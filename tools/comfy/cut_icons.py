#!/usr/bin/env python3
"""Cut the power-up icons off their background and pack them into one sheet.
out/icons/puNN.png (896 px) -> out/icons/cut/puNN.png (128 px, see-through) and
out/icons/pu_icons.png: one row of 18 cells x 128 px (cell k-1 is power-up k; the 18th,
GHOSTFACE, stays drawn in code, so its cell is left empty).
The background is filled in from the picture's edges (whatever its colour: the model
did not always paint flat magenta), stopping at the icons' thick black outline."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

D = os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy")) + "/icons"
os.makedirs(D + "/cut", exist_ok=True)
CELL = 128
KEY = (1, 254, 3)

def cut(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    work = im.filter(ImageFilter.MedianFilter(5))          # calm the speckled backgrounds first
    seeds = [(x, y) for x in range(0, w, 56) for y in (0, h - 1)] + [(x, y) for y in range(0, h, 56) for x in (0, w - 1)]
    for sd in seeds:
        if work.getpixel(sd) != KEY:
            ImageDraw.floodfill(work, sd, KEY, thresh=70)
    bg = Image.eval(ImageChops.difference(work, Image.new("RGB", (w, h), KEY)).convert("L"), lambda v: 255 if v < 8 else 0)
    bg = bg.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))   # close the pinholes
    alpha = Image.eval(bg, lambda v: 255 - v).filter(ImageFilter.GaussianBlur(1.2))
    rgba = im.convert("RGBA")
    # soft edge pixels take the outline's black, not the background's colour
    dark = Image.new("RGBA", (w, h), (12, 8, 16, 255))
    edge = Image.eval(alpha, lambda v: 255 if 0 < v < 250 else 0)
    rgba = Image.composite(dark, rgba, edge)
    rgba.putalpha(alpha)
    box = alpha.point(lambda v: 255 if v > 40 else 0).getbbox()
    if box is None:
        return None
    rgba = rgba.crop(box)
    side = int(max(rgba.size) * 1.08)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(rgba, ((side - rgba.width) // 2, (side - rgba.height) // 2))
    return sq.resize((CELL, CELL), Image.LANCZOS)

sheet = Image.new("RGBA", (CELL * 18, CELL), (0, 0, 0, 0))
for k in range(1, 18):
    p = f"{D}/pu{k:02d}.png"
    if not os.path.exists(p):
        print(f"missing pu{k:02d}")
        continue
    ic = cut(p)
    if ic is None:
        print(f"empty pu{k:02d}")
        continue
    ic.save(f"{D}/cut/pu{k:02d}.png")
    sheet.paste(ic, ((k - 1) * CELL, 0))
sheet.save(f"{D}/pu_icons.png", optimize=True)
print("sheet:", f"{D}/pu_icons.png", os.path.getsize(f"{D}/pu_icons.png"), "bytes")
