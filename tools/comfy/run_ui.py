#!/usr/bin/env python3
"""Screen pieces (2026-10-26, the user: "Look at any UI elements that may make sense to have
comfyui make"): small icons for the lobby's buttons and a crown for the winner (Z-Image Turbo, the
power-up icons' style, on flat magenta for cutting out), and a ribbon for the round banners. 4 tries each."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
STYLE = ("a single flat vector video game icon of {}, thick black outline, bright saturated colours, simple bold "
         "shapes, glossy highlight, centred, nothing else in the picture, plain flat solid magenta background")   # run_icons.py's
ICONS = {
 "power": "a glowing purple magic orb with little sparkles",          # POWER-UPS
 "bots": "a cute friendly little robot head with round glowing eyes",  # BOTS
 "level": "a speedometer gauge, green to red, with its needle in the red",   # BOT LEVEL
 "look": "a painter's palette with blobs of paint and a brush",       # LOOK
 "controls": "a handheld game controller with buttons and a thumb stick",   # CONTROLS
 "leave": "a wooden door standing open with a green arrow going out", # LEAVE
 "crown": "a golden crown with red and blue jewels",                  # the winner's screen
}
RIBBON = ("a long horizontal red banner ribbon with gold trim and folded swallowtail ends, a flat vector video game "
          "title banner, thick black outline, bright saturated colours, simple bold shapes, glossy highlight, centred, "
          "empty with no words on it, nothing else in the picture, plain flat solid magenta background")
only = sys.argv[1:]
os.makedirs(C.OUT + "/ui", exist_ok=True)
jobs = [(f"ui/{k}_{i}", "z", 896, 896, STYLE.format(v)) for k, v in ICONS.items() if not only or k in only for i in range(4)]
if not only or "ribbon" in only:
    jobs += [(f"ui/ribbon_{i}", "z", 1280, 384, RIBBON) for i in range(4)]
C.run(jobs, seed_base=8800)
