#!/usr/bin/env python3
"""The small pictures of the new game's page (bench/web/shell.html), made from art the
game already has. No GPU: only cuts, colours and a drawn moon.

1. The Home Screen icon (the app icon). Three candidates, each a square picture with no
   clear corners (the phone rounds them):
     1 "hood"    the red hero's hood and glowing eyes, close up, on a gold moon in a night sky
     2 "archer"  the red hero drawing the bow (more of the body), on the same moon
     3 "sunset"  a bold cut of the red archer from the castle loading picture

       PY tools/v2_page_art.py                 # the candidates and the sheet, into shots/icons/
       PY tools/v2_page_art.py --pick 1        # and write the picked one into bench/web/pwa/
   (PY: a Python with Pillow.) The files it writes for the page (tools/v2_build.sh copies them):
     icon-512.png, icon-192.png   the manifest's icons
     icon-180.png                 the iPhone's Home Screen icon
     icon-maskable-512.png        for Android's round and squircle masks (the hero sits smaller)
     icon-96.png, icon-32.png     the browser tab's icons

2. The soft backdrops. A tiny blurred copy of each loading picture (48 x 27, about 1 KB),
   printed as CSS lines to paste into shell.html. The page shows it at once, under the
   real picture, so the screen is never bare and a screen that is not 16:9 has no bars.

       PY tools/v2_page_art.py --backs
"""
import argparse
import base64
import io
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
HERO = os.path.join(ROOT, "bench/assets/heroes/hero_0.png")           # the red hero, clear background
CASTLE = os.path.join(ROOT, "bench/web/page/splash_castle.png")       # the castle loading picture
S = 1024                                                              # the working size; saved smaller


def lerp(a, b, k):
    return tuple(int(round(a[i] + (b[i] - a[i]) * k)) for i in range(3))


def night_sky(moon_c, moon_r):
    """A night sky: deep blue at the top to purple at the bottom, stars, and a big gold moon
    with an ink edge and a glow, as in the loading pictures."""
    top, mid, bot = (8, 10, 44), (34, 20, 96), (104, 30, 110)
    sky = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(sky)
    for y in range(S):
        k = y / (S - 1)
        d.line([(0, y), (S, y)], fill=lerp(top, mid, k / 0.6) if k < 0.6 else lerp(mid, bot, (k - 0.6) / 0.4))
    rnd = random.Random(7)                     # the same stars every time
    for _ in range(90):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S * 0.8)
        if math.hypot(x - moon_c[0], y - moon_c[1]) < moon_r * 1.12:
            continue
        r = rnd.choice([2, 2, 3, 3, 4, 6])
        d.ellipse([x - r, y - r, x + r, y + r], fill=lerp((255, 244, 200), (190, 200, 255), rnd.random()))
    # the moon's glow
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([moon_c[0] - moon_r * 1.1, moon_c[1] - moon_r * 1.1, moon_c[0] + moon_r * 1.1, moon_c[1] + moon_r * 1.1],
               fill=(255, 120, 60))
    sky = ImageChops.screen(sky, glow.filter(ImageFilter.GaussianBlur(moon_r * 0.16)).point(lambda v: int(v * 0.5)))
    # the moon: pale gold in the middle, orange at the rim, a few soft marks, an ink edge
    moon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    md = ImageDraw.Draw(moon)
    for i in range(60, 0, -1):
        k = i / 60.0
        r = moon_r * k
        md.ellipse([moon_c[0] - r, moon_c[1] - r, moon_c[0] + r, moon_c[1] + r], fill=lerp((255, 247, 190), (255, 176, 46), k ** 2.2) + (255,))
    marks = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    kd = ImageDraw.Draw(marks)
    for fx, fy, fr in [(-0.5, -0.38, 0.2), (0.42, -0.52, 0.14), (0.62, 0.05, 0.16), (-0.68, 0.2, 0.11), (0.08, -0.76, 0.08)]:
        cx, cy, rr = moon_c[0] + fx * moon_r, moon_c[1] + fy * moon_r, fr * moon_r
        kd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(240, 150, 40, 70))
    moon = Image.alpha_composite(moon, marks.filter(ImageFilter.GaussianBlur(10)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([moon_c[0] - moon_r, moon_c[1] - moon_r, moon_c[0] + moon_r, moon_c[1] + moon_r], fill=255)
    moon.putalpha(mask.filter(ImageFilter.GaussianBlur(1.5)))
    out = sky.convert("RGBA")
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).ellipse([moon_c[0] - moon_r - 9, moon_c[1] - moon_r - 9, moon_c[0] + moon_r + 9, moon_c[1] + moon_r + 9],
                                 fill=(60, 18, 30, 255))
    out = Image.alpha_composite(out, edge.filter(ImageFilter.GaussianBlur(1.2)))
    return Image.alpha_composite(out, moon)


def vignette(img, strength=0.55):
    """Darker corners, so the middle pops."""
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([-w * 0.18, -h * 0.18, w * 1.18, h * 1.18], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(w * 0.12))
    dark = Image.new("RGBA", (w, h), (6, 4, 26, 255))
    return Image.composite(img, dark, m.point(lambda v: int(255 - (255 - v) * strength)))


def hero_on(bg, scale, face_at, ink=14):
    """The red hero on bg: scaled, its face (source point 242, 262) put at face_at, with a
    thick ink edge and a soft shadow so it stands off the moon."""
    hero = Image.open(HERO).convert("RGBA")
    w, h = int(hero.width * scale), int(hero.height * scale)
    hero = hero.resize((w, h), Image.LANCZOS)
    hero = ImageEnhance.Color(hero).enhance(1.12)
    ox, oy = int(face_at[0] - 242 * scale), int(face_at[1] - 262 * scale)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(hero, (ox, oy), hero)
    a = layer.getchannel("A")
    fat = a.filter(ImageFilter.MaxFilter(ink * 2 + 1)).filter(ImageFilter.GaussianBlur(1.5))
    soft = Image.new("L", (S, S), 0)
    soft.paste(fat.filter(ImageFilter.GaussianBlur(26)).point(lambda v: int(v * 0.6)), (0, 18))   # 18 px lower
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(soft)
    out = Image.alpha_composite(bg, shadow)
    edge = Image.new("RGBA", (S, S), (22, 6, 14, 255))
    edge.putalpha(fat)
    out = Image.alpha_composite(out, edge)
    out = Image.alpha_composite(out, layer)
    # the two glowing eyes: a small soft light on each, so they still read at 60 px
    eyes = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ed = ImageDraw.Draw(eyes)
    for ex, ey in [(223, 257), (267, 250)]:
        x, y, r = ox + ex * scale, oy + ey * scale, 6.4 * scale
        ed.ellipse([x - r, y - r * 0.6, x + r, y + r * 0.6], fill=(255, 252, 232, 255))
    glow = eyes.filter(ImageFilter.GaussianBlur(4.5 * scale))
    glow.putalpha(glow.getchannel("A").point(lambda v: min(255, int(v * 2.2))))
    out = Image.alpha_composite(out, glow)
    return Image.alpha_composite(out, eyes.filter(ImageFilter.GaussianBlur(0.5 * scale)))


def make_hood(safe=1.0):
    """1: the hood and the eyes, close up. safe < 1: everything smaller (the maskable icon)."""
    bg = night_sky((S * 0.5, S * 0.41), S * 0.365 * (0.9 if safe < 1 else 1.0))
    img = hero_on(bg, 2.6 * safe, (S * 0.48, S * (0.46 if safe == 1.0 else 0.45)))
    return vignette(img)


def make_archer(safe=1.0):
    """2: the archer with the bow drawn."""
    bg = night_sky((S * 0.47, S * 0.42), S * 0.37 * (0.9 if safe < 1 else 1.0))
    img = hero_on(bg, 1.95 * safe, (S * 0.45, S * (0.46 if safe == 1.0 else 0.44)), ink=12)
    return vignette(img)


def make_sunset(safe=1.0):
    """3: the red archer cut from the castle loading picture (the sunset)."""
    src = Image.open(CASTLE).convert("RGB")
    side = 500 if safe == 1.0 else 528      # under the title's letters (they end at y 185)
    cx, cy = 356, 442                      # the middle of the red archer
    x0 = max(0, min(src.width - side, cx - side // 2))
    y0 = max(190, min(src.height - side, cy - side // 2))
    img = src.crop((x0, y0, x0 + side, y0 + side)).resize((S, S), Image.LANCZOS).convert("RGBA")
    img = ImageEnhance.Color(img).enhance(1.15)
    img = ImageEnhance.Contrast(img).enhance(1.08)
    return vignette(img, 0.35)


CANDIDATES = [("hood", make_hood), ("archer", make_archer), ("sunset", make_sunset)]


def rounded(img, size):
    """The icon as a phone shows it: its corners rounded (about 22% of its side)."""
    im = img.resize((size * 4, size * 4), Image.LANCZOS)
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=int(im.width * 0.2237), fill=255)
    im.putalpha(m)
    return im.resize((size, size), Image.LANCZOS)


def sheet(icons, path):
    """One sheet: each candidate at 512, 180 and 60 px, on a dark and on a light wall."""
    pad = 40
    w = pad + len(icons) * (512 + pad)
    h = pad + 512 + pad + 180 + pad + 60 + pad + 60 + pad
    out = Image.new("RGBA", (w, h), (30, 30, 40, 255))
    d = ImageDraw.Draw(out)
    font = os.path.join(ROOT, "bench/assets/fonts/lobby_display.ttf")
    big, small = ImageFont.truetype(font, 40), ImageFont.truetype(font, 22)
    d.rectangle([0, h - 60 - pad * 1.5, w, h], fill=(232, 232, 236, 255))
    for i, (name, img) in enumerate(icons):
        x = pad + i * (512 + pad)
        out.alpha_composite(rounded(img, 512), (x, pad))
        out.alpha_composite(rounded(img, 180), (x, pad + 512 + pad))
        out.alpha_composite(rounded(img, 60), (x + 220, pad + 512 + pad))
        out.alpha_composite(rounded(img, 60), (x + 220, pad + 512 + pad + 100))
        out.alpha_composite(rounded(img, 60), (x, h - 60 - pad // 2 - 10))
        out.alpha_composite(rounded(img, 32), (x + 100, h - 60 - pad // 2 + 4))
        d.text((x + 300, pad + 512 + pad + 4), f"{i + 1}  {name.upper()}", font=big, fill=(240, 240, 240, 255))
        d.text((x + 300, pad + 512 + pad + 54), "512, 180, 60 px", font=small, fill=(170, 170, 180, 255))
        d.text((x + 150, h - 60 - pad // 2 + 4), "60 and 32 px on a light wall", font=small, fill=(60, 60, 70, 255))
    out.convert("RGB").save(path)
    print("sheet", path, out.size)


def backs():
    """Print the four soft backdrops as CSS (the lines between the two marks in shell.html)."""
    pics = {"castle": CASTLE, "halloween": os.path.join(ROOT, "bench/assets/splash.png"),
            "harvest": os.path.join(ROOT, "bench/web/page/splash_harvest.png"),
            "christmas": os.path.join(ROOT, "bench/web/page/splash_christmas.png")}   # p4.22
    for name, path in pics.items():
        im = Image.open(path).convert("RGB").resize((192, 108), Image.LANCZOS)
        im = im.filter(ImageFilter.GaussianBlur(7)).resize((48, 27), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=62, optimize=True)
        b64 = base64.b64encode(buf.getvalue()).decode()
        print(f'html[data-dress="{name}"] {{ --tb-back: url(data:image/jpeg;base64,{b64}); }}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "shots/icons"))
    ap.add_argument("--pick", type=int, default=0, help="1, 2 or 3: write this one into bench/web/pwa/")
    ap.add_argument("--backs", action="store_true", help="print the soft backdrops as CSS and stop")
    a = ap.parse_args()
    if a.backs:
        backs()
        return
    os.makedirs(a.out, exist_ok=True)
    icons = []
    for name, fn in CANDIDATES:
        img = fn()
        icons.append((name, img))
        img.resize((512, 512), Image.LANCZOS).convert("RGB").save(os.path.join(a.out, f"candidate_{name}_512.png"), optimize=True)
    sheet(icons, os.path.join(a.out, "icon_sheet.png"))
    if a.pick:
        name, fn = CANDIDATES[a.pick - 1]
        pwa = os.path.join(ROOT, "bench/web/pwa")
        full = fn().convert("RGB")
        for size in (512, 192, 180, 96, 32):
            p = os.path.join(pwa, f"icon-{size}.png")
            full.resize((size, size), Image.LANCZOS).save(p, optimize=True)
            print(p, os.path.getsize(p), "bytes")
        p = os.path.join(pwa, "icon-maskable-512.png")
        fn(0.8).convert("RGB").resize((512, 512), Image.LANCZOS).save(p, optimize=True)
        print(p, os.path.getsize(p), "bytes")
        print("picked", a.pick, name)


if __name__ == "__main__":
    main()
