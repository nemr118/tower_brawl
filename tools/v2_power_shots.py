#!/usr/bin/env python3
"""The power-ups (p4.9) in headless Chromium: pictures of a match while it plays.

A test server (wss on --server, its host port --host; for every look at once start
it with --pu-gallery) and the Python service (the page) must run. The page joins as an
Android phone ("Cam"), the host port starts the match, and once the round plays the
page is pictured every --every seconds for --secs: <out>_pw_NN.png. The page's errors
(console.error, uncaught) are printed; exit 1 when there were any.

    ./venv/bin/python tools/v2_power_shots.py --out /tmp/pw --secs 12 --every 1
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
ap.add_argument("--out", default="/tmp/pw")
ap.add_argument("--every", type=float, default=1.0)
ap.add_argument("--secs", type=float, default=12.0)
ap.add_argument("--wait", type=float, default=0.0, help="seconds of play before the first picture")
ap.add_argument("--look", default="", help="the page's look: low, normal or high (default: the page's AUTO)")
ap.add_argument("--port", type=int, default=9338)
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
errors = []
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
    cmd("Page.navigate", url=f"{a.url}?server={a.server}&name=Cam&join" + (f"&look={a.look}" if a.look else ""))
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
    while time.time() - t0 < 60:
        drain(0.3)
        if host("/state")["phase_name"] == "PLAYING":
            break
    drain(a.wait)
    k = 0
    t1 = time.time()
    while time.time() - t1 < a.secs:
        r = cmd("Page.captureScreenshot", format="png")
        with open(f"{a.out}_pw_{k:02d}.png", "wb") as f:
            f.write(base64.b64decode(r["data"]))
        k += 1
        drain(a.every)
    r = cmd("Runtime.evaluate", expression="JSON.stringify(window.__tbErrs || [])", returnByValue=True)
    errors = json.loads(r["result"]["value"] or "[]")
finally:
    chrome.kill()
for c in console:
    if "ERROR" in c or "error" in c.lower()[:40]:
        print("  console: " + c[:200])
for e in errors:
    print("  page error: " + str(e)[:200])
print(f"{k} pictures: {a.out}_pw_NN.png; page errors: {len(errors)}")
sys.exit(1 if errors else 0)
