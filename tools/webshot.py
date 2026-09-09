#!/usr/bin/env python3
# ==============================================================================
# Screenshots of the WEB build (v0.1.4). Chromium headless with a debug port,
# driven over CDP: a phone user agent, touch emulation, the layout saved in
# localStorage before the page loads, the full-screen sheet removed, the page
# joins as a player, and a named sequence of touches (or keys) with a
# Page.captureScreenshot after each step. The --screenshot flag of Chromium only
# catches the boot splash; this is the way that works.
#
#   ./venv/bin/python tools/webshot.py --seq idle --layout twin --out /tmp/shot
#       -> /tmp/shot_idle.png, the page's console in /tmp/shot_chrome.log
#   --seq: idle | sticks (both thumbs: jump wedge + aim, duck sector + rim shot)
#          | moves (jump 150 ms, dash 100 ms, duck 800 ms) | duck (duck 80 ms,
#          the look-down at 2.5 s, released; the page joins first so it spawns
#          near the top) | keys (S held: the keyboard duck and look).
#   --layout arc|twin (saved as towerbrawl_layout), --url, --bot (start a
#   headless turtle bot 8 s after the page so a match begins; on by default).
# Needs the PC service up and the venv's websocket-client. Never run a
# sequence while the harness runs: it restarts the service per scenario.
# ==============================================================================
import argparse, base64, json, os, subprocess, sys, tempfile, time, urllib.request
import websocket

ap = argparse.ArgumentParser()
ap.add_argument("--seq", default="idle")
ap.add_argument("--layout", default="twin")
ap.add_argument("--url", default="https://127.0.0.1:8443/index.html")
ap.add_argument("--out", default="/tmp/tb_shot")
ap.add_argument("--no-bot", action="store_true")
ap.add_argument("--port", type=int, default=9333)
a = ap.parse_args()
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

prof = tempfile.mkdtemp(prefix="tb-webshot-")
chrome_log = open(f"{a.out}_chrome.log", "w")
chrome = subprocess.Popen([
    "chromium", "--headless=new", "--no-first-run", "--no-default-browser-check",
    f"--remote-debugging-port={a.port}", f"--user-data-dir={prof}",
    "--ignore-certificate-errors", "--use-gl=angle", "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader", "--enable-logging=stderr", "--v=0",
    "--window-size=1280,720", "--touch-events=enabled", "about:blank"],
    stdout=subprocess.DEVNULL, stderr=chrome_log)
tabs = None
for i in range(30):
    time.sleep(1)
    try:
        tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{a.port}/json", timeout=3))
        break
    except Exception as e:
        print("waiting for the debug port", i, e, flush=True)
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
    print("shot", name, flush=True)

# Page px -> the 640 x 360 viewport fills 1280 x 720 exactly: scale 2, no bars.
def touch(kind, points):
    cmd("Input.dispatchTouchEvent", type=kind, touchPoints=[{"x": x * 2, "y": y * 2, "id": i} for i, (x, y) in points])

def key(kind, k, code, vk):
    cmd("Input.dispatchKeyEvent", type=kind, key=k, code=code, windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk, text=k if kind == "keyDown" else "")

if a.seq != "keys":
    cmd("Emulation.setUserAgentOverride", userAgent="Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Mobile Safari/537.36")
    cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
cmd("Emulation.setDeviceMetricsOverride", width=1280, height=720, deviceScaleFactor=1, mobile=a.seq != "keys")
cmd("Page.enable")
cmd("Page.addScriptToEvaluateOnNewDocument", source=(
    f"try{{localStorage.setItem('towerbrawl_layout','{a.layout}');}}catch(e){{}} "
    "setInterval(function(){['fs-gate','rotate-hint'].forEach(function(i){var e=document.getElementById(i); if(e) e.remove();});}, 300);"))
cmd("Page.navigate", url=f"{a.url}?arg=--autojoin&arg=--name=Shot{a.seq}")
time.sleep(8)
bot = None
if not a.no_bot:
    bot = subprocess.Popen(["timeout", "150", "godot", "--headless", "--path", ".", "--", "--autojoin", "--name=ShotBot", "--ai=turtle", "--ai-seed=3"],
                           stdout=open(f"{a.out}_bot.log", "w"), stderr=subprocess.STDOUT)
time.sleep(24)

shot("idle")
if a.seq == "sticks":
    touch("touchStart", [(0, (100, 250))])
    touch("touchMove", [(0, (100, 190))])                       # the jump wedge
    touch("touchStart", [(0, (100, 190)), (1, (500, 235))])
    touch("touchMove", [(0, (100, 190)), (1, (550, 235))])      # aim right
    time.sleep(0.4)
    shot("held_jump_aim")
    touch("touchMove", [(0, (100, 310)), (1, (600, 235))])      # duck sector, past the aim rim
    time.sleep(0.4)
    shot("held_duck_shot")
    touch("touchEnd", [])
elif a.seq == "moves":
    touch("touchStart", [(0, (100, 250))])
    touch("touchMove", [(0, (100, 180))])                       # the jump wedge
    time.sleep(0.15)
    shot("jump_150ms")
    time.sleep(0.8)
    touch("touchMove", [(0, (100, 250))])
    touch("touchMove", [(0, (195, 250))])                       # 95 px right: past the rim, a dash
    time.sleep(0.1)
    shot("dash_100ms")
    time.sleep(0.5)
    touch("touchMove", [(0, (100, 250))])
    touch("touchMove", [(0, (100, 320))])                       # straight down: duck
    time.sleep(0.8)
    shot("duck_800ms")
    touch("touchEnd", [])
elif a.seq == "duck":
    touch("touchStart", [(0, (100, 250))])
    touch("touchMove", [(0, (100, 320))])
    time.sleep(0.08)
    shot("duck_80ms")
    time.sleep(2.4)
    shot("duck_2500ms_look")
    touch("touchEnd", [])
    time.sleep(1.0)
    shot("released")
elif a.seq == "keys":
    key("keyDown", "s", "KeyS", 83)
    time.sleep(0.2)
    shot("s_200ms")
    time.sleep(2.6)
    shot("s_2800ms_look")
    key("keyUp", "s", "KeyS", 83)
    time.sleep(0.8)
    shot("released")
ws.close()
chrome.terminate()
if bot:
    bot.terminate()
print("done:", a.out + "_*.png")
