#!/usr/bin/env python3
"""Cut the 46 award pictures off their backgrounds and pack the game's sheet:
out/awards/<slug>.png (768 px) -> award_art.png, 8 a row, 80 px each, a thin white edge,
in the order of run_awards.py's AW (the same as client/award_art.gd ORDER)."""
import os, re
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ns = {"__file__": os.path.join(HERE, "cut_icons.py")}
exec(open(ns["__file__"]).read().split("sheet = Image.new")[0], ns)   # cut(): the power-up icons' cut
cut = ns["cut"]
names = re.findall(r'"([A-Z!\' ]+)": "', open(os.path.join(HERE, "run_awards.py")).read())
def slug(n): return re.sub(r"[^a-z0-9]+", "_", n.lower()).strip("_")
CELL, PER = 80, 8
rows = (len(names) + PER - 1) // PER
sheet = Image.new("RGBA", (CELL * PER, CELL * rows), (0, 0, 0, 0))
for i, n in enumerate(names):
    p = os.path.join(os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy")), "awards", slug(n) + ".png")
    ic = cut(p) if os.path.exists(p) else None
    if ic is None:
        print("missing or empty:", n)
        continue
    pad = Image.new("RGBA", (148, 148), (0, 0, 0, 0))
    pad.paste(ic, (10, 10), ic)
    ring = pad.getchannel("A").point(lambda v: 255 if v > 60 else 0).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(0.8))
    st = Image.new("RGBA", pad.size, (255, 255, 255, 0))
    st.putalpha(ring.point(lambda v: int(v * 0.95)))
    st.alpha_composite(pad)
    sheet.paste(st.resize((CELL, CELL), Image.LANCZOS), ((i % PER) * CELL, (i // PER) * CELL))
out = os.path.join(os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy")), "award_art.png")
sheet.save(out, optimize=True)
print(len(names), "awards ->", out, os.path.getsize(out), "bytes", sheet.size)
view = Image.new("RGBA", sheet.size, (36, 28, 60, 255))
view.alpha_composite(sheet)
view.convert("RGB").resize((sheet.width * 2, sheet.height * 2), Image.LANCZOS).save(os.path.join(os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy")), "award_art_view.png"))
