#!/usr/bin/env python3
"""The lobby's arena cards (2026-10-26): a painted picture of each arena, in the loading
picture's style (FLUX.2 klein), 4 tries each to pick from. MIX is made from the picked four."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
STYLE = ("a painted comic book illustration with thick black ink outlines and rich saturated colours, dramatic "
         "cinematic lighting, detailed video game key art, {}, no people, no text, no letters, no logo")
CARDS = {
 "keep": "a medieval stone castle courtyard at dusk seen from the front: a squat stone keep with battlements standing on "
         "two short stone legs above the courtyard floor, a tall watchtower behind it, stone steps up the side walls, "
         "colourful banners, warm torchlight, deep blue evening sky with the first stars",
 "bridges": "narrow stone bridges and wooden walkways crossing a deep misty chasm between tall castle towers, hanging "
            "chains, green moss and ivy, colourful banners, moonlit blue night, soft mist glowing below",
 "haunted": "the inside of a spooky haunted mansion at night: purple stone walls, tall windows glowing orange, a huge "
            "orange full moon outside, carved jack-o'-lanterns, cobwebs, candles, little bats, friendly and spooky for children",
 "boiler": "a dark spooky old boiler room: a huge round iron boiler in the middle with a glowing orange furnace door, red "
           "and green striped pipes, hissing white steam, metal grating walkways, rusty riveted steel walls, a red glow, "
           "spooky but friendly for children",
}
os.makedirs(C.OUT + "/cards", exist_ok=True)
only = sys.argv[1:]
jobs = [(f"cards/{k}_{i}", "k", 1024, 576, STYLE.format(v)) for k, v in CARDS.items() if not only or k in only for i in range(4)]
C.run(jobs, seed_base=2610)
