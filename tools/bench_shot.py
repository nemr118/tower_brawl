#!/usr/bin/env python3
# Screenshots of the benchmark page (branch beta) in headless Chromium over
# CDP, one per tier in look-only mode (?tier=N). Software drawing (SwiftShader):
# the pictures are real, the speed is not. Nothing opens on the screen.
#   ./venv/bin/python tools/bench_shot.py --server wss://127.0.0.1:8095 --tiers 0,2,3,4 --out <prefix>
import argparse, base64, json, os, subprocess, tempfile, time, urllib.request
import websocket

ap = argparse.ArgumentParser()
ap.add_argument("--page", default="https://127.0.0.1:8443/bench/index.html")
ap.add_argument("--server", default="wss://127.0.0.1:8095")
ap.add_argument("--tiers", default="0,1,2,3,4,5")
ap.add_argument("--wait", type=float, default=14.0)
ap.add_argument("--out", default="/tmp/bench_shot")
ap.add_argument("--port", type=int, default=9344)
ap.add_argument("--extra", default="")
ap.add_argument("--looks", default="", help="split-test steps instead of tiers, e.g. t3,t3-fog (world.gd VARIANTS)")
ap.add_argument("--ladder", default="", help="run a ladder instead, e.g. 'split=t3&seconds=4': one picture after --wait")
a = ap.parse_args()

prof = tempfile.mkdtemp(prefix="bench-shot-")
log = open(f"{a.out}_chrome.log", "w")
chrome = subprocess.Popen(["chromium", "--headless=new", "--no-first-run", "--no-default-browser-check",
    f"--remote-debugging-port={a.port}", f"--user-data-dir={prof}", "--ignore-certificate-errors",
    "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--window-size=1920,1080",
    "--remote-allow-origins=*", "--enable-logging=stderr", "about:blank"], stdout=log, stderr=log)
try:
    target = None
    for _ in range(60):
        try:
            tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{a.port}/json"))
            target = next(t for t in tabs if t.get("type") == "page")
            break
        except Exception:
            time.sleep(0.25)
    ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=60)
    msg_id = [0]
    def cdp(method, **params):
        msg_id[0] += 1
        ws.send(json.dumps({"id": msg_id[0], "method": method, "params": params}))
        while True:
            r = json.loads(ws.recv())
            if r.get("id") == msg_id[0]:
                return r.get("result", {})
    cdp("Page.enable")
    cdp("Emulation.setDeviceMetricsOverride", width=1920, height=1080, deviceScaleFactor=1, mobile=False)
    if a.ladder:
        shots = [(f"{a.page}?server={a.server}&name=chromium&auto&{a.ladder}", f"{a.out}_ladder.png")]
    elif a.looks:
        shots = [(f"{a.page}?server={a.server}&look={v}&view-res=1080&name=shot", f"{a.out}_{v}.png") for v in a.looks.split(",")]
    else:
        shots = [(f"{a.page}?server={a.server}&tier={t}&view-res=1080&name=shot", f"{a.out}_T{t}.png") for t in a.tiers.split(",")]
    for url, path in shots:
        url += ("&" + a.extra) if a.extra else ""
        cdp("Page.navigate", url=url)
        time.sleep(a.wait)
        png = base64.b64decode(cdp("Page.captureScreenshot", format="png")["data"])
        open(path, "wb").write(png)
        print("shot", path, len(png), "bytes")
finally:
    chrome.terminate()
