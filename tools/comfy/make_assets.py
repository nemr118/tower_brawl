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


# ---- p4.18 the Harvest season (run_harvest.py; the picks of 2026-11-24)
HARVEST = {"splash": "splash/harvest_1_logo", "winner": "winner/harvest_1", "barn": "cards/barn_0", "table": "cards/table_1",
           "sky": "backdrops/pix/autumn_k2", "small_bird": 3, "big_bird": 2, "pie_top": 0}
# the season's badges, 128 px a cell, in client/powers_view.gd's HV_* order; the try of each
HARVEST_ICONS = [("dish", 0), ("pie", 1), ("popcorn", 0), ("crows", 0), ("turkey_time", 1), ("too_much_pie", 1), ("pea", 2), ("big_turkey", 0)]
# the season's award pictures, 80 px a cell, in client/award_art.gd's HARVEST order
HARVEST_AWARDS = [("gobble", 1), ("pie_face", 0), ("stuffed", 1), ("leftovers", 1), ("big_turkey", 0), ("turkey_time", 1), ("dish", 0)]
BIRDS = ["turkey_run", "turkey_jump", "big_stand", "big_peck", "big_down"]   # 256 px a cell (client/harvest_view.gd)


def _no_pink(im):
    """A cut-out's pink ground shadow goes (the model shades the magenta background under a figure): every
    pixel that is pink or magenta (red and blue well over green) turns clear. The birds and the badges
    here have no pink of their own."""
    a = np.asarray(im.convert("RGBA")).copy()
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    pink = (r - g > 45) & (b - g > 35) & (b > 90)
    a[pink, 3] = 0
    # the shadow's own dark outline, right beside the pink, goes with it
    from PIL import ImageFilter
    near = np.asarray(Image.fromarray((pink * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(13))) > 0
    dark = np.maximum(np.maximum(r, g), b) < 80
    a[near & dark, 3] = 0
    return Image.fromarray(a, "RGBA")


def harvest():
    """The loading picture (bench/web/page/splash_harvest.png), the winner's backdrop, the arena cards
    (two more cells and a second MIX for the season), the autumn sky, the badges, the awards, the birds,
    the pie for the lobby title's O. (The "splat" tries came out as cupcakes: the cream is drawn in code.)"""
    Image.open(f"{OUT}/{HARVEST['splash']}.png").convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT).save(
        f"{REPO}/bench/web/page/splash_harvest.png", optimize=True)
    Image.open(f"{OUT}/{HARVEST['winner']}.png").convert("RGB").save(f"{ASSETS}/winner_harvest.png", optimize=True)
    Image.open(f"{OUT}/{HARVEST['sky']}.png").convert("RGBA").save(f"{ASSETS}/bg_autumn_far.png", optimize=True)
    # the cards: cells 0..4 stay (MIX, THE KEEP, THE BRIDGES, THE HAUNTED HOUSE, THE BOILER ROOM); then
    # THE HARVEST BARN, THE BIG TABLE, and the Harvest season's MIX (the keep, the bridges, the barn, the table)
    old = Image.open(f"{ASSETS}/arena_cards.png").convert("RGB")
    sheet = Image.new("RGB", (400 * 8, 225), (10, 8, 16))
    sheet.paste(old.crop((0, 0, 2000, 225)), (0, 0))
    barn = Image.open(f"{OUT}/{HARVEST['barn']}.png").convert("RGB").resize((400, 225), Image.LANCZOS)
    table = Image.open(f"{OUT}/{HARVEST['table']}.png").convert("RGB").resize((400, 225), Image.LANCZOS)
    sheet.paste(barn, (2000, 0))
    sheet.paste(table, (2400, 0))
    mix = Image.new("RGB", (400, 225), (10, 8, 16))
    quads = [old.crop((400, 0, 800, 225)), old.crop((800, 0, 1200, 225)), barn, table]
    for i, q in enumerate(quads):
        mix.paste(q.resize((198, 111), Image.LANCZOS), ((i % 2) * 202, (i // 2) * 114))
    sheet.paste(mix, (2800, 0))
    sheet.save(f"{ASSETS}/arena_cards.png", optimize=True)
    for names, cell, dst in ((HARVEST_ICONS, 128, "harvest_icons.png"), (HARVEST_AWARDS, 80, "award_art_harvest.png")):
        out = Image.new("RGBA", (cell * len(names), cell), (0, 0, 0, 0))
        for i, (k, n) in enumerate(names):
            out.alpha_composite(_no_pink(P.cut(f"{OUT}/harvest/{k}_{n}.png", 512)).resize((cell, cell), Image.LANCZOS), (i * cell, 0))
        out.save(f"{ASSETS}/{dst}", optimize=True)
    birds = Image.new("RGBA", (256 * len(BIRDS), 256), (0, 0, 0, 0))
    for i, k in enumerate(BIRDS):
        n = HARVEST["small_bird"] if k.startswith("turkey_") else HARVEST["big_bird"]
        b = _no_pink(P.cut(f"{OUT}/harvest/{k}_{n}.png", 512))
        b = b.crop(b.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox())
        k2 = 244.0 / max(b.size)
        b = b.resize((max(1, round(b.width * k2)), max(1, round(b.height * k2))), Image.LANCZOS)
        birds.alpha_composite(b, (i * 256 + (256 - b.width) // 2, 250 - b.height))   # its feet on the cell's line 250, in the middle
    birds.save(f"{ASSETS}/harvest_birds.png", optimize=True)
    _no_pink(P.cut(f"{OUT}/harvest/pie_top_{HARVEST['pie_top']}.png", 512)).resize((256, 256), Image.LANCZOS).save(f"{ASSETS}/harvest_pie.png", optimize=True)
    print("ok harvest")


if __name__ == "__main__":
    jobs = {f.__name__: f for f in (backdrops, heroes, icons, ribbon, harvest)}
    for job in ([jobs[a] for a in sys.argv[1:]] if sys.argv[1:] else jobs.values()):
        job()
