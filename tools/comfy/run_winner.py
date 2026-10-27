#!/usr/bin/env python3
"""The winner's screen (2026-10-26, the user: "Let's make it look great"): a painted backdrop
behind the podium (a castle celebration, and a spooky one for October), 4 tries each (FLUX.2
klein); and a painted portrait of the hooded archer in each of the 8 seat colours, 4 tries, the
same seed for every colour in a try (so one try is one hero in 8 colours)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
STYLE = ("a painted comic book illustration with thick black ink outlines and rich saturated colours, dramatic "
         "cinematic lighting, video game key art, {}, no text, no letters, no logo")
BACKDROPS = {
 "castle": "a grand castle terrace at night, huge colourful fireworks bursting in the starry sky, gold and red victory "
           "banners hanging from stone arches on both sides, warm torchlight, confetti in the air, an open empty stone "
           "terrace in the middle, festive and triumphant, no people",
 "spooky": "a haunted castle terrace at night under a huge orange full moon, purple and orange fireworks bursting in the "
           "sky, carved jack-o'-lanterns, little bats, orange and purple victory banners on stone arches, candles, an open "
           "empty stone terrace in the middle, festive and spooky for children, no people",
}
COLOURS = ["red", "blue", "green", "yellow", "purple", "orange", "teal", "pink"]   # the seats' colours, P1 to P8
PORTRAIT = ("a waist-up portrait of a heroic hooded archer in a bright {} hooded cloak, the face hidden in the shadow of "
            "the hood with two small glowing eyes, raising a wooden longbow in victory, a leather belt and a quiver of "
            "arrows, three-quarter view, a dark purple night background with soft light rays behind, one character only")
only = sys.argv[1:]
if not only or "backdrops" in only:
    os.makedirs(C.OUT + "/winner", exist_ok=True)
    C.run([(f"winner/{k}_{i}", "k", 1280, 720, STYLE.format(v)) for k, v in BACKDROPS.items() for i in range(4)], seed_base=6100)
if not only or "portraits" in only:
    os.makedirs(C.OUT + "/portraits", exist_ok=True)
    for t in range(4):
        for c in COLOURS:   # one call a picture: every colour of try t gets the same seed
            C.run([(f"portraits/{c}_{t}", "k", 768, 1024, STYLE.format(PORTRAIT.format(c)))], seed_base=7300 + t)
