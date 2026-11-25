#!/usr/bin/env python3
"""The Christmas season's pictures (2026-11-25, for p4.22; the user: "4. Go"): the loading
picture, the winner's backdrop, the two new arenas' cards and a winter far backdrop (FLUX.2
klein); the badges for the present, SNOWBALLS, ORNAMENT BOMBS, SNOW FLURRY, BLIZZARD, the
tricks, KRAMPUS and the reindeer, seven awards and a wreath for the lobby title's O (Z-Image
Turbo on magenta, 4 tries each); and the sprites: KRAMPUS, the reindeer, the snowman, the
sleigh and the presents, one seed a try for every pose (so a try is one creature in each pose).
    run_christmas.py [paint] [icons] [sprites]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_lib as C
ART = ("a painted comic book illustration with thick black ink outlines and rich saturated colours, dramatic "
       "cinematic lighting, video game key art, {}, no text, no letters, no logo")
SPLASH = ("two hooded archers in colourful cloaks, one red and one blue, duelling with bows on the snowy stone battlements "
          "of a castle on Christmas Eve at night, arrows flying, a huge full moon, snow falling, a big decorated Christmas "
          "tree with glowing lights and a gold star in the courtyard, strings of coloured lights and green wreaths with red "
          "bows on the battlements, wrapped presents in the snow, one funny reindeer running away between them, warm "
          "lantern light, clear open night sky across the top of the picture")
WINNER = ("the great hall of a castle on Christmas Eve, a huge decorated Christmas tree with glowing lights on the left, "
          "a roaring stone fireplace hung with stockings on the right, green garlands and wreaths with red bows on stone "
          "arches, piles of wrapped presents on both sides, warm candle light, snow falling outside tall windows, an open "
          "empty stone floor in the middle, festive and cosy, no people")
CARDS = {
 "rooftops": "the snowy rooftops of an old town on Christmas Eve at night seen from the side: steep roofs at different "
             "heights, brick chimneys with a little smoke, warm glowing windows, strings of coloured lights hung between "
             "the houses, a huge full moon with the small black silhouette of a sleigh and reindeer flying across it, "
             "snow falling, deep blue night sky, no people",
 "workshop": "the inside of a toy workshop at the north pole cut open like a doll's house: warm wooden beams, shelves "
             "full of teddy bears, drums and wrapped presents, workbenches, a big decorated Christmas tree, a red and "
             "green toy steam train on a track along the floor, red and white candy cane posts, a fireplace with "
             "stockings, frosty windows with snow outside, warm golden light, no people",
}
BACKDROP = ("pixel art, 16-bit video game background, a winter night sky over distant snowy castle towers and rolling white "
            "hills with dark pine trees, a big pale moon behind soft clouds, faint green northern lights, a few stars, deep "
            "navy blue, teal and white, low contrast muted colours, silhouettes only, wide panorama, no foreground, no text")
ICON = ("a single flat vector video game power-up icon of {}, thick black outline, bright saturated colours, "
        "simple bold shapes, glossy highlight, centred, nothing else in the picture, plain flat solid magenta background")   # run_icons.py's
BADGE = ("a single flat vector cartoon award badge icon of {}, thick black outline, bright saturated colours, "
         "simple bold shapes, glossy highlight, cute and funny, centred, nothing else in the picture, plain flat solid magenta background")   # run_awards.py's
ICONS = {
 "present": "a wrapped Christmas present, a red box with a big green ribbon bow on top, sparkles",                   # the PRESENT (the candy's twin)
 "snowball": "a round white snowball flying through the air, small motion lines and a few snowflakes behind it",     # SNOWBALLS
 "ornament": "a shiny red glass Christmas tree ball ornament with a gold cap and a burning fuse like a bomb",        # ORNAMENT BOMBS
 "flurry": "a swirling whirl of white snowflakes and blue wind, a small snow tornado",                               # SNOW FLURRY (BAT SWARM's twin)
 "blizzard": "a dark blue storm cloud with an angry face blowing icy wind and big white snowflakes",                 # BLIZZARD (RAIN's twin)
 "snowman": "a funny cartoon snowman with a carrot nose, coal eyes, stick arms and a red scarf, hopping, small motion lines",   # the tricks
 "brain_freeze": "a dizzy cartoon face with swirly eyes and a block of blue ice on its head, snowflakes and little stars spinning round it",
 "elf": "a tiny cute cartoon elf in a green suit and a pointed green hat with a gold bell, standing next to a huge red Christmas ball that is much bigger than the elf",
 "krampus": "a big fierce cartoon Krampus head, a shaggy dark brown furry monster with two long curved goat horns, angry yellow eyes, sharp white teeth, a long red tongue hanging out and a gold bell on a collar",   # the costume
 "reindeer": "a happy cartoon reindeer head with big brown antlers, a black nose and a red collar hung with gold sleigh bells",   # the reindeer you ride
 "wreath": "a Christmas wreath seen from straight in front, a perfect circle, a thick ring of green pine branches with red berries, small gold balls and a big red bow at the bottom, an empty round hole in the middle",   # the lobby title's O
 "coal": "a lump of shiny black coal with a grumpy little face",                                                     # a present's trick
}
AWARDS = {
 "naughty": "a rolled paper list with a big red X on it and two small red devil horns on top",        # NAUGHTY LIST
 "nice": "a rolled paper list with a big green check mark on it and a gold halo over it",             # NICE LIST
 "snowball_champ": "a gold trophy cup piled full of white snowballs",                                 # SNOWBALL CHAMP
 "lump_of_coal": "a red Christmas stocking with a lump of black coal sticking out of the top",        # LUMP OF COAL
 "sleigh_ride": "a happy cartoon reindeer flying through the air wearing a gold medal",               # SLEIGH RIDE
 "unwrapped": "an open Christmas present box with torn wrapping paper, ribbons flying and a gold star popping out",   # UNWRAPPED
 "fruitcake": "a funny cartoon fruitcake loaf with a sad face, red and green candied fruit dots, one slice cut off, on a plate",   # FRUITCAKE
}
SPRITE = ("a single flat vector cartoon video game character sprite, {}, the whole body in the picture, side view facing "
          "right, thick black outline, bright saturated colours, simple bold shapes, centred, nothing else in the picture, "
          "plain flat solid magenta background")      # run_harvest.py's BIRD
THING = ("a single flat vector cartoon video game object sprite, {}, the whole thing in the picture, thick black outline, "
         "bright saturated colours, simple bold shapes, centred, nothing else in the picture, plain flat solid magenta background")
KRAMPUS = ("a big chunky cartoon Krampus monster covered in shaggy dark brown fur, two long curved goat horns, angry yellow "
           "eyes, sharp white teeth, a long red tongue hanging out, a rusty chain with gold bells across its chest, a brown "
           "sack on its back, hoofed feet, ")
DEER = ("a cute chunky cartoon reindeer with big brown antlers, a black nose, a white fluffy chest and a red harness hung "
        "with gold sleigh bells, ")
SNOWMAN = ("a funny chunky cartoon snowman made of three snowballs, a carrot nose, coal eyes and a coal smile, stick arms "
           "and a red scarf, ")
SPRITES = {      # name: (the prompt's frame, what it is)
 "krampus_stand": (SPRITE, KRAMPUS + "standing tall with its chest out, holding a bundle of birch sticks in one hand"),
 "krampus_swing": (SPRITE, KRAMPUS + "lunging forward and swinging a bundle of birch sticks far out in front of it"),
 "krampus_down": (SPRITE, KRAMPUS + "lying flat on its back, dizzy, its legs in the air, little stars over its head"),
 "deer_trot": (SPRITE, DEER + "trotting happily, its legs in the middle of a step"),
 "deer_fly": (SPRITE, DEER + "flying through the air in a big leap, front legs stretched forward and back legs stretched behind"),
 "snowman_stand": (SPRITE, SNOWMAN + "standing still with a surprised face"),
 "snowman_hop": (SPRITE, SNOWMAN + "hopping up into the air with its stick arms up"),
 "sleigh": (SPRITE, "Santa Claus in his red suit waving from a red and gold sleigh full of wrapped presents, pulled by two "
                    "reindeer in a row in front, flying through the air"),
 "gift_big": (THING, "a huge heavy wrapped Christmas present, a big red box with a wide gold ribbon and a giant gold bow on "
                     "top, seen from straight in front"),
 "gift_open": (THING, "a red Christmas present box bursting open, its lid flying up, gold ribbons and sparkles shooting out, "
                      "seen from straight in front"),
 "gift_chute": (THING, "a small green wrapped Christmas present with a red bow hanging on strings under a little red and "
                       "white striped parachute"),
}
only = sys.argv[1:]
if not only or "paint" in only:
    for d in ("splash", "winner", "cards", "backdrops"):
        os.makedirs(f"{C.OUT}/{d}", exist_ok=True)
    jobs = [(f"splash/christmas_{i}", "k", 1280, 720, ART.format(SPLASH)) for i in range(5)]
    jobs += [(f"winner/christmas_{i}", "k", 1280, 720, ART.format(WINNER)) for i in range(4)]
    jobs += [(f"cards/{k}_{i}", "k", 1024, 576, ART.format(v)) for k, v in CARDS.items() for i in range(4)]
    jobs += [(f"backdrops/winter_k{i}", "k", 1024, 576, BACKDROP) for i in range(3)]
    C.run(jobs, seed_base=12250)
if not only or "icons" in only:
    os.makedirs(C.OUT + "/christmas", exist_ok=True)
    jobs = [(f"christmas/{k}_{i}", "z", 896, 896, ICON.format(v)) for k, v in ICONS.items() for i in range(4)]
    jobs += [(f"christmas/{k}_{i}", "z", 896, 896, BADGE.format(v)) for k, v in AWARDS.items() for i in range(4)]
    C.run(jobs, seed_base=12260)
if not only or "sprites" in only:
    os.makedirs(C.OUT + "/christmas", exist_ok=True)
    for t in range(4):
        for k, (frame, what) in SPRITES.items():   # one call a picture: every pose of try t gets the same seed
            C.run([(f"christmas/{k}_{t}", "z", 896, 896, frame.format(what))], seed_base=12280 + t)
