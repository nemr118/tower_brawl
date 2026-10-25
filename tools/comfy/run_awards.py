#!/usr/bin/env python3
"""46 award pictures in one style (Z-Image Turbo), on flat magenta for cutting out."""
import os, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
STYLE = ("a single flat vector cartoon award badge icon of {}, thick black outline, bright saturated colours, "
         "simple bold shapes, glossy highlight, cute and funny, centred, nothing else in the picture, plain flat solid magenta background")
AW = {
 "SHARPSHOOTER": "a red and white target with an arrow in the bullseye", "STOMP CHAMP": "a big boot stomping down with impact stars",
 "BOOM BOOM": "a cartoon explosion cloud with stars", "CAT WHISPERER": "a cute pale green ghost cat with a little heart",
 "CATCH OF THE DAY": "a hand catching an arrow in mid air", "TREASURE HUNTER": "an open treasure chest full of gold coins",
 "PARTY ANIMAL": "a striped party hat with confetti", "PIN MASTER": "an arrow stuck deep in a wooden plank",
 "WALL DECORATION": "a picture frame hanging crooked on a nail", "LIGHTNING ROD": "a metal lightning rod being struck by a yellow lightning bolt",
 "EXTRA CRISPY": "a burnt black piece of toast with little flames", "STINKY": "a green stink cloud with buzzing flies",
 "PANCAKE": "a stack of fluffy pancakes with butter and syrup", "PINCUSHION": "a red pincushion stuck full of arrows",
 "CAT FOOD": "a cat food bowl with fish bones", "OOPS!": "a yellow banana peel",
 "BUTTERFINGERS": "a wooden bow falling with motion lines", "TRIGGER HAPPY": "a quiver overflowing with arrows",
 "PEACEMAKER": "a white dove holding an olive branch", "BOUNCY CASTLE": "a colourful inflatable bouncy castle",
 "NINJA ROLL": "a black ninja mask with a red headband", "SPEED DEMON": "a red running shoe with flames behind it",
 "COUCH POTATO": "a happy potato sitting on a small red couch", "THE FLOOR IS LAVA": "a bubbling pool of orange lava",
 "FREQUENT FLYER": "white feathered wings with a golden ticket", "SURVIVOR": "a red heart with a bandage on it",
 "NAP TIME": "a fluffy pillow with a sleeping cap and Zzz letters", "SPOOKY": "a cute white ghost shouting boo",
 "FRIENDLY GHOST": "a smiling white ghost waving hello", "NOW YOU SEE ME": "a black magic top hat with sparkles",
 "ARROW COLLECTOR": "a bundle of arrows tied with a red ribbon", "ROUND WINNER": "a shiny gold trophy cup",
 "GOOD KITTY": "a black cat with green eyes and a pink heart", "TRICKED!": "a jack-in-the-box with a springy clown",
 "SLASHER": "a cartoon kitchen knife with a sparkle", "SWEET TOOTH": "a swirly lollipop and wrapped candies",
 "SCARY MOVIE STAR": "a movie clapperboard with a little ghost", "GHOST BUSTER": "a cracked white spooky mask with a gold star",
 "GOOD SPORT": "two hands in a friendly handshake", "BEST WIGGLE": "a wiggly smiling worm", "MAIN CHARACTER": "a golden star wearing a crown",
 "WILL WIN NEXT TIME": "a small red rocket taking off", "FASHION ICON": "cool pink sunglasses with sparkles",
 "CERTIFIED SILLY": "a red clown nose with a rubber chicken", "FAN FAVORITE": "a big pink heart with sparkles",
 "NEVER GAVE UP": "a little flag on top of a mountain",
}
def slug(n): return re.sub(r"[^a-z0-9]+", "_", n.lower()).strip("_")
os.makedirs(C.OUT + "/awards", exist_ok=True)
only = sys.argv[1:]
jobs = [(f"awards/{slug(k)}", "z", 768, 768, STYLE.format(v)) for k, v in AW.items() if not only or slug(k) in only]
C.run(jobs, seed_base=777)
