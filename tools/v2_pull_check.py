#!/usr/bin/env python3
"""The phone's pull-back shot (p4.4), end to end in headless Chromium with touch.

A test server (wss on --server, with its host port --host, --bots 0), a second
person who only stands there (play_probe.gd --idle) and the Python service (the
page) must run. The page joins as "Pull"; the host port starts the match once
both sit; in the fight the right thumb (a touch drag on the
right half) first pulls a little and lets go inside the ring (no arrow), then
pulls left past the ring and lets go (one arrow, flying right). Shots are
counted by the host port's numbers for "Pull". Pictures: <out>_armed.png (the
thumb held past the ring) and <out>_shot.png (just after the release). Exit 1 on a FAIL.

    ./venv/bin/python tools/v2_pull_check.py --out /tmp/pull
"""
import argparse
import base64
import json
import os
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
ap.add_argument("--out", default="/tmp/pull")
ap.add_argument("--port", type=int, default=9335)
a = ap.parse_args()
W, H = 1280, 720
FAILS = []


def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what, flush=True)
    if not ok:
        FAILS.append(what)


def host(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(a.host + path, data=data, method="GET" if body is None else "POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read())


def pull_stats():
    st = host("/state")
    for p in st["stats"]:
        if p["name"] == "Pull" and not p["bot"]:
            return st, p
    return st, {"shots": 0, "deaths": 0}


prof = tempfile.mkdtemp(prefix="tb-pull-")
chrome = subprocess.Popen(["chromium", "--headless=new", "--no-first-run", "--no-default-browser-check",
                           f"--remote-debugging-port={a.port}", f"--user-data-dir={prof}", "--ignore-certificate-errors",
                           "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                           f"--window-size={W},{H}", "--touch-events=enabled", "about:blank"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    tabs = None
    for i in range(30):
        time.sleep(1)
        try:
            tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{a.port}/json", timeout=3))
            break
        except Exception:
            pass
    page = [t for t in tabs if t.get("type") == "page"][0]
    ws = websocket.create_connection(page["webSocketDebuggerUrl"], suppress_origin=True, timeout=40)
    _id = [0]

    def cmd(method, **params):
        _id[0] += 1
        ws.send(json.dumps({"id": _id[0], "method": method, "params": params}))
        while True:
            m = json.loads(ws.recv())
            if m.get("id") == _id[0]:
                return m.get("result", m)

    def shot(name):
        r = cmd("Page.captureScreenshot", format="png")
        with open(f"{a.out}_{name}.png", "wb") as f:
            f.write(base64.b64decode(r["data"]))

    def pt(dx, dy):   # a point of the 1920 x 1080 design (the page scales by height and centres)
        k = H / 1080.0
        return {"x": (W - 1920 * k) / 2 + dx * k, "y": dy * k, "radiusX": 8, "radiusY": 8, "force": 1, "id": 7}

    def drag(x0, y0, x1, y1, steps, hold_shot=None):
        cmd("Input.dispatchTouchEvent", type="touchStart", touchPoints=[pt(x0, y0)])
        time.sleep(0.05)
        for i in range(1, steps + 1):
            cmd("Input.dispatchTouchEvent", type="touchMove", touchPoints=[pt(x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps)])
            time.sleep(0.03)
        time.sleep(0.15)
        if hold_shot:
            shot(hold_shot)
        cmd("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])

    cmd("Page.enable")
    cmd("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=1, mobile=True)
    cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
    cmd("Emulation.setUserAgentOverride", userAgent="Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36")
    cmd("Page.navigate", url=f"{a.url}?server={a.server}&name=Pull&join")
    seated = False
    for i in range(60):
        time.sleep(0.5)
        try:
            st = host("/state")
            seated = any(s["name"] == "Pull" and s["who"] == "person" for s in st["seats"])
        except Exception:
            pass
        if seated:
            break
    check(seated, "the page joined as Pull")
    cmd("Runtime.evaluate", expression="(function(){var g=document.getElementById('fs-gate'); if(g){g.click(); g.remove();} return 'ok'})()")
    for i in range(60):
        if host("/state")["people"] >= 2:
            break
        time.sleep(0.5)
    host("/start", {})
    tries = 0
    done = False
    while tries < 3 and not done:
        tries += 1
        for i in range(80):
            time.sleep(0.25)
            st = host("/state")
            if st["phase_name"] == "PLAYING":
                break
        time.sleep(0.3)
        st, before = pull_stats()
        drag(1500, 800, 1440, 800, 4)                      # 60 px: inside the ring (110)
        time.sleep(0.5)
        st, mid = pull_stats()
        drag(1500, 800, 1290, 800, 7, hold_shot="armed")   # 210 px to the left: past the ring
        time.sleep(0.12)
        shot("shot")
        time.sleep(0.5)
        st, after = pull_stats()
        print(f"round {st['round']}: shots {before['shots']} -> {mid['shots']} (inside the ring) -> {after['shots']} (past it)", flush=True)
        if after["deaths"] > before["deaths"]:
            print(f"Pull died in round {st['round']}: trying the next round", flush=True)
            continue
        done = True
        check(mid["shots"] == before["shots"], f"let go inside the ring: no arrow (shots {before['shots']} -> {mid['shots']})")
        check(after["shots"] == mid["shots"] + 1, f"pulled past the ring and let go: one arrow (shots {mid['shots']} -> {after['shots']})")
    check(done, "a round where Pull lived through both pulls")
finally:
    chrome.kill()
print("ALL PASS" if not FAILS else f"{len(FAILS)} FAIL", flush=True)
sys.exit(1 if FAILS else 0)
