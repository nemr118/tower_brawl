#!/usr/bin/env python3
"""A pixel-style far backdrop for the castle arenas (2026-10-26), to try against
assets/bg_castle_far.png (480 x 270, drawn 4x): 3 tries each from Z-Image Turbo and
FLUX.2 klein; pixelate_backdrop.py brings them to 480 x 270."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
PROMPT = ("pixel art, 16-bit video game background, a calm night sky over distant castle towers and rolling hills, a pale "
          "full moon behind soft clouds, many small stars, dark navy blue and deep purple, low contrast muted colours, "
          "silhouettes only, wide panorama, no foreground, no text")
os.makedirs(C.OUT + "/backdrops", exist_ok=True)
C.run([(f"backdrops/castle_{m}{i}", m, 1024, 576, PROMPT) for m in ("z", "k") for i in range(3)], seed_base=4040)
