#!/usr/bin/env python3
"""p4.17: the game's files from the ComfyUI pictures picked on 2026-10-26 (run_winner.py, run_ui.py).
Run it with ComfyUI's Python (it has onnxruntime for the heroes' cut):

    ~/ComfyUI/venv-py312/bin/python tools/comfy/make_assets.py [backdrops] [heroes] [icons] [ribbon]

- the winner's screen backdrops: bench/assets/winner_castle.png, winner_spooky.png (1280 x 720);
- the heroes: each seat colour's portrait cut off its background by ISNet (anime), on the CPU
  (~/ComfyUI/models/background_removal/isnet-anime.onnx, rembg's recipe), 540 x 720:
  bench/assets/heroes/hero_<seat>.png, the seats' order (client/world.gd TEAM);
- the lobby's button icons and the winner's crown: bench/assets/ui_icons.png, 128 px a cell in ICONS' order
  (client/lobby_art.gd UI_ICON_*); cut off their magenta like the power-up pictures (pick_sheets.cut);
- the banners' ribbon: bench/assets/ui_ribbon.png, 1024 px wide (client/hud_banner.gd RIBBON_*)."""
import os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pick_sheets as P

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.."))
ASSETS = os.path.join(REPO, "bench/assets")
OUT = P.OUT
PICKS = {"castle": "winner/castle_0", "spooky": "winner/spooky_2", "hero_try": 0, "ribbon": "ui/ribbon_3"}
COLOURS = ["red", "blue", "green", "yellow", "purple", "orange", "teal", "pink"]   # the seats, P1 to P8
ICONS = ["ui/bots_0", "ui/level_2", "ui/look_3", "ui/controls_1", "ui/leave_3", "ui/crown_3"]


def backdrops():
    for k in ("castle", "spooky"):
        Image.open(f"{OUT}/{PICKS[k]}.png").convert("RGB").save(f"{ASSETS}/winner_{k}.png", optimize=True)
        print("ok winner", k)


def isnet_cut(paths):
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.intra_op_num_threads = 4
    sess = ort.InferenceSession(os.path.expanduser("~/ComfyUI/models/background_removal/isnet-anime.onnx"), so,
                                providers=["CPUExecutionProvider"])
    name = sess.get_inputs()[0].name
    for p in paths:
        im = Image.open(p).convert("RGB")
        a = np.asarray(im.resize((1024, 1024), Image.LANCZOS)).astype(np.float32)
        a /= a.max()
        a -= np.array([0.485, 0.456, 0.406], np.float32)
        pred = sess.run(None, {name: a.transpose(2, 0, 1)[None]})[0][0, 0]
        pred = (pred - pred.min()) / (pred.max() - pred.min())
        rgba = im.convert("RGBA")
        rgba.putalpha(Image.fromarray((pred * 255).astype(np.uint8)).resize(im.size, Image.LANCZOS))
        yield rgba


def heroes():
    os.makedirs(f"{ASSETS}/heroes", exist_ok=True)
    paths = [f"{OUT}/portraits/{c}_{PICKS['hero_try']}.png" for c in COLOURS]
    for seat, rgba in enumerate(isnet_cut(paths)):
        rgba.resize((540, 720), Image.LANCZOS).save(f"{ASSETS}/heroes/hero_{seat}.png", optimize=True)
        print("ok hero", seat, COLOURS[seat])


def icons():
    sheet = Image.new("RGBA", (128 * len(ICONS), 128), (0, 0, 0, 0))
    for i, k in enumerate(ICONS):
        sheet.alpha_composite(P.cut(f"{OUT}/{k}.png", 128), (i * 128, 0))
    sheet.save(f"{ASSETS}/ui_icons.png", optimize=True)
    print("ok icons", len(ICONS))


def ribbon():
    P.cut(f"{OUT}/{PICKS['ribbon']}.png", 1024, square=False).save(f"{ASSETS}/ui_ribbon.png", optimize=True)
    print("ok ribbon")


if __name__ == "__main__":
    jobs = {f.__name__: f for f in (backdrops, heroes, icons, ribbon)}
    for job in ([jobs[a] for a in sys.argv[1:]] if sys.argv[1:] else jobs.values()):
        job()
