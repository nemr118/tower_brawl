#!/usr/bin/env python3
"""The deathcam (p4.8) in headless Chromium: a quick match to its end, with pictures.

A test server (wss on --server, its host port --host; start it with --goal 2 for a
short match) and the Python service (the page) must run. The page joins as an
Android phone ("Cam"), the host port starts the match, and once the server is in
MATCH END the page is pictured every --every seconds for 12 s: <out>_cam_NN.png.
The page's console is kept: the "🎬 [Deathcam]" lines say if the montage played.
With --skip-after N the page taps its SKIP button N s into the montage: the
server must be back in the LOBBY within 3 s. Exit 1 when no montage line came
(or the skip did not bring the lobby back).

    ./venv/bin/python tools/v2_deathcam_check.py --out /tmp/cam
"""
import argparse
import base64
import json
import subprocess
import sys
import tempfile
import time
import urllib.request

import websocket

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--url", default="https://127.0.0.1:8443/v2/index.html")
ap.add_argument("--server", default="wss://127.0.0.1:8091")
ap.add_argument("--host", default="http://127.0.0.1:8092")
ap.add_argument("--out", default="/tmp/cam")
ap.add_argument("--every", type=float, default=1.0)
ap.add_argument("--port", type=int, default=9337)
ap.add_argument("--skip-after", type=float, default=-1.0)
a = ap.parse_args()


def host(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(a.host + path, data=data, method="GET" if body is None else "POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read())


prof = tempfile.mkdtemp(prefix="tb-cam-")
chrome = subprocess.Popen(["chromium", "--headless=new", "--no-first-run", f"--remote-debugging-port={a.port}",
                           f"--user-data-dir={prof}", "--ignore-certificate-errors", "--use-gl=angle", "--use-angle=swiftshader",
                           "--enable-unsafe-swiftshader", "--window-size=1280,720", "--touch-events=enabled", "about:blank"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
console = []
try:
    tabs = None
    for i in range(30):
        time.sleep(1)
        try:
            tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{a.port}/json", timeout=3))
            break
        except Exception:
            pass
    ws = websocket.create_connection([t for t in tabs if t["type"] == "page"][0]["webSocketDebuggerUrl"], suppress_origin=True, timeout=40)
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
        ws.settimeout(40)

    cmd("Runtime.enable")
    cmd("Page.enable")
    cmd("Emulation.setDeviceMetricsOverride", width=1280, height=720, deviceScaleFactor=1, mobile=True)
    cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
    cmd("Emulation.setUserAgentOverride", userAgent="Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36")
    cmd("Page.navigate", url=f"{a.url}?server={a.server}&name=Cam&join")
    for i in range(60):
        drain(0.5)
        try:
            if any(s["name"] == "Cam" and s["who"] == "person" for s in host("/state")["seats"]):
                break
        except Exception:
            pass
    cmd("Runtime.evaluate", expression="(function(){var g=document.getElementById('fs-gate'); if(g){g.click(); g.remove();} return 'ok'})()")
    host("/start", {})
    t0 = time.time()
    while time.time() - t0 < 400:
        drain(0.5)
        st = host("/state")
        if st["phase_name"] == "MATCH END":
            break
    print(f"match end after {time.time() - t0:.0f} s, round {st['round']}", flush=True)
    k = 0
    t1 = time.time()
    skipped_ok = None
    while time.time() - t1 < 12.0:
        r = cmd("Page.captureScreenshot", format="png")
        with open(f"{a.out}_cam_{k:02d}.png", "wb") as f:
            f.write(base64.b64decode(r["data"]))
        k += 1
        drain(a.every)
        if a.skip_after >= 0 and skipped_ok is None and time.time() - t1 >= a.skip_after:
            kk = 720 / 1080.0   # the SKIP button's middle, (1740, 996) of the 1920 x 1080 arena
            pt = {"x": (1280 - 1920 * kk) / 2 + 1740 * kk, "y": 996 * kk, "radiusX": 8, "radiusY": 8, "force": 1, "id": 3}
            cmd("Input.dispatchTouchEvent", type="touchStart", touchPoints=[pt])
            time.sleep(0.08)
            cmd("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
            t_skip = time.time()
            skipped_ok = False
            while time.time() - t_skip < 3.0:
                drain(0.25)
                if host("/state")["phase_name"] == "LOBBY":
                    skipped_ok = True
                    print(f"SKIP tapped {t_skip - t1:.1f} s into the montage: the lobby came back {time.time() - t_skip:.1f} s later", flush=True)
                    break
            r = cmd("Page.captureScreenshot", format="png")
            with open(f"{a.out}_cam_after_skip.png", "wb") as f:
                f.write(base64.b64decode(r["data"]))
            break
finally:
    chrome.kill()
lines = [c for c in console if "Deathcam" in c]
for c in lines:
    print("  " + c)
print(f"{k} pictures: {a.out}_cam_NN.png")
ok = any("montage" in c for c in lines) and (a.skip_after < 0 or skipped_ok)
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
