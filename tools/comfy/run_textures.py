#!/usr/bin/env python3
"""Platform textures for THE HAUNTED HOUSE and THE BOILER ROOM (Z-Image Turbo), seamless after
make_seamless (cut_textures.py)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
PIX = "seamless tileable texture, 16-bit pixel art video game tile, crisp pixels, limited palette, flat front view, even lighting, no shadows, fills the whole picture"
TEX = {
    "hh_stone": f"{PIX}, old haunted castle stone bricks, dark purple and grey stones of different sizes, cracks, small moss patches, a few cobwebs",
    "hh_stone2": f"{PIX}, ancient crumbling haunted mansion stone wall blocks, dusky violet grey, chipped corners, thin green moss lines",
    "hh_wood": f"{PIX}, old rotten dark wooden floor planks running sideways, iron nails, worn purple-brown wood grain",
    "boiler_steel": f"{PIX}, dark rusty riveted steel plates, rows of bolts along the seams, scratches, grime and rust streaks",
    "boiler_steel2": f"{PIX}, industrial boiler room wall of heavy riveted iron panels, dark gunmetal with orange rust, oil stains",
    "boiler_grating": f"{PIX}, rusty dark metal floor grating with a diamond pattern, seen from the front, thin bars",
}
os.makedirs(C.OUT + "/tex", exist_ok=True)
only = sys.argv[1:]
C.run([(f"tex/{k}", "z", 768, 768, v) for k, v in TEX.items() if not only or k in only], seed_base=5150)
