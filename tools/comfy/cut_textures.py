#!/usr/bin/env python3
"""Make ComfyUI's platform textures seamless and game-sized.
<TB_COMFY_OUT>/tex/<name>.png (768 px) -> <TB_COMFY_OUT>/tex/<name>_tile.png: the picture shifted by
half and blended over itself so its edges meet (a seam-free tile), then made small (SIZE px, the
art scripts draw at half the screen's size) with a few colours, so it sits with the game's pixel art."""
import os, sys
import numpy as np
from PIL import Image

OUT = os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy")) + "/tex"
SIZE = int(os.environ.get("TB_TEX_SIZE", "120"))

def seamless(im):
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    h, w = a.shape[:2]
    b = np.roll(np.roll(a, h // 2, 0), w // 2, 1)          # the same picture, its edges now in the middle
    y = np.abs(np.linspace(-1, 1, h))[:, None]
    x = np.abs(np.linspace(-1, 1, w))[None, :]
    m = np.clip((np.maximum(x, y) - 0.55) / 0.4, 0, 1)[..., None]   # 1 at the edges: take the shifted copy there
    return Image.fromarray((a * (1 - m) + b * m).astype(np.uint8))

for name in sys.argv[1:] or sorted(n[:-4] for n in os.listdir(OUT) if n.endswith(".png") and "_tile" not in n):
    src = os.path.join(OUT, name + ".png")
    im = seamless(Image.open(src))
    small = im.resize((SIZE, SIZE), Image.LANCZOS)
    small = small.quantize(colors=40, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    small.save(os.path.join(OUT, name + "_tile.png"))
    # a 3 x 3 check of the seams at 2x
    check = Image.new("RGB", (SIZE * 3, SIZE * 3))
    for i in range(3):
        for j in range(3):
            check.paste(small, (i * SIZE, j * SIZE))
    check.resize((SIZE * 6, SIZE * 6), Image.NEAREST).save(os.path.join(OUT, name + "_check.png"))
    print("ok", name)
