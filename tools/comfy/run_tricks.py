#!/usr/bin/env python3
"""The candy tricks' badges (2026-10-26) in the power-up icons' style (Z-Image Turbo), on
flat magenta for cutting out (cut_icons.py's way). 4 tries each."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
STYLE = ("a single flat vector video game power-up icon of {}, thick black outline, bright saturated colours, "
         "simple bold shapes, glossy highlight, centred, nothing else in the picture, plain flat solid magenta background")   # run_icons.py's
TRICKS = {
 "pumpkin": "a grinning carved jack-o'-lantern head on a tiny body, hopping, with little motion lines",
 "backwards": "two curved arrows, one blue pointing left and one red pointing right, swapping places in a loop, with dizzy stars",
 "tiny": "a very small cute hooded archer standing next to a giant magnifying glass",
 "ghostface": "a white ghost mask with big black drooping eyes and a long open mouth, framed by a black hood, with a small silver hunting knife",
}
os.makedirs(C.OUT + "/tricks", exist_ok=True)
only = sys.argv[1:]
C.run([(f"tricks/{k}_{i}", "z", 896, 896, STYLE.format(v)) for k, v in TRICKS.items() if not only or k in only for i in range(4)],
      seed_base=1031)
