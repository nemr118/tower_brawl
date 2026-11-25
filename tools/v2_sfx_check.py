#!/usr/bin/env python3
# ==============================================================================
# The sound check (p4.19): proof without ears. Chromium headless, MUTED
# (--mute-audio: nothing reaches the speakers), opens the game's page and
# watches a match. It counts three things:
#   1. the page's own lines, one per sound (?sfxlog: "🔊 [Sfx] name"),
#   2. what the browser's sound machine was really asked to do: sounds started
#      (AudioBufferSourceNode.start), sound data made (createBuffer),
#   3. what came out of the game towards the speakers: the loudest sample on
#      the left and on the right (1.0 is the most there is: over it, it clips).
# And the page's errors. With --sound 0 the same match must show no sound work.
#
#   ./venv/bin/python tools/v2_sfx_check.py --out /tmp/sfx/on  --sound 1
#   ./venv/bin/python tools/v2_sfx_check.py --out /tmp/sfx/off --sound 0
#   --tv: THE BIG SCREEN (no seat; start the server with --soak so matches run)
#   --phone [--ios]: a phone's page (touch, its user agent)
#   --lock: the browser's real rule (no sound before a tap); the check waits
#           --lock-wait s with the match on, then taps once and goes on
#   --sound default: no ?sound= option (the device's own default)
# Start first: a page server (python3 -m http.server 8155 --bind 127.0.0.1 -d build/web)
# and a game server (--no-tls --port 8140 --bots 7). Needs the venv's websocket-client.
# ==============================================================================
import argparse, base64, json, os, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request
import websocket

ap = argparse.ArgumentParser()
ap.add_argument("--url", default="http://127.0.0.1:8155/v2/index.html")
ap.add_argument("--server", default="ws://127.0.0.1:8140")
ap.add_argument("--out", default="/tmp/v2sfx")
ap.add_argument("--name", default="Ear")
ap.add_argument("--sound", default="1", help="1, 0, or default (no ?sound= option)")
ap.add_argument("--tv", action="store_true", help="THE BIG SCREEN: no seat, no START tap")
ap.add_argument("--phone", action="store_true")
ap.add_argument("--ios", action="store_true")
ap.add_argument("--lock", action="store_true", help="keep the browser's rule: no sound before a tap")
ap.add_argument("--lock-wait", type=float, default=20.0, help="with --lock: seconds to watch before the tap")
ap.add_argument("--gate-tap", action="store_true", help="with --phone --lock: the one tap goes on the full-screen sign")
ap.add_argument("--no-start", action="store_true", help="do not tap START (a server with --soak starts matches by itself)")
ap.add_argument("--host-start", type=int, default=0, help="after the tap on START, also ask the server's host port (--admin-port N) to start: a tap on a page that was still loading is lost")
ap.add_argument("--until", default="[Replay]", help="stop at the first page console line with this text (the page prints [Replay] when the match ends)")
ap.add_argument("--after", type=float, default=8.0, help="seconds to go on after that line (the fanfare)")
ap.add_argument("--timeout", type=float, default=400.0)
ap.add_argument("--extra", default="", help="more page options, a=1&b=2")
ap.add_argument("--port", type=int, default=9440)
ap.add_argument("--wait", type=float, default=9.0, help="seconds for the page to load and join")
ap.add_argument("--shot", action="store_true", help="a picture at the end: <out>_end.png")
a = ap.parse_args()
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

W, H = 1280, 720
# The probe runs in the page before the game does. It only counts and listens:
# every call goes on to the browser's own function unchanged.
PROBE = r"""
(function () {
	const S = window.__tbSfx = { buffers: 0, bufferFrames: 0, sources: 0, starts: 0, startsWhileLocked: 0,
		peakL: 0, peakR: 0, polls: 0, loudPolls: 0, sumSq: 0, sumN: 0, taps: 0, rate: 0, meter: null };
	// The meter: a tiny program on the browser's sound thread. It sees every sample that
	// goes towards the speakers (the page's own timers are too slow for that on a busy PC).
	const METER = `class TbMeter extends AudioWorkletProcessor {
		constructor() { super(); this.m = { peakL: 0, peakR: 0, sumSq: 0, n: 0, blocks: 0, loudBlocks: 0 };
			this.port.onmessage = () => this.port.postMessage(this.m); }
		process(inputs) {
			const inp = inputs[0], m = this.m;
			m.blocks++;
			if (inp && inp.length) {
				const L = inp[0], R = inp[1] || inp[0];
				let top = 0;
				for (let i = 0; i < L.length; i++) {
					const l = Math.abs(L[i]), r = Math.abs(R[i]);
					if (l > m.peakL) { m.peakL = l; }
					if (r > m.peakR) { m.peakR = r; }
					if (l > top) { top = l; }
					if (r > top) { top = r; }
					m.sumSq += L[i] * L[i] + R[i] * R[i];
				}
				m.n += 2 * L.length;
				if (top > 0.003) { m.loudBlocks++; }
			}
			return true;
		}
	}
	registerProcessor('tb-meter', TbMeter);`;
	let meterNode = null;
	const tapped = [];
	const AC = window.AudioContext || window.webkitAudioContext;
	if (!AC) { S.none = true; return; }
	const base = (window.BaseAudioContext || AC).prototype;
	const createBuffer = base.createBuffer;
	base.createBuffer = function (ch, len) { S.buffers++; S.bufferFrames += len * ch; return createBuffer.apply(this, arguments); };
	const createSource = base.createBufferSource;
	base.createBufferSource = function () { S.sources++; return createSource.apply(this, arguments); };
	const start = AudioBufferSourceNode.prototype.start;
	AudioBufferSourceNode.prototype.start = function () {
		S.starts++;
		if (this.context.state !== 'running') { S.startsWhileLocked++; }
		return start.apply(this, arguments);
	};
	const connect = AudioNode.prototype.connect;
	let split = null, aL = null, aR = null, bL = null, bR = null;
	function poll() {
		aL.getFloatTimeDomainData(bL);
		aR.getFloatTimeDomainData(bR);
		let m = 0;
		for (let i = 0; i < bL.length; i++) {
			const l = Math.abs(bL[i]), r = Math.abs(bR[i]);
			if (l > S.peakL) { S.peakL = l; }
			if (r > S.peakR) { S.peakR = r; }
			if (l > m) { m = l; }
			if (r > m) { m = r; }
		}
		// the newest 50 ms only, for the average level (the windows overlap)
		const n = Math.floor(aL.context.sampleRate * 0.05);
		for (let i = bL.length - n; i < bL.length; i++) { S.sumSq += bL[i] * bL[i] + bR[i] * bR[i]; }
		S.sumN += 2 * n;
		S.polls++;
		if (m > 0.003) { S.loudPolls++; }
	}
	AudioNode.prototype.connect = function (dest) {
		const out = connect.apply(this, arguments);
		try {
			if (dest === this.context.destination) {
				const ctx = this.context;
				if (!split) {
					split = ctx.createChannelSplitter(2);
					aL = ctx.createAnalyser();
					aR = ctx.createAnalyser();
					aL.fftSize = aR.fftSize = 8192;
					bL = new Float32Array(aL.fftSize);
					bR = new Float32Array(aR.fftSize);
					connect.call(split, aL, 0);
					connect.call(split, aR, 1);
					S.rate = ctx.sampleRate;
					setInterval(poll, 50);
					ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([METER], { type: 'application/javascript' }))).then(function () {
						meterNode = new AudioWorkletNode(ctx, 'tb-meter', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
							channelCount: 2, channelCountMode: 'explicit', channelInterpretation: 'speakers' });
						meterNode.port.onmessage = function (ev) { S.meter = ev.data; };
						for (const n of tapped) { connect.call(n, meterNode); }
						connect.call(meterNode, ctx.destination);      // it sends silence on: the browser keeps it running
						setInterval(function () { meterNode.port.postMessage(0); }, 500);
					}).catch(function (e) { S.meterError = String(e); });
				}
				connect.call(this, split);
				tapped.push(this);
				if (meterNode) { connect.call(this, meterNode); }
				S.taps++;
			}
		} catch (e) { S.tapError = String(e); }
		return out;
	};
}());
"""

prof = tempfile.mkdtemp(prefix="tb-v2sfx-")
os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
chrome_log = open(f"{a.out}_chrome.log", "w")
flags = [
    "chromium", "--headless=new", "--no-first-run", "--no-default-browser-check", "--mute-audio",
    f"--remote-debugging-port={a.port}", f"--user-data-dir={prof}",
    "--ignore-certificate-errors", "--use-gl=angle", "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader", "--enable-logging=stderr", "--v=0", f"--window-size={W},{H}"]
if not a.lock:
    flags.append("--autoplay-policy=no-user-gesture-required")
if a.phone:
    flags.append("--touch-events=enabled")
flags.append("about:blank")
chrome = subprocess.Popen(flags, stdout=subprocess.DEVNULL, stderr=chrome_log)
print("chromium pid", chrome.pid, flush=True)
tabs = None
for i in range(30):
    time.sleep(1)
    try:
        tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{a.port}/json", timeout=3))
        break
    except Exception:
        pass
if not tabs:
    print("Chromium never opened its debug port", file=sys.stderr)
    chrome.kill()
    sys.exit(1)
page = [t for t in tabs if t.get("type") == "page"][0]
ws = websocket.create_connection(page["webSocketDebuggerUrl"], suppress_origin=True, timeout=40)
_id = [0]
console = []     # (seconds since the start, text)
errors = []      # console.error, script errors, the browser's own error lines
t0 = time.time()


def note(m):
    k = m.get("method")
    if k == "Runtime.consoleAPICalled":
        p = m["params"]
        text = " ".join(str(x.get("value", x.get("description", ""))) for x in p.get("args", []))
        console.append((time.time() - t0, text))
        if p.get("type") in ("error", "assert"):
            errors.append("console.error: " + text[:300])
    elif k == "Runtime.exceptionThrown":
        d = m["params"].get("exceptionDetails", {})
        errors.append("exception: " + str(d.get("exception", {}).get("description", d.get("text", "")))[:300])
    elif k == "Log.entryAdded":
        e = m["params"].get("entry", {})
        if e.get("level") == "error":
            errors.append("browser: " + str(e.get("text", ""))[:300] + " " + str(e.get("url", ""))[-80:])


def cmd(method, **params):
    _id[0] += 1
    ws.send(json.dumps({"id": _id[0], "method": method, "params": params}))
    while True:
        m = json.loads(ws.recv())
        note(m)
        if m.get("id") == _id[0]:
            return m.get("result", m)


def drain(secs):
    end = time.time() + secs
    ws.settimeout(0.5)
    while time.time() < end:
        try:
            note(json.loads(ws.recv()))
        except websocket.WebSocketTimeoutException:
            continue
    ws.settimeout(40)


def js(expr):
    r = cmd("Runtime.evaluate", expression=expr, returnByValue=True)
    return r.get("result", {}).get("value")


def probe(mark=""):
    # mark: the page also prints this line, so the page's lines can be counted up to the same moment
    say = ("console.log(%s);" % json.dumps(mark)) if mark else ""
    s = js("(function(){ var s = JSON.stringify(Object.assign({}, window.__tbSfx || {}, {state: (window.tbAudio && window.tbAudio.state) || 'none'})); %s return s; })()" % say)
    return json.loads(s) if s else {}


# A real tap or click (the browser counts it as the player's): x, y in page pixels.
def tap_px(x, y):
    if a.phone:
        pt = {"x": x, "y": y, "radiusX": 8, "radiusY": 8, "force": 1, "id": 1}
        cmd("Input.dispatchTouchEvent", type="touchStart", touchPoints=[pt])
        time.sleep(0.08)
        cmd("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
    else:
        cmd("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y)
        cmd("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
        time.sleep(0.08)
        cmd("Input.dispatchMouseEvent", type="mouseReleased", x=x, y=y, button="left", clickCount=1)


# A point of the 1920 x 1080 design (the page scales by height and centres).
def tap(dx, dy):
    k = H / 1080.0
    tap_px((W - 1920 * k) / 2 + dx * k, dy * k)


def sfx_lines(lines):
    counts = {}
    for _t, c in lines:
        if "[Sfx] " in c:
            word = c.split("[Sfx] ", 1)[1].split(" ")[0]
            counts[word] = counts.get(word, 0) + 1
    return counts


# What each play cost the page, from its lines ("🔊 [Sfx] name 0.21 ms [first] [own]").
def sfx_costs(lines):
    first, again = [], []
    for _t, c in lines:
        if "[Sfx] " in c and " ms" in c:
            parts = c.split("[Sfx] ", 1)[1].split(" ")
            try:
                (first if "first" in parts else again).append(float(parts[1]))
            except (ValueError, IndexError):
                pass
    return first, again


cmd("Runtime.enable")
cmd("Page.enable")
cmd("Log.enable")
cmd("Page.addScriptToEvaluateOnNewDocument", source=PROBE)
if a.phone:
    cmd("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=1, mobile=True)
    cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
    ua = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
          if a.ios else "Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36")
    cmd("Emulation.setUserAgentOverride", userAgent=ua)
else:
    cmd("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=1, mobile=False)
opts = [f"server={a.server}", "info", "sfxlog", "nohowto"]
opts += ["tv"] if a.tv else [f"name={a.name}", "join"]
if a.sound != "default":
    opts.append(f"sound={a.sound}")
if a.extra:
    opts.append(a.extra)
url = f"{a.url}?" + "&".join(opts)
print("page:", url, flush=True)
cmd("Page.navigate", url=url)
drain(a.wait)
t_boot = time.time() + 90.0          # a busy PC: wait for the game's first line before any tap
while time.time() < t_boot and not any("[Client]" in c for _t, c in console):
    drain(1.0)
drain(3.0)
result = {"url": url, "lock": a.lock}
gate = js("(function(){var g=document.getElementById('fs-gate'); return !!(g && g.classList.contains('show'))})()")
result["gate_shown"] = bool(gate)
if a.lock:
    # the match runs, the page asks for sounds, the browser is still locked: nothing may start
    if not a.tv and not a.no_start and not a.gate_tap:
        pass     # (a seated page with the lock: START below is the first tap)
    drain(a.lock_wait if (a.tv or a.no_start) else 1.0)
    before = probe()
    result["before_tap"] = before
    result["sfx_lines_before_tap"] = sum(len(v) for v in sfx_costs(console))     # lines of sounds really played
    result["errors_before_tap"] = len(errors)
    print("before the tap:", json.dumps(before), "| page sound lines:", result["sfx_lines_before_tap"], "| errors:", len(errors), flush=True)
    if a.gate_tap and gate:
        tap_px(W / 2, H / 2)             # on the "Tap to play full screen" sign
        drain(1.5)
        result["after_gate_tap"] = probe()
        print("after the tap on the full-screen sign:", json.dumps(result["after_gate_tap"]), flush=True)
    elif a.tv or a.no_start:
        tap(960, 300)                    # anywhere on the game
        drain(1.5)
        result["after_first_tap"] = probe()
        print("after the first tap:", json.dumps(result["after_first_tap"]), flush=True)
if gate and not (a.lock and a.gate_tap):
    js("(function(){var g=document.getElementById('fs-gate'); if(g){g.remove();} return 'ok'})()")
    drain(0.5)
mark = len(console)
if not a.tv and not a.no_start:
    tap(1230, 854)      # START (lobby.gd: the big button at 920..1860 x 798..952)
    if a.host_start:
        drain(2.0)
        try:
            urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{a.host_start}/start", data=b"{}", method="POST"), timeout=5).read()
        except urllib.error.HTTPError:
            pass     # the server says no: the tap on START already started the match
        except Exception as e:
            print("host start:", e, flush=True)
    if a.lock:
        drain(1.5)
        result["after_start_tap"] = probe()
        print("after the tap on START:", json.dumps(result["after_start_tap"]), flush=True)
t_end = time.time() + a.timeout
hit = False
while time.time() < t_end:
    drain(0.5)
    if any(a.until in c for _t, c in console[mark:]):
        hit = True
        break
drain(a.after)
result["until_seen"] = hit
if a.shot:
    r = cmd("Page.captureScreenshot", format="png")
    with open(f"{a.out}_end.png", "wb") as f:
        f.write(base64.b64decode(r["data"]))
final = probe("[SfxCheck] end")
drain(1.0)
end = next((i for i, (_t, c) in enumerate(console) if "[SfxCheck] end" in c), len(console))
console = console[:end]
result["probe"] = final
result["sfx_lines"] = sfx_lines(console)
result["page_errors"] = errors
result["page_err_list"] = js("JSON.stringify(window.__tbErrs || [])")
try:
    result["heap"] = cmd("Runtime.getHeapUsage")
    cmd("Performance.enable")
    result["metrics"] = {m["name"]: m["value"] for m in cmd("Performance.getMetrics").get("metrics", [])
                         if m["name"] in ("JSHeapUsedSize", "JSHeapTotalSize", "Nodes", "AudioHandlers", "JSEventListeners")}
except Exception as e:
    result["heap_error"] = str(e)
with open(f"{a.out}_console.log", "w") as f:
    f.write("\n".join("%7.2f %s" % (t, c) for t, c in console))
with open(f"{a.out}_sfx.json", "w") as f:
    json.dump(result, f, indent=1)

counts = result["sfx_lines"]
names = sorted((k for k in counts if k not in ("sound", "unlocked:", "locked:", "no")), key=lambda k: -counts[k])
print("")
print("the page's own lines:", " ".join(c for _t, c in console if "[Sfx] sound" in c or "[Sfx] unlocked" in c or "[Sfx] locked" in c or "[Sfx] no " in c) or "(none)")
print("until %r seen: %s after %.0f s" % (a.until, hit, time.time() - t0))
print("sounds played (the page's lines): %d in all, %d different" % (sum(counts[k] for k in names), len(names)))
for k in names:
    print("   %-16s %d" % (k, counts[k]))
first, again = sfx_costs(console)
for label, vals in (("the first play of a sound (it loads)", first), ("every later play", again)):
    if vals:
        vals = sorted(vals)
        print("what a play costs the page, %s: %d plays, median %.2f ms, 95%% under %.2f ms, the worst %.2f ms" % (
            label, len(vals), vals[len(vals) // 2], vals[int(len(vals) * 0.95)], vals[-1]))
if final:
    print("the browser: %d sounds started (%d while locked), %d sound buffers made (%.1f MB of samples in all), sound machine '%s' at %d Hz" % (
        final.get("starts", 0), final.get("startsWhileLocked", 0), final.get("buffers", 0),
        final.get("bufferFrames", 0) * 4 / 1048576.0, final.get("state"), final.get("rate", 0)))
    m = final.get("meter")
    if m:
        rms = (m["sumSq"] / m["n"]) ** 0.5 if m.get("n") else 0.0
        print("towards the speakers (every sample, %.0f s of sound time): peak left %.3f, right %.3f (1.0 clips); average level %.4f; sound in %.1f%% of the time" % (
            m["blocks"] * 128.0 / max(1, final.get("rate", 48000)), m["peakL"], m["peakR"], rms, 100.0 * m["loudBlocks"] / max(1, m["blocks"])))
    else:
        rms = (final.get("sumSq", 0) / final["sumN"]) ** 0.5 if final.get("sumN") else 0.0
        print("towards the speakers (a listen now and then: %d listens, %s): peak left %.3f, right %.3f (1.0 clips); average level %.4f" % (
            final.get("polls", 0), final.get("meterError", "no meter"), final.get("peakL", 0), final.get("peakR", 0), rms))
print("page errors: %d" % len(errors))
for e in errors[:10]:
    print("   ", e)
if "heap" in result:
    h = result["heap"]
    print("memory (the browser's count): JS heap %.1f MB used; buffers outside it %.1f MB" % (
        h.get("usedSize", 0) / 1048576.0, h.get("backingStorageSize", 0) / 1048576.0))
ws.close()
chrome.terminate()
try:
    chrome.wait(5)
except subprocess.TimeoutExpired:
    chrome.kill()
shutil.rmtree(prof, ignore_errors=True)      # the browser's throw-away profile
