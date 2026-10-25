#!/usr/bin/env python3
"""The new game's loading picture (2026-10-25): TOWER BRAWL in the lobby's font,
a gold gradient, a dark edge, a red rim, a soft glow, and a ribbon under it, on a
clear background (the page's splash colour shows round it). Replaces Godot's own
logo while the page loads. Original art drawn here; the font is Noto Sans
(open licence, bench/assets/fonts/OFL.txt).
    python3 tools/v2_splash.py [OUT]   (default: bench/assets/splash.png)
Then in bench/project.godot, [application]:
    boot_splash/bg_color=Color(0.04, 0.02, 0.08, 1)
    boot_splash/image="res://assets/splash.png"
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "bench/assets/splash.png")
FONT = os.path.join(os.path.dirname(OUT), "fonts/lobby_display.ttf")
if not os.path.exists(FONT):
    FONT = os.path.join(ROOT, "bench/assets/fonts/lobby_display.ttf")
W, H = 1000, 420
TOP, BOT = (255, 246, 178), (245, 150, 30)      # the letters: light gold to orange
EDGE, RIM = (26, 12, 6), (140, 50, 14)
RIBBON, RIBBON_DARK, RIBBON_TEXT = (158, 30, 36), (86, 12, 18), (255, 230, 150)

img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
text = "TOWER BRAWL"
d = ImageDraw.Draw(img)
size = 170
while True:   # as big as fits with room for the glow
    font = ImageFont.truetype(FONT, size)
    tw = d.textlength(text, font=font)
    if tw <= W - 170 or size <= 60:
        break
    size -= 4
x, y = (W - tw) / 2, 50
# a soft glow behind
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow).text((x, y), text, font=font, fill=(255, 150, 40, 150), stroke_width=34, stroke_fill=(255, 150, 40, 150))
img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(26)))
# the shadow, the dark edge, the rim
for dx, dy, sw, col in [(0, 12, 24, (0, 0, 0, 150)), (0, 0, 22, EDGE + (255,)), (0, 0, 10, RIM + (255,))]:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((x + dx, y + dy), text, font=font, fill=col, stroke_width=sw, stroke_fill=col)
    img = Image.alpha_composite(img, layer)
# the letters: a gradient through the text's mask
mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask).text((x, y), text, font=font, fill=255)
box = mask.getbbox()
grad = Image.new("RGBA", (W, H))
gd = ImageDraw.Draw(grad)
for yy in range(H):
    k = min(1.0, max(0.0, (yy - box[1]) / max(1, box[3] - box[1])))
    gd.line([(0, yy), (W, yy)], fill=tuple(int(TOP[i] + (BOT[i] - TOP[i]) * k) for i in range(3)) + (255,))
img.paste(grad, (0, 0), mask)
# the ribbon
d = ImageDraw.Draw(img)
rf = ImageFont.truetype(FONT, 40)
rt = "8 PLAYER ARCHER BRAWL"
rw = d.textlength(rt, font=rf) + 100
rx0, rx1, ry = (W - rw) / 2, (W + rw) / 2, box[3] + 30
for side, xe in [(-1, rx0), (1, rx1)]:
    d.polygon([(xe - side * 10, ry + 14), (xe + side * 60, ry + 14), (xe + side * 42, ry + 44), (xe + side * 60, ry + 74),
               (xe - side * 10, ry + 74)], fill=RIBBON_DARK)
d.rectangle([rx0, ry, rx1, ry + 60], fill=RIBBON)
d.rectangle([rx0, ry, rx1, ry + 5], fill=(200, 70, 70))
d.rectangle([rx0, ry + 54, rx1, ry + 60], fill=RIBBON_DARK)
d.text(((W - (rw - 100)) / 2, ry + 7), rt, font=rf, fill=RIBBON_TEXT, stroke_width=4, stroke_fill=EDGE)
img = img.crop((0, 0, W, min(H, int(ry + 90))))
img.save(OUT, optimize=True)
print(OUT, img.size, os.path.getsize(OUT), "bytes")
