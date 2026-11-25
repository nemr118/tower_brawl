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
With --skip-test (2026-11-24, the November review's bug 8: SKIP wakes 2 s in, at
the top in the middle): a tap on SKIP's spot 1 s into the montage and a tap on
its OLD spot (the bottom right corner, where right thumbs play) at 2.6 s must
NOT skip; then a picture, then a tap on SKIP: the lobby within 3 s.

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
ap.add_argument("--skip-test", action="store_true")
ap.add_argument("--extra", default="", help="more page options, a=1&b=2 (look=t1&res=0.5: a faster page in software rendering)")
ap.add_argument("--first-tap", default="new", help="with --skip-test: 'old' taps the OLD spot first, 0.9 s in (a page from before 2026-11-24 skips there)")
a = ap.parse_args()
SKIP_AT = (960, 58)        # the SKIP button's middle in the 1920 x 1080 arena (client/deathcam.gd SKIP_RECT)
SKIP_OLD = (1740, 996)     # where it was until 2026-11-24


def host(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(a.host + path, data=data, method="GET" if body is None else "POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read())


prof = tempfile.mkdtemp(prefix="tb-cam-")


import atexit, shutil   # p4.19: the browser's throw-away profile goes when the tool ends (they piled up in /tmp)


atexit.register(lambda: shutil.rmtree(prof, ignore_errors=True))
chrome = subprocess.Popen(["chromium", "--headless=new", "--no-first-run", f"--remote-debugging-port={a.port}",
                           f"--user-data-dir={prof}", "--ignore-certificate-errors", "--use-gl=angle", "--use-angle=swiftshader",
                           "--enable-unsafe-swiftshader", "--window-size=1280,720", "--touch-events=enabled", "--mute-audio", "about:blank"],   # p4.19: the game has sound; a check never reaches the speakers
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
    cmd("Page.navigate", url=f"{a.url}?server={a.server}&name=Cam&join" + (f"&{a.extra}" if a.extra else ""))
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

    def tap(at, touch_id):
        kk = 720 / 1080.0
        pt = {"x": (1280 - 1920 * kk) / 2 + at[0] * kk, "y": at[1] * kk, "radiusX": 8, "radiusY": 8, "force": 1, "id": touch_id}
        cmd("Input.dispatchTouchEvent", type="touchStart", touchPoints=[pt])
        time.sleep(0.08)
        cmd("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])

    test_ok = True
    if a.skip_test:
        # the times are the page's own: seconds since its "[Deathcam] the match's montage" line
        t_wait = time.time()
        while not any("the match's montage" in c for c in console) and time.time() - t_wait < 10:
            drain(0.05)
        t1 = time.time()
        if not any("the match's montage" in c for c in console):
            print("no montage on this page (the winner had no kill): the SKIP test cannot run", flush=True)
            test_ok = False
        drain(max(0.0, t1 + 0.9 - time.time()))
        s1 = time.time() - t1
        tap(SKIP_OLD if a.first_tap == "old" else SKIP_AT, 3)
        at1 = time.time() - t1
        drain(0.7)
        early = host("/state")["phase_name"]
        drain(max(0.0, t1 + 2.6 - time.time()))
        s2 = time.time() - t1
        tap(SKIP_OLD, 4)
        at2 = time.time() - t1
        drain(0.7)
        old = host("/state")["phase_name"]
        test_ok = test_ok and early == "MATCH END" and old == "MATCH END" and at1 < 1.9
        print(f"a tap on SKIP's {'OLD ' if a.first_tap == 'old' else ''}spot {s1:.1f} to {at1:.1f} s into the replay (it is asleep until 2 s): the server is in {early}; "
              f"a tap on its old spot {s2:.1f} to {at2:.1f} s in: {old} (MATCH END wanted, twice): {'PASS' if test_ok else 'FAIL'}", flush=True)
        s3 = time.time() - t1
        tap(SKIP_AT, 5)
        t_skip = time.time()
        skipped_ok = False
        while time.time() - t_skip < 3.0:
            drain(0.1)
            if host("/state")["phase_name"] == "LOBBY":
                skipped_ok = True
                print(f"SKIP tapped {s3:.1f} to {t_skip - t1:.1f} s into the replay: the lobby came back {time.time() - t_skip:.1f} s later", flush=True)
                break
        if not skipped_ok:
            print(f"SKIP tapped {s3:.1f} to {t_skip - t1:.1f} s into the replay: NO lobby in 3 s", flush=True)
        a.skip_after = 0.0
        k = 1
    while not a.skip_test and time.time() - t1 < 12.0 + max(0.0, a.skip_after):
        r = cmd("Page.captureScreenshot", format="png")
        with open(f"{a.out}_cam_{k:02d}.png", "wb") as f:
            f.write(base64.b64decode(r["data"]))
        k += 1
        drain(a.every)
        if a.skip_after >= 0 and skipped_ok is None and time.time() - t1 >= a.skip_after:
            tap(SKIP_AT, 5)
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
ok = any("montage" in c for c in lines) and (a.skip_after < 0 or skipped_ok) and test_ok
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
