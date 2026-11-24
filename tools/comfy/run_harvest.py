#!/usr/bin/env python3
"""The Harvest season's pictures (2026-11-24, for Thanksgiving; the user: "Yes, go ahead"): the
loading picture, the winner's backdrop, the two new arenas' cards and an autumn far backdrop
(FLUX.2 klein); the badges for the dish, PIE, POPCORN, CROWS and the tricks, four awards, a pie
for the lobby title's O and a cream splat (Z-Image Turbo on magenta, 4 tries each); and the two
turkeys as small sprites, one seed a try for every pose (so a try is one bird in each pose).
    run_harvest.py [paint] [icons] [birds]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
ART = ("a painted comic book illustration with thick black ink outlines and rich saturated colours, dramatic "
       "cinematic lighting, video game key art, {}, no text, no letters, no logo")
SPLASH = ("two hooded archers in colourful cloaks, one red and one blue, duelling with bows on the stone battlements of a "
          "castle in autumn at golden hour, arrows flying, a huge orange harvest moon rising, trees in red and gold, "
          "leaves falling, pumpkins, corn sheaves and hay bales on the battlements, one funny turkey running away between "
          "them, warm lanterns, clear open sky across the top of the picture")
WINNER = ("a castle terrace set for a harvest feast at dusk, long wooden tables piled with pies, a roast, pumpkins, corn "
          "and apples on both sides, garlands of autumn leaves and orange and gold banners on stone arches, warm lanterns "
          "and candles, leaves falling, a huge harvest moon, an open empty stone floor in the middle, festive and cosy, "
          "no people")
CARDS = {
 "barn": "the inside of a big red wooden barn cut open like a doll's house at harvest sunset: a hay loft, stacked hay "
         "bales, wooden ladders and beams, glowing lanterns, a grain silo beside it, a wagon, pumpkins and corn in the "
         "yard, autumn leaves blowing, a low orange sun, no people",
 "table": "a huge Thanksgiving dinner table seen from the side at a mouse's eye level: a giant golden roast turkey on a "
          "silver platter in the middle, two tall brass candlesticks with lit candles, a pumpkin pie on a cake stand, a "
          "gravy boat, stacked white plates, giant forks and spoons, warm candle light, a cosy dining room blurred "
          "behind, no people",
}
BACKDROP = ("pixel art, 16-bit video game background, an autumn dusk sky over distant castle towers and rolling hills of "
            "orange and red trees, a big pale harvest moon behind soft clouds, a few birds, deep orange, plum and navy "
            "blue, low contrast muted colours, silhouettes only, wide panorama, no foreground, no text")
ICON = ("a single flat vector video game power-up icon of {}, thick black outline, bright saturated colours, "
        "simple bold shapes, glossy highlight, centred, nothing else in the picture, plain flat solid magenta background")   # run_icons.py's
BADGE = ("a single flat vector cartoon award badge icon of {}, thick black outline, bright saturated colours, "
         "simple bold shapes, glossy highlight, cute and funny, centred, nothing else in the picture, plain flat solid magenta background")   # run_awards.py's
ICONS = {
 "dish": "a shiny silver serving dish with a round dome lid on a platter, a little steam and sparkles",        # WHAT'S FOR DINNER? (the candy's twin)
 "pie": "a whipped cream pie flying through the air, cream on top, small motion lines",                         # PIE
 "popcorn": "a golden corn cob bursting into fluffy white popcorn",                                             # POPCORN ARROWS
 "crows": "a black cartoon crow with a yellow beak flapping its wings",                                         # CROWS (BAT SWARM's twin)
 "turkey_time": "a funny cartoon turkey with a fan tail of orange, red and yellow feathers, hopping, small motion lines",   # the tricks
 "too_much_pie": "a dizzy cartoon face with swirly eyes and a slice of pumpkin pie on its head, little stars spinning round it",
 "pea": "one tiny bright green pea with a cute face alone on a big white plate",
 "big_turkey": "a big fierce cartoon turkey head with angry eyebrows, a red wattle and a fan of orange and gold tail feathers behind it",   # the costume
 "pie_top": "a whole pumpkin pie seen from straight above, a perfect circle, a crimped golden crust rim, orange filling, a white swirl of whipped cream in the middle",   # the lobby title's O
 "splat": "a big messy splat of white whipped cream with drips, seen from the front",                           # PIE on your own screen
}
AWARDS = {
 "gobble": "a happy cartoon turkey wearing a gold medal",                                         # GOBBLE GOBBLE
 "pie_face": "a cartoon face covered in whipped cream pie with only two surprised eyes showing",  # PIE FACE
 "stuffed": "a very round full cartoon tummy with a fork and a knife and an empty plate",         # STUFFED
 "leftovers": "an open food box full of arrows and one turkey drumstick",                         # LEFTOVERS
}
BIRD = ("a single flat vector cartoon video game character sprite, {}, the whole body in the picture, side view facing "
        "right, thick black outline, bright saturated colours, simple bold shapes, centred, nothing else in the picture, "
        "plain flat solid magenta background")
SMALL = "a small plump funny turkey with a fan tail of orange, red and yellow feathers, a red wattle and a yellow beak, "
BIG = "a big proud chunky turkey with a huge fan tail of orange, red and gold feathers, a red wattle, angry eyebrows and a yellow beak, "
BIRDS = {
 "turkey_run": SMALL + "running away as fast as it can, legs stretched wide, wings out, scared eyes",
 "turkey_jump": SMALL + "jumping up in fright with its wings flapping and feathers flying off",
 "big_stand": BIG + "standing tall with its chest out",
 "big_peck": BIG + "lunging forward to peck, its neck and beak stretched far out in front",
 "big_down": BIG + "lying flat on its back, dizzy, its legs in the air, little stars over its head",
}
only = sys.argv[1:]
if not only or "paint" in only:
    for d in ("splash", "winner", "cards", "backdrops"):
        os.makedirs(f"{C.OUT}/{d}", exist_ok=True)
    jobs = [(f"splash/harvest_{i}", "k", 1280, 720, ART.format(SPLASH)) for i in range(5)]
    jobs += [(f"winner/harvest_{i}", "k", 1280, 720, ART.format(WINNER)) for i in range(4)]
    jobs += [(f"cards/{k}_{i}", "k", 1024, 576, ART.format(v)) for k, v in CARDS.items() for i in range(4)]
    jobs += [(f"backdrops/autumn_k{i}", "k", 1024, 576, BACKDROP) for i in range(3)]
    C.run(jobs, seed_base=11260)
if not only or "icons" in only:
    os.makedirs(C.OUT + "/harvest", exist_ok=True)
    jobs = [(f"harvest/{k}_{i}", "z", 896, 896, ICON.format(v)) for k, v in ICONS.items() for i in range(4)]
    jobs += [(f"harvest/{k}_{i}", "z", 896, 896, BADGE.format(v)) for k, v in AWARDS.items() for i in range(4)]
    C.run(jobs, seed_base=11270)
if not only or "birds" in only:
    os.makedirs(C.OUT + "/harvest", exist_ok=True)
    for t in range(4):
        for k, v in BIRDS.items():   # one call a picture: every pose of try t gets the same seed
            C.run([(f"harvest/{k}_{t}", "z", 896, 896, BIRD.format(v))], seed_base=11280 + t)
