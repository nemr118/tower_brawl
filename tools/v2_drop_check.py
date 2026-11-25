#!/usr/bin/env python3
# ==============================================================================
# The PAGE after a drop (the November review's bugs 1, 5, 6 and 11), in headless
# Chromium against a test server of its own. A phone page "Kid" joins and a match
# starts. Then:
#   A. the page FREEZES for 10 s (its script is paused through the debugger; the socket
#      stays open in the browser): the server must count it as a drop after 3 s (bug 5);
#      when the page runs again it must be back in its own seat by itself, with no tap
#      (bug 1). (Chromium's own "frozen" page state is no use here: it closes the
#      websocket at once, "Page entered Back-Forward Cache", which a phone does not do.)
#   B. the SERVER stops for 9 s: the lobby must not say ONE MORE STEP (bug 11: the socket
#      had been open, so the certificate is fine); a picture of what it says instead.
#   C. a new server starts: the page must take a seat again by itself (bugs 1 and 6),
#      and play: the new server must use its inputs.
#   D. a page whose socket never opens (nothing listens there): ONE MORE STEP must still
#      come (after 5 s), as before.
# The page file server must run (python3 -m http.server 8125 --bind 127.0.0.1 -d build/web).
#   ./venv/bin/python tools/v2_drop_check.py --page http://127.0.0.1:8125/v2/index.html \
#       --cert CERT.pem --key KEY.pem [--port 8115] [--admin-port 8123] [--debug-port 9411] [--out DIR]
#   --cert/--key: a TLS pair for the test server (wss: the ONE MORE STEP words only
#   come for wss). Make a throwaway pair for this: openssl req -x509 -newkey rsa:2048
#   -nodes -keyout key.pem -out cert.pem -days 2 -subj "/CN=127.0.0.1". Never the game's own.
#   --bench DIR: the server from another copy of bench/ (with --page for that copy's page).
# Pictures: <out>/drop_*.png. Exit 1 on any FAIL.
# ==============================================================================
import argparse, base64, json, os, subprocess, sys, tempfile, time, urllib.request
import websocket
from v2_chaos import Host, Server, ROOT

ap = argparse.ArgumentParser()
ap.add_argument("--page", default="http://127.0.0.1:8125/v2/index.html")
ap.add_argument("--port", type=int, default=8115)
ap.add_argument("--admin-port", type=int, default=8123)
ap.add_argument("--debug-port", type=int, default=9411)
ap.add_argument("--cert", default="")
ap.add_argument("--key", default="")
ap.add_argument("--bench", default="")
ap.add_argument("--out", default=os.path.join(ROOT, "bench_results", "drop_check"))
ap.add_argument("--extra", default="look=t1&res=0.5&nohowto", help="page options (a light page: software rendering is slow)")
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
FAILS = []
tls = (a.cert, a.key) if a.cert else None
scheme = "wss" if tls else "ws"
SARGS = ["--bots", "3", "--goal", "40", "--arena", "keep", "--season", "harvest", "--bot-level", "easy"]


def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what, flush=True)
    if not ok:
        FAILS.append(what)
    return ok


server = Server(a.port, a.admin_port, a.out, SARGS, a.bench or None, tls, "server1.log")
host = Host(a.admin_port)
prof = tempfile.mkdtemp(prefix="tb-drop-")
chrome = subprocess.Popen(["chromium", "--headless=new", "--no-first-run", "--no-default-browser-check", f"--remote-debugging-port={a.debug_port}",
                           f"--user-data-dir={prof}", "--ignore-certificate-errors", "--use-gl=angle", "--use-angle=swiftshader",
                           "--enable-unsafe-swiftshader", "--window-size=1280,720", "--touch-events=enabled", "--mute-audio", "about:blank"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
console = []
try:
    tabs = None
    for i in range(30):
        time.sleep(1)
        try:
            tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{a.debug_port}/json", timeout=3))
            break
        except Exception:
            pass
    ws = websocket.create_connection([t for t in tabs if t["type"] == "page"][0]["webSocketDebuggerUrl"], suppress_origin=True, timeout=60)
    n = [0]

    def keep(m):
        if m.get("method") == "Runtime.consoleAPICalled":
            console.append(" ".join(str(x.get("value", "")) for x in m["params"]["args"]))

    def cmd(method, **params):
        n[0] += 1
        ws.send(json.dumps({"id": n[0], "method": method, "params": params}))
        while True:
            m = json.loads(ws.recv())
            keep(m)
            if m.get("id") == n[0]:
                return m.get("result", m)

    def drain(secs):
        end = time.time() + secs
        ws.settimeout(0.3)
        while time.time() < end:
            try:
                keep(json.loads(ws.recv()))
            except websocket.WebSocketTimeoutException:
                pass
        ws.settimeout(60)

    def shot(name):
        r = cmd("Page.captureScreenshot", format="png")
        with open(os.path.join(a.out, f"drop_{name}.png"), "wb") as f:
            f.write(base64.b64decode(r["data"]))

    def kid(st=None):
        st = st or host.state()
        return next((s for s in st["seats"] if s["kind"] == 1 and s["name"] == "Kid"), None)

    def wait_state(test, secs):
        end = time.time() + secs
        while time.time() < end:
            drain(0.1)
            try:
                if test():
                    return True
            except Exception:
                pass
        return False

    cmd("Runtime.enable")
    cmd("Page.enable")
    cmd("Emulation.setDeviceMetricsOverride", width=1280, height=720, deviceScaleFactor=1, mobile=True)
    cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
    cmd("Emulation.setUserAgentOverride", userAgent="Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36")
    cmd("Page.navigate", url=f"{a.page}?server={scheme}://127.0.0.1:{a.port}&name=Kid&join&{a.extra}")
    seated = wait_state(lambda: kid() is not None, 40)
    cmd("Runtime.evaluate", expression="(function(){var g=document.getElementById('fs-gate'); if(g){g.click(); g.remove();} return 'ok'})()")
    if not check(seated, "the page joined as Kid"):
        raise SystemExit
    seat0 = kid()["i"]
    host.cmd("start")
    wait_state(lambda: host.state()["phase"] == 3, 15)

    # ------------------------------------------------------------ A: the page freezes
    drain(2.0)
    cmd("Debugger.enable")
    t0 = time.time()
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": "Debugger.pause", "params": {}}))    # (no waiting for an answer from a paused page)
    held = wait_state(lambda: not kid()["online"], 9.0)
    t_held = time.time() - t0
    drain(max(0.0, t0 + 10.0 - time.time()))
    mid = kid()
    t1 = time.time()
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": "Debugger.resume", "params": {}}))
    back = wait_state(lambda: kid() is not None and kid()["online"], 12.0)
    cmd("Debugger.disable")
    t_back = time.time() - t1
    now = kid()
    with open(server.log_path, errors="replace") as f:
        log1 = f.read()
    check(held and 2.5 <= t_held <= 5.0 and "went silent" in log1,
          f"A (bug 5) the page freezes: the server counts it as a drop {t_held:.1f} s later (3 s wanted) and says 'went silent': {'went silent' in log1}")
    check(mid is not None and mid["i"] == seat0 and not mid["online"], f"A (bug 1) 10 s into the freeze the seat is still Kid's, held ({mid['held_s'] if mid else '-'} s more)")
    check(back and now is not None and now["i"] == seat0,
          f"A (bug 1) the page wakes: back in its own seat {t_back:.1f} s later with no tap (seat {now['i'] if now else None}, it was {seat0}; points {now['points'] if now else '-'})")
    shot("A_back_after_freeze")

    # ------------------------------------------------------------ B: the server stops
    drain(2.0)
    lines_before = len(console)
    server.stop()
    drain(9.0)
    shot("B_server_gone_9s")
    said = [c for c in console[lines_before:] if "ONE MORE STEP" in c]
    check(not said, f"B (bug 11) the server is gone for 9 s after the socket had been open: the lobby does not say ONE MORE STEP ({len(said)} such console lines)")

    # ------------------------------------------------------------ C: a new server
    server = Server(a.port, a.admin_port, a.out, SARGS, a.bench or None, tls, "server2.log")
    t2 = time.time()
    again = wait_state(lambda: kid() is not None and kid()["online"], 20.0)
    t_again = time.time() - t2
    k2 = kid()
    check(again, f"C (bugs 1, 6) a new server starts: the page takes a seat again by itself {t_again:.1f} s later (seat {k2['i'] if k2 else None}, it had {seat0}), no tap")
    shot("C_back_on_new_server")
    host.cmd("start")
    wait_state(lambda: host.state()["phase"] == 3, 15)
    drain(8.0)
    with open(server.log_path, errors="replace") as f:
        log2 = f.read()
    # the server's report line every 5 s: "late seat:inputs/late" for each person
    used = 0
    for line in log2.splitlines():
        if "📊" in line and "| late " in line:
            for part in line.split("| late ")[1].split():
                if part.startswith(f"{k2['i'] if k2 else -1}:"):
                    used = max(used, int(part.split(":")[1].split("/")[0]))
    check(used >= 100, f"C (bug 6) the page plays on the new server: it used {used} of the page's inputs in one 5 s report (300 is all of them; 0 or 1: none)")

    # ------------------------------------------------------------ D: a socket that never opens
    lines_before = len(console)
    cmd("Page.navigate", url=f"{a.page}?server=wss://127.0.0.1:{a.port + 4}&name=Kid2&{a.extra}")
    drain(8.0)
    cmd("Runtime.evaluate", expression="(function(){var g=document.getElementById('fs-gate'); if(g){g.click(); g.remove();} return 'ok'})()")
    t_d = time.time()
    while time.time() - t_d < 25.0 and not any("ONE MORE STEP" in c for c in console[lines_before:]):
        drain(0.5)
    drain(1.0)
    said = [c for c in console[lines_before:] if "ONE MORE STEP" in c]
    shot("D_never_opened")
    check(len(said) == 1, f"D (bug 11) a page whose socket never opens still says ONE MORE STEP after 5 s: {said[0][:110] if said else 'NO such line'}")
    with open(os.path.join(a.out, "console.log"), "w") as f:
        f.write("\n".join(console))
finally:
    chrome.terminate()
    try:
        chrome.wait(5)
    except subprocess.TimeoutExpired:
        chrome.kill()
    server.stop()
print("✅ v2_drop_check: every check passed" if not FAILS else f"❌ v2_drop_check: {len(FAILS)} FAIL", flush=True)
sys.exit(1 if FAILS else 0)
