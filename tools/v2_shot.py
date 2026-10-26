#!/usr/bin/env python3
# ==============================================================================
# Screenshots of the new game's WEB page (P1): Chromium headless with a debug
# port, driven over CDP, against the Python service (https://127.0.0.1:8443/v2/)
# and a game server on wss://127.0.0.1:8091 (start both first). The page joins
# as a player, the lobby is shot, START is tapped, the round's first banner and
# the fight with the HUD are shot. --phone adds touch emulation and a phone
# user agent, so the twin sticks show.
#
#   ./venv/bin/python tools/v2_shot.py --out /tmp/v2shot            # PC: lobby, round, fight
#   ./venv/bin/python tools/v2_shot.py --out /tmp/v2shot_phone --phone [--ios]
#   --extra "slow=25&lag=60": more page options; --ios: an iPhone's browser (with --phone)
#   -> <out>_lobby.png, <out>_round.png, <out>_fight.png; the page's console in <out>_chrome.log
# Needs the venv's websocket-client. The game server should have bots (--bots 7
# is the default) so a START with one person makes a match.
# ==============================================================================
import argparse, base64, json, os, subprocess, sys, tempfile, time, urllib.request
import websocket

ap = argparse.ArgumentParser()
ap.add_argument("--url", default="https://127.0.0.1:8443/v2/index.html")
ap.add_argument("--server", default="wss://127.0.0.1:8091")
ap.add_argument("--out", default="/tmp/v2shot")
ap.add_argument("--name", default="Shot")
ap.add_argument("--phone", action="store_true")
ap.add_argument("--ios", action="store_true", help="with --phone: an iPhone's user agent (the page starts on LOW)")
ap.add_argument("--extra", default="", help="more page options, a=1&b=2")
ap.add_argument("--watch", type=float, default=0.0, help="after the fight shots, wait this long and shoot <out>_late.png")
ap.add_argument("--look-tap", action="store_true", help="tap the lobby's LOOK button once, then reload the page (the pick is kept)")
ap.add_argument("--lobby-tap", default="", help="X,Y in the 1920 x 1080 design: tap there in the lobby and shoot <out>_lobby_tap.png, then tap it again (2026-10-26: the ARENA picker is 320,732)")
ap.add_argument("--port", type=int, default=9334)
ap.add_argument("--wait", type=float, default=9.0, help="seconds for the page to load and join")
ap.add_argument("--round-wait", type=float, default=4.3, help="seconds from START to the round shot (3 s countdown + the ROUND banner; less on a slow page)")
a = ap.parse_args()
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

W, H = 1280, 720
prof = tempfile.mkdtemp(prefix="tb-v2shot-")
chrome_log = open(f"{a.out}_chrome.log", "w")
flags = [
    "chromium", "--headless=new", "--no-first-run", "--no-default-browser-check",
    f"--remote-debugging-port={a.port}", f"--user-data-dir={prof}",
    "--ignore-certificate-errors", "--use-gl=angle", "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader", "--enable-logging=stderr", "--v=0",
    f"--window-size={W},{H}", "--autoplay-policy=no-user-gesture-required"]
if a.phone:
    flags.append("--touch-events=enabled")
flags.append("about:blank")
chrome = subprocess.Popen(flags, stdout=subprocess.DEVNULL, stderr=chrome_log)
tabs = None
for i in range(30):
    time.sleep(1)
    try:
        tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{a.port}/json", timeout=3))
        break
    except Exception as e:
        print("waiting for the debug port", i, e, flush=True)
if not tabs:
    print("Chromium never opened its debug port", file=sys.stderr)
    chrome.kill()
    sys.exit(1)
page = [t for t in tabs if t.get("type") == "page"][0]
ws = websocket.create_connection(page["webSocketDebuggerUrl"], suppress_origin=True, timeout=40)
_id = [0]
console = []

def cmd(method, **params):
    _id[0] += 1
    ws.send(json.dumps({"id": _id[0], "method": method, "params": params}))
    while True:
        m = json.loads(ws.recv())
        if m.get("method") == "Runtime.consoleAPICalled":
            args = m["params"].get("args", [])
            console.append(" ".join(str(x.get("value", x.get("description", ""))) for x in args))
        if m.get("id") == _id[0]:
            return m.get("result", m)

def drain(secs):
    end = time.time() + secs
    ws.settimeout(0.5)
    while time.time() < end:
        try:
            m = json.loads(ws.recv())
        except websocket.WebSocketTimeoutException:
            continue
        if m.get("method") == "Runtime.consoleAPICalled":
            args = m["params"].get("args", [])
            console.append(" ".join(str(x.get("value", x.get("description", ""))) for x in args))
    ws.settimeout(40)

def shot(name):
    r = cmd("Page.captureScreenshot", format="png")
    with open(f"{a.out}_{name}.png", "wb") as f:
        f.write(base64.b64decode(r["data"]))
    print("shot", name, flush=True)

# A tap or click at a point of the 1920 x 1080 design (the page scales by height and centres).
def tap(dx, dy):
    k = H / 1080.0
    x = (W - 1920 * k) / 2 + dx * k
    y = dy * k
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

cmd("Runtime.enable")
cmd("Page.enable")
if a.phone:
    cmd("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=1, mobile=True)
    cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
    ua = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
          if a.ios else "Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36")
    cmd("Emulation.setUserAgentOverride", userAgent=ua)
else:
    cmd("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=1, mobile=False)
url = f"{a.url}?server={a.server}&name={a.name}&join&info" + (f"&{a.extra}" if a.extra else "")
cmd("Page.navigate", url=url)
drain(a.wait)
# the old shell's full-screen gate ("Tap to play full screen") sits over the canvas on a phone: tap it away
cmd("Runtime.evaluate", expression="(function(){var g=document.getElementById('fs-gate'); if(g){g.click(); g.remove();} return 'ok'})()")
drain(1.0)
shot("lobby")
if a.look_tap:
    tap(1700, 54)       # LOOK (lobby.gd since 2026-10-25: the button at the top right, 1540..1860 x 18..90)
    drain(1.5)
    shot("lobby_look")
    cmd("Page.reload")
    drain(a.wait)
    cmd("Runtime.evaluate", expression="(function(){var g=document.getElementById('fs-gate'); if(g){g.click(); g.remove();} return 'ok'})()")
    drain(1.0)
    shot("lobby_reload")
if a.lobby_tap:
    lx, ly = (float(v) for v in a.lobby_tap.split(","))
    tap(lx, ly)
    drain(1.0)
    shot("lobby_tap")
    tap(960, 1060)      # a tap at the bottom edge: a picker or a menu closes
    drain(0.8)
tap(1230, 854)          # START (lobby.gd since 2026-10-25: the big button at 920..1860 x 798..952)
drain(a.round_wait)     # 3 s countdown + the ROUND 1 banner
shot("round")
drain(2.5)              # FIGHT
shot("fight")
drain(4.0)
shot("fight2")
if a.watch > 0:
    drain(a.watch)
    shot("late")
with open(f"{a.out}_console.log", "w") as f:
    f.write("\n".join(console))
joined = any("[Client]" in c for c in console)
print("console lines:", len(console), "| client booted:", joined)
for c in console[:12]:
    print("  ", c[:160])
ws.close()
chrome.terminate()
try:
    chrome.wait(5)
except subprocess.TimeoutExpired:
    chrome.kill()
