#!/usr/bin/env python3
"""p4.21: a film clip of the page's menus, to SEE motion (a still picture cannot show it).

The test page draws only a few frames a second (no graphics card: software drawing), so a
plain recording would stutter. The trick: the page runs N times slower (?slowmo=N, a test
knob in game_client.gd), every frame it draws is kept with its time, and the clip plays
them back N times faster. A real phone draws 30 to 60 frames a second; the clip shows what
that looks like.

    ./venv/bin/python tools/v2_motion_clip.py --out /tmp/clip --script lobby
    ./venv/bin/python tools/v2_motion_clip.py --out /tmp/clip_off --script lobby --extra polish_off=motion

It needs a game server already running (--server), as tools/v2_shot.py does. Scripts: the
steps below (SCRIPTS). Out: <out>.mp4 and <out>_frames/. Sound never plays (--mute-audio).
"""
import argparse
import atexit
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

import websocket

ap = argparse.ArgumentParser()
ap.add_argument("--url", default="https://127.0.0.1:8443/v2/index.html")
ap.add_argument("--server", default="wss://127.0.0.1:8091")
ap.add_argument("--out", default="/tmp/v2clip")
ap.add_argument("--name", default="Tav")
ap.add_argument("--script", default="lobby", help="which steps to film: " + ", ".join(["lobby", "teams", "join", "menu", "tv", "hats", "match", "hatmove"]))
ap.add_argument("--secs", type=float, default=16.0, help="p4.22 --script match: how many seconds of the match to film (after the tap on START)")
ap.add_argument("--slowmo", type=float, default=4.0)
ap.add_argument("--extra", default="", help="more page options, a=1&b=2")
ap.add_argument("--phone", action="store_true")
ap.add_argument("--port", type=int, default=9352)
ap.add_argument("--wait", type=float, default=14.0, help="seconds for the page to load and join")
ap.add_argument("--size", default="960x540")
ap.add_argument("--fps", type=int, default=30)
ap.add_argument("--admin", type=int, default=0, help="the server's host port (for the steps that change bots or the mode from outside)")
a = ap.parse_args()
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
W, H = (int(v) for v in a.size.lower().split("x"))
N = a.slowmo

# The steps: (seconds of clip time to wait first, what to do). A tap is at a point of the
# 1920 x 1080 design. Clip time is what the viewer sees; the page takes N times as long.
SET = (1640, 58)          # SETTINGS (a PC's place; a phone's is 1630)
SCRIPTS = {
    # SETTINGS opens, LOOK: LOW, then AUTO, DONE; the arena picker and a pick; HOW TO PLAY; the bots' - - + +
    "lobby": [(0.6, ("tap", SET)), (1.5, ("tap", (1051, 308))), (0.9, ("tap", (853, 308))), (0.9, ("tap", (960, 936))),
              (0.7, ("tap", (320, 732))), (1.6, ("tap", (732, 317))), (1.0, ("tap", (230, 124))), (2.4, ("tap", (960, 980))),
              (0.7, ("tap", (1293, 732))), (0.6, ("tap", (1293, 732))), (0.6, ("tap", (1389, 732))), (0.7, ("tap", (1389, 732))), (1.0, None)],
    # TEAMS: the mode comes on (the flags drop in), your own card is tapped twice, then TONIGHT'S CHAMPIONS
    # (its button shows once the server has seen a match end tonight)
    "teams": [(0.6, ("tap", SET)), (1.3, ("tap", (1348, 774))), (1.0, ("tap", (960, 936))), (1.5, ("tap", (165, 420))), (1.4, ("tap", (165, 420))),
              (1.4, ("tap", (230, 203))), (3.0, ("tap", (960, 1040))), (0.7, None)],
    # a new phone: WHO ARE YOU? (when the server knows names), then the join
    "join": [(0.8, ("tap", (1390, 875))), (1.8, ("tap", (960, 420))), (2.0, None)],
    # a match: the MENU opens, a pick, back to the game
    "menu": [(0.5, ("tap", (1230, 854))), (9.0, ("key", "Escape")), (1.6, ("tap", (1500, 500))), (1.0, ("tap", (1250, 890))), (1.0, None)],
    "tv": [(4.0, None)],
    # p4.22 a MATCH: START is tapped, then --secs of it (the countdown, ROUND, FIGHT and on). The server must run
    # with --slowmo N (the same N as --slowmo here): the page gets ?slowmatch=N, and both clocks run N times slower.
    # (The server's own --slowmo gives fewer ticks a second; Godot's --time-scale would not: it changes a tick's length only.)
    "match": [(0.5, ("tap", (1230, 854))), (a.secs, None)],
    # p4.22 the winter hats (a server with --season christmas): the HAT button on your own card (seat 1) six times, all the way round
    "hats": [(0.8, ("tap", (166, 577))), (1.4, ("tap", (166, 577))), (1.4, ("tap", (166, 577))), (1.4, ("tap", (166, 577))),
             (1.4, ("tap", (166, 577))), (1.4, ("tap", (166, 577))), (1.8, None)],
    # the hats' own motion with no server: the test page ?hatsheet=move (client/hats.gd Sheet): six fighters, one in each hat,
    # run, jump, land, turn, roll, aim and are knocked out. One whole turn of the routine is 13 s
    "hatmove": [(13.6, None)],
}
steps = SCRIPTS[a.script]

prof = tempfile.mkdtemp(prefix="tb-v2clip-")
atexit.register(lambda: shutil.rmtree(prof, ignore_errors=True))
chrome_log = open(f"{a.out}_chrome.log", "w")
flags = ["chromium", "--headless=new", "--no-first-run", "--no-default-browser-check", f"--remote-debugging-port={a.port}",
         f"--user-data-dir={prof}", "--ignore-certificate-errors", "--use-gl=angle", "--use-angle=swiftshader",
         "--enable-unsafe-swiftshader", "--enable-logging=stderr", "--v=0", f"--window-size={W},{H}",
         "--autoplay-policy=no-user-gesture-required", "--mute-audio"]
if a.phone:
    flags.append("--touch-events=enabled")
flags.append("about:blank")
chrome = subprocess.Popen(flags, stdout=subprocess.DEVNULL, stderr=chrome_log)

def stop_chrome():
    if chrome.poll() is None:
        chrome.terminate()
        try:
            chrome.wait(5)
        except subprocess.TimeoutExpired:
            chrome.kill()
atexit.register(stop_chrome)

tabs = None
for i in range(30):
    time.sleep(1)
    try:
        tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{a.port}/json", timeout=3))
        break
    except Exception:
        pass
if not tabs:
    sys.exit("Chromium never opened its debug port")
page = [t for t in tabs if t.get("type") == "page"][0]
ws = websocket.create_connection(page["webSocketDebuggerUrl"], suppress_origin=True, timeout=40)
_id = [0]
console = []
frames = []            # [seconds since the cast began, file]
taps = []              # [seconds since the cast began, x, y in the window]: a ring marks each one in the clip
cast_on = [False]
cast_t0 = [0.0]
fdir = f"{a.out}_frames"
shutil.rmtree(fdir, ignore_errors=True)
os.makedirs(fdir)

def handle(m):
    if m.get("method") == "Runtime.consoleAPICalled":
        console.append(" ".join(str(x.get("value", x.get("description", ""))) for x in m["params"].get("args", [])))
    elif m.get("method") == "Page.screencastFrame":
        if cast_on[0]:
            f = f"{fdir}/{len(frames):04d}.jpg"
            with open(f, "wb") as fh:
                fh.write(base64.b64decode(m["params"]["data"]))
            frames.append([time.time() - cast_t0[0], f])
        _id[0] += 1
        ws.send(json.dumps({"id": _id[0], "method": "Page.screencastFrameAck", "params": {"sessionId": m["params"]["sessionId"]}}))

def cmd(method, **params):
    _id[0] += 1
    mine = _id[0]
    ws.send(json.dumps({"id": mine, "method": method, "params": params}))
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == mine:
            return m.get("result", m)
        handle(m)

def drain(secs):
    end = time.time() + secs
    ws.settimeout(0.3)
    while time.time() < end:
        try:
            handle(json.loads(ws.recv()))
        except websocket.WebSocketTimeoutException:
            continue
    ws.settimeout(40)

def tap(dx, dy):
    k = H / 1080.0
    x = (W - 1920 * k) / 2 + dx * k
    y = dy * k
    if cast_on[0]:
        taps.append([time.time() - cast_t0[0], x, y])
    if a.phone:
        pt = {"x": x, "y": y, "radiusX": 8, "radiusY": 8, "force": 1, "id": 1}
        cmd("Input.dispatchTouchEvent", type="touchStart", touchPoints=[pt])
        drain(0.09 * N)          # (the finger stays down long enough to see the squeeze)
        cmd("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
    else:
        cmd("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y)
        cmd("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
        drain(0.09 * N)
        cmd("Input.dispatchMouseEvent", type="mouseReleased", x=x, y=y, button="left", clickCount=1)

def key(name):
    for kind in ("keyDown", "keyUp"):
        cmd("Input.dispatchKeyEvent", type=kind, key=name, code=name, windowsVirtualKeyCode=27 if name == "Escape" else 0)

cmd("Runtime.enable")
cmd("Page.enable")
if a.phone:
    cmd("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=1, mobile=True)
    cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
    cmd("Emulation.setUserAgentOverride", userAgent="Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36")
else:
    cmd("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=1, mobile=False)
join = "" if a.script in ("join", "tv", "hatmove") else f"&name={a.name}&join"
url = f"{a.url}?server={a.server}{join}&nohowto&slowmo={N:g}" + ("&tv" if a.script == "tv" else "") + ("&hatsheet=move" if a.script == "hatmove" else "") + (f"&{a.extra}" if a.extra else "")
if a.script == "match":
    url += f"&slowmatch={N:g}"
cmd("Page.navigate", url=url)
drain(a.wait)
cmd("Runtime.evaluate", expression="(function(){var g=document.getElementById('fs-gate'); if(g){g.click(); g.remove();} return 'ok'})()")
drain(2.0 + 1.5 * N)         # the lobby's own rise-in ends (it is slow too)

_id[0] += 1
ws.send(json.dumps({"id": _id[0], "method": "Page.startScreencast", "params": {"format": "jpeg", "quality": 90, "everyNthFrame": 1}}))
cast_t0[0] = time.time()
cast_on[0] = True
for wait, act in steps:
    drain(wait * N)
    if act is None:
        continue
    if act[0] == "tap":
        tap(*act[1])
    elif act[0] == "key":
        key(act[1])
cast_on[0] = False
total = time.time() - cast_t0[0]
cmd("Page.stopScreencast")
with open(f"{a.out}_console.log", "w") as f:
    f.write("\n".join(console))
errs = [c for c in console if "SCRIPT ERROR" in c or "ERROR:" in c or "Uncaught" in c]
ws.close()
stop_chrome()

# the clip: each frame shows for (its gap to the next) / N seconds
if len(frames) < 2:
    sys.exit(f"only {len(frames)} frames")
lst = f"{a.out}_frames.txt"
with open(lst, "w") as f:
    for i, (t, path) in enumerate(frames):
        nxt = frames[i + 1][0] if i + 1 < len(frames) else total
        f.write(f"file '{os.path.abspath(path)}'\nduration {max(0.001, (nxt - t) / N):.4f}\n")
    f.write(f"file '{os.path.abspath(frames[-1][1])}'\n")
# a ring where each tap landed (a film has no finger to see): a small ring, then a wider one.
# The rings are two small pictures written here, laid over the clip by ffmpeg at each tap's time.
def ring_png(path, size, r, w):
    import struct
    import zlib
    c = (size - 1) / 2.0
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            white = max(0.0, min(1.0, w / 2 + 0.5 - abs(d - r)))
            dark = max(0.0, min(1.0, w / 2 + 2.5 - abs(d - r))) * 0.55
            if white > 0.0:
                raw += bytes([255, 255, 255, int(255 * max(white, dark))])
            else:
                raw += bytes([0, 0, 0, int(255 * dark)])
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))

inputs = ["-f", "concat", "-safe", "0", "-i", lst]
chain = f"[0:v]fps={a.fps}[v0]"
last = "v0"
if taps:
    k = H / 540.0
    sizes = [(int(52 * k) | 1, 15 * k), (int(84 * k) | 1, 30 * k)]
    for n, (size, r) in enumerate(sizes):
        ring_png(f"{a.out}_ring{n}.png", size, r, max(2.5, 3.5 * k))
        inputs += ["-i", f"{a.out}_ring{n}.png"]
    m = len(taps)
    chain += f";[1:v]format=rgba,split={m}" + "".join(f"[a{i}]" for i in range(m)) + f";[2:v]format=rgba,split={m}" + "".join(f"[b{i}]" for i in range(m))
    for i, (tt, x, y) in enumerate(taps):
        t0 = tt / N
        for tag, (size, _r), (s0, s1) in (("a", sizes[0], (0.0, 0.13)), ("b", sizes[1], (0.13, 0.3))):
            nxt = f"v{tag}{i}"
            chain += f";[{last}][{tag}{i}]overlay=x={x - size / 2:.0f}:y={y - size / 2:.0f}:enable='between(t,{t0 + s0:.3f},{t0 + s1:.3f})'[{nxt}]"
            last = nxt
chain += f";[{last}]format=yuv420p[out]"
r = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + inputs + ["-filter_complex", chain, "-map", "[out]",
                    "-c:v", "libx264", "-crf", "20", "-preset", "medium", "-movflags", "+faststart", f"{a.out}.mp4"], capture_output=True, text=True)
if r.returncode != 0:
    sys.exit("ffmpeg: " + r.stderr[-400:])
print(f"clip {a.out}.mp4: {len(frames)} frames in {total:.1f} s of page time = {total / N:.1f} s of clip, "
      f"{len(frames) / (total / N):.0f} frames a clip second; page errors {len(errs)}")
for e in errs[:6]:
    print("  ", e[:200])
