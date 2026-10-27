#!/usr/bin/env python3
"""Contact sheets to pick from, after batch.sh (2026-10-26): the arena cards, the year-round
loading picture with the logo on it, the candy tricks' badges cut out on dark discs (as the
game shows them), and the castle backdrops brought to the game's 480 x 270 next to today's.
    python3 tools/comfy/pick_sheets.py        -> $TB_COMFY_OUT/sheets/*.png"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

OUT = os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy"))
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONT = os.path.join(REPO, "bench/assets/fonts/lobby_display.ttf")
os.makedirs(OUT + "/sheets", exist_ok=True)
BG = (18, 14, 26)


def label(draw, xy, text, size=22):
    f = ImageFont.truetype(FONT, size)
    draw.text(xy, text, font=f, fill=(255, 255, 255), stroke_width=3, stroke_fill=(0, 0, 0))


def grid(cells, cols, cw, ch, title, pad=10):
    rows = (len(cells) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cw + pad) + pad, rows * (ch + pad) + pad + 44), BG)
    d = ImageDraw.Draw(sheet)
    label(d, (pad, 8), title, 26)
    for i, (name, im) in enumerate(cells):
        x, y = pad + (i % cols) * (cw + pad), 44 + pad + (i // cols) * (ch + pad)
        if im is not None:
            sheet.paste(im, (x, y), im if im.mode == "RGBA" else None)
        label(d, (x + 8, y + 6), name)
    return sheet


def cards():
    cells = []
    for k in ("keep", "bridges", "haunted", "boiler"):
        for i in range(4):
            p = f"{OUT}/cards/{k}_{i}.png"
            cells.append((f"{k} {i}", Image.open(p).convert("RGB").resize((384, 216), Image.LANCZOS) if os.path.exists(p) else None))
    grid(cells, 4, 384, 216, "Arena cards: pick one a row (name + number)").save(f"{OUT}/sheets/cards.png")


def logo(w):
    """TOWER BRAWL as on the Halloween loading picture: a yellow to orange fill, a thick dark outline, a dark glow."""
    size = int(w * 0.119)
    f = ImageFont.truetype(FONT, size)
    text = "TOWER BRAWL"
    box = f.getbbox(text, stroke_width=int(size * 0.07))
    tw, th = box[2] - box[0], box[3] - box[1]
    pad = int(size * 0.3)
    lw, lh = tw + pad * 2, th + pad * 2
    mask = Image.new("L", (lw, lh), 0)
    ImageDraw.Draw(mask).text((pad - box[0], pad - box[1]), text, font=f, fill=255)
    outline = Image.new("L", (lw, lh), 0)
    ImageDraw.Draw(outline).text((pad - box[0], pad - box[1]), text, font=f, fill=255, stroke_width=int(size * 0.07), stroke_fill=255)
    glow = outline.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(size * 0.12))
    grad = Image.new("RGB", (lw, lh))
    gd = ImageDraw.Draw(grad)
    for y in range(lh):
        t = min(1.0, max(0.0, (y - pad) / max(1, th)))
        gd.line([(0, y), (lw, y)], fill=(255, int(232 - 110 * t), int(110 - 90 * t)))
    out = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    out.paste((20, 8, 14, 200), (0, 0), glow)
    out.paste((42, 16, 8, 255), (0, 0), outline)
    out.paste(grad, (0, 0), mask)
    return out, pad


def splash():
    cells = []
    for i in range(6):
        p = f"{OUT}/splash/castle_{i}.png"
        if not os.path.exists(p):
            cells.append((f"castle {i}", None))
            continue
        im = Image.open(p).convert("RGBA")
        lg, pad = logo(im.width)
        im.alpha_composite(lg, ((im.width - lg.width) // 2, max(0, int(im.height * 0.035) - pad)))
        im.convert("RGB").save(f"{OUT}/splash/castle_{i}_logo.png")
        cells.append((f"castle {i}", im.convert("RGB").resize((640, 360), Image.LANCZOS)))
    grid(cells, 2, 640, 360, "The year-round loading picture (with the logo): pick one").save(f"{OUT}/sheets/splash.png")


KEY = (1, 254, 3)


def cut(path, cell=128, square=True):
    """cut_icons.py's cut: fill the background from the edges, close pinholes, dark soft edges.
    square=False (a ribbon): keep its shape, cell is then its width."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    work = im.filter(ImageFilter.MedianFilter(5))
    seeds = [(x, y) for x in range(0, w, 56) for y in (0, h - 1)] + [(x, y) for y in range(0, h, 56) for x in (0, w - 1)]
    for sd in seeds:
        if work.getpixel(sd) != KEY:
            ImageDraw.floodfill(work, sd, KEY, thresh=70)
    bg = Image.eval(ImageChops.difference(work, Image.new("RGB", (w, h), KEY)).convert("L"), lambda v: 255 if v < 8 else 0)
    bg = bg.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    alpha = Image.eval(bg, lambda v: 255 - v).filter(ImageFilter.GaussianBlur(1.2))
    rgba = im.convert("RGBA")
    dark = Image.new("RGBA", (w, h), (12, 8, 16, 255))
    edge = Image.eval(alpha, lambda v: 255 if 0 < v < 250 else 0)
    rgba = Image.composite(dark, rgba, edge)
    rgba.putalpha(alpha)
    box = alpha.point(lambda v: 255 if v > 40 else 0).getbbox()
    if box is None:
        return None
    rgba = rgba.crop(box)
    if not square:
        return rgba.resize((cell, max(1, int(rgba.height * cell / rgba.width))), Image.LANCZOS)
    side = int(max(rgba.size) * 1.08)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(rgba, ((side - rgba.width) // 2, (side - rgba.height) // 2))
    return sq.resize((cell, cell), Image.LANCZOS)


def tricks():
    os.makedirs(f"{OUT}/tricks/cut", exist_ok=True)
    cells = []
    for k in ("pumpkin", "backwards", "tiny", "ghostface"):
        for i in range(4):
            p = f"{OUT}/tricks/{k}_{i}.png"
            tile = Image.new("RGBA", (200, 200), BG + (255,))
            ImageDraw.Draw(tile).ellipse((20, 20, 180, 180), fill=(40, 30, 58, 255), outline=(255, 214, 90, 255), width=4)
            ic = cut(p) if os.path.exists(p) else None
            if ic is not None:
                ic.save(f"{OUT}/tricks/cut/{k}_{i}.png")
                tile.alpha_composite(ic, (36, 36))
                small = ic.resize((48, 48), Image.LANCZOS)   # about its size on a phone's HUD card
                tile.alpha_composite(small, (146, 146))
            cells.append((f"{k} {i}", tile.convert("RGB")))
    grid(cells, 4, 200, 200, "Candy trick badges (big, and small at the bottom right): pick one a row").save(f"{OUT}/sheets/tricks.png")


def backdrops():
    now = Image.open(os.path.join(REPO, "bench/assets/bg_castle_far.png")).convert("RGBA")
    cells = [("today (bg_castle_far)", now.resize((960, 540), Image.NEAREST))]
    os.makedirs(f"{OUT}/backdrops/pix", exist_ok=True)
    for m in ("z", "k"):
        for i in range(3):
            p = f"{OUT}/backdrops/castle_{m}{i}.png"
            if not os.path.exists(p):
                cells.append((f"{m}{i}", None))
                continue
            im = Image.open(p).convert("RGB").resize((480, 270), Image.BOX)
            im = im.quantize(colors=40, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
            im.save(f"{OUT}/backdrops/pix/castle_{m}{i}.png")
            cells.append((f"{m}{i}", im.resize((960, 540), Image.NEAREST)))
    grid(cells, 2, 960, 540, "Castle far backdrop, at the game's pixel size (drawn 4x in the game): today, then the tries").save(f"{OUT}/sheets/backdrops.png")


def winner():
    cells = []
    for k in ("castle", "spooky"):
        for i in range(4):
            p = f"{OUT}/winner/{k}_{i}.png"
            cells.append((f"{k} {i}", Image.open(p).convert("RGB").resize((480, 270), Image.LANCZOS) if os.path.exists(p) else None))
    grid(cells, 4, 480, 270, "The winner's screen backdrop: pick a castle one, and a spooky one for October").save(f"{OUT}/sheets/winner.png")


COLOURS = ["red", "blue", "green", "yellow", "purple", "orange", "teal", "pink"]


def portraits():
    cells = []
    for t in range(4):
        for c in COLOURS:
            p = f"{OUT}/portraits/{c}_{t}.png"
            cells.append((f"{c} {t}", Image.open(p).convert("RGB").resize((180, 240), Image.LANCZOS) if os.path.exists(p) else None))
    grid(cells, 8, 180, 240, "Winner portraits: a row is one try, the same seed for all 8 colours. Pick a row (or mix)").save(f"{OUT}/sheets/portraits.png")


UI = ["power", "bots", "level", "look", "controls", "leave", "crown"]


def ui():
    os.makedirs(f"{OUT}/ui/cut", exist_ok=True)
    cells = []
    for k in UI:
        for i in range(4):
            p = f"{OUT}/ui/{k}_{i}.png"
            tile = Image.new("RGBA", (200, 200), BG + (255,))
            ImageDraw.Draw(tile).ellipse((20, 20, 180, 180), fill=(40, 30, 58, 255), outline=(255, 214, 90, 255), width=4)
            ic = cut(p) if os.path.exists(p) else None
            if ic is not None:
                ic.save(f"{OUT}/ui/cut/{k}_{i}.png")
                tile.alpha_composite(ic, (36, 36))
                tile.alpha_composite(ic.resize((48, 48), Image.LANCZOS), (146, 146))
            cells.append((f"{k} {i}", tile.convert("RGB")))
    grid(cells, 4, 200, 200, "Lobby button icons and the winner's crown (big, and small at the bottom right): pick one a row").save(f"{OUT}/sheets/ui.png")
    rcells = []
    for i in range(4):
        p = f"{OUT}/ui/ribbon_{i}.png"
        tile = Image.new("RGBA", (700, 200), BG + (255,))
        rb = cut(p, 640, square=False) if os.path.exists(p) else None
        if rb is not None:
            rb.save(f"{OUT}/ui/cut/ribbon_{i}.png")
            tile.alpha_composite(rb, ((700 - rb.width) // 2, max(0, (200 - rb.height) // 2)))
        rcells.append((f"ribbon {i}", tile.convert("RGB")))
    grid(rcells, 2, 700, 200, "A ribbon behind the round banners (ROUND 2, NAME WINS THE ROUND): pick one").save(f"{OUT}/sheets/ribbons.png")


if __name__ == "__main__":
    import sys
    jobs = {f.__name__: f for f in (cards, splash, tricks, backdrops, winner, portraits, ui)}
    for job in ([jobs[a] for a in sys.argv[1:]] if sys.argv[1:] else jobs.values()):
        try:
            job()
            print("ok", job.__name__)
        except Exception as e:   # one job's missing pictures never stop the others
            print("FAIL", job.__name__, e)
