#!/usr/bin/env python3
"""The loading picture for the rest of the year (2026-10-26): the Halloween one's style (FLUX.2
klein), at golden sunset, no pumpkins or bats; clear sky at the top for the logo. 6 tries."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
PROMPT = ("a painted comic book illustration with thick black ink outlines and rich saturated colours, dramatic "
          "cinematic lighting, video game key art: two hooded archers in colourful cloaks, one red and one blue, duelling "
          "with bows on the stone battlements of a castle at golden sunset, arrows flying, colourful banners waving in the "
          "wind, warm orange and pink sky with soft clouds, distant castle towers and green hills, birds, clear open sky "
          "across the top of the picture, no text, no letters, no logo")
os.makedirs(C.OUT + "/splash", exist_ok=True)
C.run([(f"splash/castle_{i}", "k", 1280, 720, PROMPT) for i in range(6)], seed_base=3110)
