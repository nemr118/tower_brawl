#!/usr/bin/env python3
"""17 power-up icons in one style (Z-Image Turbo), on flat magenta for cutting out."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
STYLE = ("a single flat vector video game power-up icon of {}, thick black outline, bright saturated colours, "
         "simple bold shapes, glossy highlight, centred, nothing else in the picture, plain flat solid magenta background")
ICONS = {1: "a flaming arrow, its arrowhead wrapped in orange fire", 2: "a round black bomb with a lit sparking fuse",
         3: "a purple poison potion bottle with a skull label and bubbles", 4: "a puffy grey smoke cloud",
         5: "a round glowing blue magic shield", 6: "a golden infinity symbol made of two arrows",
         7: "a pair of white feathered wings", 8: "one giant green arrow pointing up and to the right",
         9: "a cute pale green glowing ghost cat", 10: "a blue rain cloud with falling raindrops and a small red umbrella",
         11: "a see-through pale blue ghostly hooded cloak fading into sparkles", 12: "a light blue ice crystal snowflake",
         13: "a round wooden shield with a ring of sharp steel spikes sticking out of its rim", 14: "a yellow lightning bolt with speed lines",
         15: "a wrapped Halloween candy with a purple and orange striped wrapper", 16: "a jack-o'-lantern bomb with a burning fuse",
         17: "three black bats with red eyes flying together"}
os.makedirs(C.OUT + "/icons", exist_ok=True)
only = [int(a) for a in sys.argv[1:]]
jobs = [(f"icons/pu{k:02d}", "z", 896, 896, STYLE.format(v)) for k, v in ICONS.items() if not only or k in only]
C.run(jobs, seed_base=4242)
