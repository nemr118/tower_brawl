#!/usr/bin/env python3
"""The phones' reports (p4.7), end to end in headless Chromium as an Android phone.

A test server (wss on --server, its host port --host, writing to --log, a
v2_server.jsonl) and the Python service (the page) must run. The page joins as
"Report"; the host port starts a match; after the first report and one timer
report (30 s) a script error is planted on the page. Checks: the server logged
the phone's reports ("client" lines with the device, the look, the frame rate,
the ping), the planted error came in a report, and the host port shows the
phone's health. Exit 1 on a FAIL.

    ./venv/bin/python tools/v2_report_check.py --log <out>/<date>/v2_server.jsonl
"""
import argparse
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
ap.add_argument("--log", required=True)
ap.add_argument("--port", type=int, default=9336)
a = ap.parse_args()
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


def client_lines():
    out = []
    with open(a.log, encoding="utf-8", errors="replace") as f:
        for raw in f:
            if '"kind":"client"' in raw:
                d = json.loads(raw)
                if d.get("name") == "Report":
                    out.append(d)
    return out


prof = tempfile.mkdtemp(prefix="tb-report-")
chrome = subprocess.Popen(["chromium", "--headless=new", "--no-first-run", f"--remote-debugging-port={a.port}",
                           f"--user-data-dir={prof}", "--ignore-certificate-errors", "--use-gl=angle", "--use-angle=swiftshader",
                           "--enable-unsafe-swiftshader", "--window-size=1280,720", "--touch-events=enabled", "about:blank"],
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
    ws = websocket.create_connection([t for t in tabs if t["type"] == "page"][0]["webSocketDebuggerUrl"], suppress_origin=True, timeout=40)
    n = [0]

    def cmd(method, **params):
        n[0] += 1
        ws.send(json.dumps({"id": n[0], "method": method, "params": params}))
        while True:
            m = json.loads(ws.recv())
            if m.get("id") == n[0]:
                return m.get("result", m)

    cmd("Page.enable")
    cmd("Emulation.setDeviceMetricsOverride", width=1280, height=720, deviceScaleFactor=1, mobile=True)
    cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
    cmd("Emulation.setUserAgentOverride", userAgent="Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36")
    cmd("Page.navigate", url=f"{a.url}?server={a.server}&name=Report&join")
    for i in range(60):
        time.sleep(0.5)
        try:
            if any(s["name"] == "Report" and s["who"] == "person" for s in host("/state")["seats"]):
                break
        except Exception:
            pass
    host("/start", {})
    time.sleep(40)          # the first report (3 s after the socket opens), then the timer one (30 s later)
    cmd("Runtime.evaluate", expression="setTimeout(function(){ throw new Error('tb report check: planted'); }, 0); 'ok'")
    time.sleep(10)          # page errors go out within 5 s
    lines = client_lines()
    whys = [l["why"] for l in lines]
    check(len(lines) >= 2 and "timer" in whys, f"the server logged the phone's reports: {len(lines)} ({', '.join(whys)})")
    if lines:
        last = [l for l in lines if l["why"] == "timer"][-1] if "timer" in whys else lines[-1]
        check(last["device"] == "android" and last["look"] in ("low", "normal", "high") and last["pick"] in ("auto", "low", "normal", "high"),
              f"a report says the device and the look: {last['device']}, pick {last['pick']}, look {last['look']}, screen {last['screen']}")
        check(last["frames"] > 0 and last["fps"] > 0 and last["ping_ms"] > 0,
              f"and the match's frame rate and the ping: {last['fps']} fps over {last['frames']} frames, ping {last['ping_ms']} ms")
    errs = [e for l in lines for e in l.get("errors", [])]
    check(any("tb report check: planted" in e for e in errs), f"the planted page error came in a report: {errs[:2]}")
    st = host("/state")
    seat = next((s for s in st["seats"] if s["name"] == "Report"), None)
    ph = seat.get("phone") if seat else None
    check(ph is not None and ph["device"] == "android" and ph["errors"] >= 1 and ph["age_s"] < 40,
          f"the host port shows the phone: {ph}")
finally:
    chrome.kill()
print("ALL PASS" if not FAILS else f"{len(FAILS)} FAIL", flush=True)
sys.exit(1 if FAILS else 0)
