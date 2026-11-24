#!/usr/bin/env python3
"""THE BIG TABLE's art (bench/sim/level.gd, theme "table"), made here, never by hand.

The fighters are tiny and the arena is a Thanksgiving dinner table seen from the side.
Everything is drawn by this code (no copied art). It reads the map from
bench/sim/level.gd, checks that every block and ledge is where the pictures expect it,
and paints any cell it does not know as plain wood or silver, so a platform is never
invisible. The art is drawn four times too big and shrunk, so its edges are smooth.

    python3 tools/make_table_art.py [--preview DIR]      (needs Pillow and numpy)

writes bench/assets/:
  table_back.png    the dining room, out of focus: a window at dusk, chair backs, a
                    sideboard, soft candle light (960 x 540; the page draws it twice as big)
  table_front.png   the blocks and ledges: the roast on its platter, the two candlesticks,
                    the gravy boat over its plates, the pie on its stand, the lamp, the
                    cutlery, the tablecloth (the floor) and the dark wood frame
--preview DIR: also DIR/table_preview.png (both, darkened and lit about as the page does
it, with stand-in fighters on the spawn spots), DIR/table_preview_phone.png (a phone's
size) and DIR/table_card.png (400 x 225, no fighters: the size of the lobby's arena cards).
The moving parts (flames, steam, the lamp's glow) are client/table_view.gd's.
"""
import math
import os
import random
import re
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVEL = os.path.join(ROOT, "bench", "sim", "level.gd")
OUT = os.path.join(ROOT, "bench", "assets")
W, H = 1920, 1080         # the arena, in screen pixels: every number below is in these
C = 30                    # a map cell
COLS, ROWS = 64, 36
K = 2                     # the front is drawn at K canvas pixels a screen pixel,
SHRINK = 4                # then shrunk by this: 960 x 540

# ---------------------------------------------------------------- where things are (map cells)
# [first col, last col, first row, last row]
ROAST_TOP = (27, 36, 26, 27)
ROAST_BODY = (25, 38, 28, 31)
PLATTER = (23, 40, 32, 33)
CANDLES = [(16, 17, 20, 33, 24), (46, 47, 20, 33, 24)]     # the stick's cols and rows, then its wax tray's row
BOAT_HULL = (6, 11, 21, 22)
BOAT_SPOUT = (4, 5, 21, 21)
BOAT_FOOT = (7, 10, 23, 23)
BOAT_HANDLE = (12, 13, 21)                                 # a ledge: first col, last col, row
PLATES = [(6, 11, 27), (5, 12, 31)]                        # ledges under the gravy boat (a tiered stand)
PIE = (53, 58, 26, 27)
PIE_PLATE = (51, 60, 28)                                   # a ledge
PIE_STEM = (55, 56, 29, 33)
LAMP = (28, 35, 8, 9)
# the cutlery ledges: kind, first col, last col, row, which end the head is at (-1 left, 1 right)
CUTLERY = [
    ("spoon", 20, 26, 10, -1), ("fork", 37, 43, 10, 1),
    ("knife", 9, 14, 14, 1), ("fork", 18, 24, 14, -1), ("spoon", 39, 45, 14, 1), ("knife", 49, 54, 14, -1),
    ("spoon", 2, 8, 18, 1), ("knife", 26, 37, 18, 1), ("fork", 55, 61, 18, -1),
    ("fork", 20, 27, 22, 1), ("spoon", 36, 43, 22, -1), ("fork", 52, 59, 22, -1),
]

# ---------------------------------------------------------------- the palette
CHINA = (250, 247, 240)
CHINA_S = (206, 210, 224)
CHINA_D = (150, 158, 182)
GOLD = (226, 178, 84)
SILVER_H = (250, 252, 255)
SILVER_L = (226, 231, 240)
SILVER = (180, 188, 204)
SILVER_D = (116, 124, 144)
SILVER_K = (58, 64, 84)
BRASS_H = (255, 238, 170)
BRASS_L = (246, 204, 104)
BRASS = (212, 158, 60)
BRASS_D = (146, 98, 36)
BRASS_K = (82, 50, 20)
SKIN_H = (255, 214, 140)
SKIN_L = (240, 166, 78)
SKIN = (204, 116, 44)
SKIN_D = (150, 74, 28)
SKIN_K = (88, 38, 16)
WAX = (246, 236, 212)
WAX_S = (214, 196, 164)
WAX_D = (164, 142, 116)
CRUST_L = (246, 204, 128)
CRUST = (218, 160, 84)
CRUST_D = (160, 102, 46)
CRUST_K = (96, 56, 24)
PUMPKIN = (224, 124, 40)
CREAM = (255, 252, 244)
GRAVY_L = (198, 132, 66)
GRAVY = (150, 88, 38)
GRAVY_D = (98, 54, 22)
CLOTH_H = (255, 255, 255)
CLOTH = (246, 242, 234)
CLOTH_S = (212, 206, 204)
CLOTH_D = (160, 152, 160)
STITCH = (208, 92, 40)
WOOD_L = (150, 100, 62)
WOOD = (108, 68, 44)
WOOD_D = (70, 42, 30)
WOOD_K = (34, 20, 16)
LEAF = (112, 168, 62)
LEAF_D = (62, 112, 44)
BERRY = (206, 34, 52)
SHADE_L = (250, 226, 170)
SHADE = (238, 180, 98)
SHADE_D = (192, 120, 56)


def read_map():
    src = open(LEVEL).read()
    i = src.index('"name": "THE BIG TABLE"')
    j = src.index('"map": [', i)
    k = src.index("]}", j)
    rows = re.findall(r'"([#=.0-9a-h]{64})"', src[j:k])
    assert len(rows) == ROWS, len(rows)
    return rows


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def rgba(c, a=255):
    return (int(round(c[0])), int(round(c[1])), int(round(c[2])), int(round(a)))


# ================================================================ the drawing kit
class Art:
    """The big canvas the front is drawn on."""

    def __init__(self):
        self.img = Image.new("RGBA", (W * K, H * K), (0, 0, 0, 0))

    def tile(self, x0, y0, x1, y1, pad=8):
        return Tile(self, x0 - pad, y0 - pad, x1 + pad, y1 + pad)


class Tile:
    """A piece of the canvas. Shapes are made as masks (white where the shape is), then
    filled with a colour or a blend; commit() puts the piece on the canvas."""

    def __init__(self, art, x0, y0, x1, y1):
        self.art = art
        self.x0 = int(math.floor(x0))
        self.y0 = int(math.floor(y0))
        self.w = (int(math.ceil(x1)) - self.x0) * K
        self.h = (int(math.ceil(y1)) - self.y0) * K
        self.img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))

    def p(self, x, y):
        return ((x - self.x0) * K, (y - self.y0) * K)

    def _new(self):
        m = Image.new("L", (self.w, self.h), 0)
        return m, ImageDraw.Draw(m)

    # ---- shapes
    def rect(self, x0, y0, x1, y1, r=0.0):
        m, d = self._new()
        a = self.p(x0, y0)
        b = self.p(x1, y1)
        box = [a[0], a[1], b[0] - 1, b[1] - 1]
        if box[2] < box[0] or box[3] < box[1]:
            return m
        if r > 0:
            d.rounded_rectangle(box, radius=r * K, fill=255)
        else:
            d.rectangle(box, fill=255)
        return m

    def ell(self, cx, cy, rx, ry):
        m, d = self._new()
        a = self.p(cx - rx, cy - ry)
        b = self.p(cx + rx, cy + ry)
        d.ellipse([a[0], a[1], b[0] - 1, b[1] - 1], fill=255)
        return m

    def poly(self, pts):
        m, d = self._new()
        d.polygon([self.p(*q) for q in pts], fill=255)
        return m

    def line(self, pts, w):
        m, d = self._new()
        q = [self.p(*t) for t in pts]
        d.line(q, fill=255, width=max(1, int(round(w * K))), joint="curve")
        r = w * K / 2.0
        for t in (q[0], q[-1]):
            d.ellipse([t[0] - r, t[1] - r, t[0] + r, t[1] + r], fill=255)
        return m

    def boxes(self, boxes, r=0.0):
        """Map cells: [c0, c1, r0, r1] boxes joined; r rounds the corners that stick out."""
        m, d = self._new()
        for (c0, c1, r0, r1) in boxes:
            a = self.p(c0 * C, r0 * C)
            b = self.p((c1 + 1) * C, (r1 + 1) * C)
            d.rectangle([a[0], a[1], b[0] - 1, b[1] - 1], fill=255)
        return self.rounded(m, r)

    def rounded(self, m, r):
        """Round a mask's outer corners by about r (never adds a pixel)."""
        if r <= 0:
            return m
        b = m.filter(ImageFilter.GaussianBlur(r * K * 0.54)).point(lambda v: 255 if v >= 128 else 0)
        return ImageChops.multiply(b, m)

    # ---- mask sums
    @staticmethod
    def both(a, b):
        return ImageChops.multiply(a, b)

    @staticmethod
    def either(a, b):
        return ImageChops.lighter(a, b)

    @staticmethod
    def less(a, b):
        return ImageChops.subtract(a, b)

    def shift(self, m, dx, dy):
        out = Image.new("L", m.size, 0)
        out.paste(m, (int(round(dx * K)), int(round(dy * K))))
        return out

    def top(self, m, px):
        """The px under every top edge of a mask."""
        return ImageChops.subtract(m, self.shift(m, 0, px))

    def bottom(self, m, px):
        return ImageChops.subtract(m, self.shift(m, 0, -px))

    def left(self, m, px):
        return ImageChops.subtract(m, self.shift(m, px, 0))

    def right(self, m, px):
        return ImageChops.subtract(m, self.shift(m, -px, 0))

    def shrink(self, m, px):
        n = max(1, int(round(px * K)))
        return m.filter(ImageFilter.MinFilter(2 * n + 1))

    def edge(self, m, px):
        """A band px wide just inside a mask's edge."""
        return ImageChops.subtract(m, self.shrink(m, px))

    def soft(self, m, px):
        return m.filter(ImageFilter.GaussianBlur(px * K))

    # ---- paint
    def fill(self, m, c, a=1.0):
        lay = Image.new("RGBA", (self.w, self.h), rgba(c))
        lay.putalpha(m if a >= 1.0 else m.point(lambda v: int(v * a)))
        self.img = Image.alpha_composite(self.img, lay)

    def blend(self, m, stops, down=True, a=1.0):
        """Fill with a blend: stops = [(screen y or x, colour), ...], top to bottom (down) or left to right."""
        n = self.h if down else self.w
        origin = self.y0 if down else self.x0
        pos = origin + (np.arange(n) + 0.5) / K
        xs = [s[0] for s in stops]
        line = np.stack([np.interp(pos, xs, [s[1][i] for s in stops]) for i in range(3)], axis=-1)
        arr = np.broadcast_to(line[:, None, :] if down else line[None, :, :], (self.h, self.w, 3))
        lay = Image.fromarray(np.ascontiguousarray(arr).astype(np.uint8), "RGB").convert("RGBA")
        lay.putalpha(m if a >= 1.0 else m.point(lambda v: int(v * a)))
        self.img = Image.alpha_composite(self.img, lay)

    def commit(self):
        self.art.img.alpha_composite(self.img, (self.x0 * K, self.y0 * K))


def cell_box(b):
    """A [c0, c1, r0, r1] box in screen pixels: x0, y0, x1, y1."""
    return (b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C)


# ================================================================ the front: each thing
def paint_cloth(art, rows, rng):
    """The floor: a white tablecloth. Its top line is bright; where the table has a gap
    the cloth turns down over the edge."""
    for run in solid_runs(rows, 34):
        x0, x1 = run[0] * C, (run[1] + 1) * C
        t = art.tile(x0, 1020, x1, H)
        ex0 = x0 - 30 if x0 == 0 else x0          # a square end at the screen's edge,
        ex1 = x1 + 30 if x1 == W else x1          # a round shoulder at a gap
        body = t.rect(ex0, 1020, ex1, 1064, 9)
        body = t.either(body, t.rect(ex0, 1032, ex1, 1066))
        for x in range(int(x0) + 15, int(x1), 30):   # the scalloped hem along the bottom
            body = t.either(body, t.ell(x, 1065, 15.5, 13))
        t.blend(body, [(1020, CLOTH), (1040, mix(CLOTH, CLOTH_S, 0.35)), (1080, CLOTH_S)])
        x = x0 + rng.uniform(20, 60)
        while x < x1 - 20:                           # soft folds
            fold = t.soft(t.poly([(x, 1024), (x + 7, 1024), (x + 16, 1080), (x - 4, 1080)]), 3)
            t.fill(t.both(fold, body), CLOTH_D, 0.3)
            lit = t.soft(t.poly([(x + 12, 1026), (x + 17, 1026), (x + 30, 1080), (x + 20, 1080)]), 3)
            t.fill(t.both(lit, body), CLOTH_H, 0.5)
            x += rng.uniform(70, 130)
        for end, at_gap in ((x0, x0 != 0), (x1, x1 != W)):   # the cloth turning down into a gap
            if at_gap:
                sh = t.soft(t.rect(end - 7, 1022, end + 7, 1080), 4)
                t.fill(t.both(sh, body), CLOTH_D, 0.55)
        t.fill(t.both(t.rect(x0 - 40, 1047, x1 + 40, 1050), body), STITCH)      # a stitched autumn border
        for x in range(int(x0) + 15, int(x1), 30):
            t.fill(t.both(t.poly([(x, 1053), (x + 5, 1058), (x, 1063), (x - 5, 1058)]), body), mix(STITCH, GOLD, 0.5))
        t.fill(t.both(t.bottom(body, 2.5), t.rect(x0 - 40, 1062, x1 + 40, H)), CLOTH_D, 0.8)
        t.fill(t.top(body, 3), CLOTH_H)                                         # where you stand
        t.fill(t.both(t.shift(t.top(body, 2), 0, 3), body), mix(CLOTH, CLOTH_S, 0.6), 0.7)
        t.commit()


def paint_wood(art, rows):
    """The frame: the beam over the table (the ceiling) and the posts at the sides."""
    for run in solid_runs(rows, 0):
        x0, x1 = run[0] * C, (run[1] + 1) * C
        t = art.tile(x0, 0, x1, 60)
        m = t.rect(x0 - (30 if x0 == 0 else 0), -30, x1 + (30 if x1 == W else 0), 60, 5)
        t.blend(m, [(0, WOOD_D), (40, WOOD), (60, mix(WOOD, WOOD_L, 0.5))])
        for x in range(int(x0) + 90, int(x1), 180):
            t.fill(t.both(t.rect(x, 0, x + 2, 60), m), WOOD_K, 0.45)
        t.fill(t.both(t.rect(x0 - 40, 44, x1 + 40, 46), m), WOOD_K, 0.5)        # a groove
        t.fill(t.bottom(m, 3), WOOD_L)
        t.fill(t.edge(m, 1.5), WOOD_K, 0.8)
        t.commit()
    for side in (0, 1):
        for (r0, r1) in wall_runs(rows, 0 if side == 0 else COLS - 1):
            x0 = 0 if side == 0 else W - 60
            y0, y1 = r0 * C, (r1 + 1) * C
            t = art.tile(x0, y0, x0 + 60, y1)
            m = t.rect(x0 - (30 if side == 0 else 0), y0, x0 + 60 + (30 if side == 1 else 0), y1, 5)
            if side == 0:
                t.blend(m, [(0, WOOD_D), (40, WOOD), (60, mix(WOOD, WOOD_L, 0.35))], down=False)
            else:
                t.blend(m, [(W - 60, mix(WOOD, WOOD_L, 0.35)), (W - 40, WOOD), (W, WOOD_D)], down=False)
            y = y0 + 75
            while y < y1 - 30:                     # turned rings on the post
                t.fill(t.both(t.rect(x0 - 5, y, x0 + 65, y + 16), m), WOOD_D, 0.75)
                t.fill(t.both(t.rect(x0 - 5, y, x0 + 65, y + 3), m), WOOD_L, 0.8)
                t.fill(t.both(t.rect(x0 - 5, y + 16, x0 + 65, y + 18), m), WOOD_K, 0.6)
                y += 150
            inner = t.right(m, 3) if side == 0 else t.left(m, 3)
            t.fill(inner, WOOD_L, 0.9)
            t.fill(t.edge(m, 1.5), WOOD_K, 0.8)
            if r0 > 2:                             # the passage's floor: you can stand here
                t.fill(t.top(m, 3), mix(WOOD_L, BRASS_H, 0.35))
            t.commit()


def oval(cx, cy, rx, ry, ang, n=44):
    """The corner points of a tilted oval."""
    pts = []
    for i in range(n):
        a = math.tau * i / n
        x, y = math.cos(a) * rx, math.sin(a) * ry
        pts.append((cx + x * math.cos(ang) - y * math.sin(ang), cy + x * math.sin(ang) + y * math.cos(ang)))
    return pts


def paint_roast(art, rng):
    """The roast turkey: golden-brown, a shine on top, a drumstick on each side with a
    paper frill on its bone, on a silver platter with garnish."""
    # the platter
    px0, py0, px1, py1 = cell_box(PLATTER)
    t = art.tile(px0, py0 - 6, px1, py1)
    m = t.either(t.rect(px0, py0, px1, py0 + 40, 7), t.rect(px0, py0 + 14, px1, py1, 13))   # the underside curves in
    t.blend(m, [(py0, SILVER_L), (py0 + 12, SILVER), (py0 + 34, SILVER_L), (py1, SILVER_D)])
    for i in range(9):                                         # the room in the silver: soft streaks
        x = px0 + 30 + i * 60 + rng.uniform(-12, 12)
        t.fill(t.both(t.soft(t.rect(x, py0 + 6, x + rng.uniform(6, 16), py1 - 6), 3), m), SILVER_H, 0.6)
    t.fill(t.both(t.rect(px0, py0 + 14, px1, py0 + 16), m), SILVER_D, 0.8)   # the rim's engraved line
    t.fill(t.both(t.rect(px0, py0 + 16, px1, py0 + 17.5), m), SILVER_H, 0.9)
    t.fill(t.both(t.soft(t.bottom(m, 9), 3), m), SILVER_K, 0.4)              # the shade under its belly
    t.fill(t.edge(m, 2), SILVER_K)
    t.fill(t.top(m, 3), SILVER_H)
    bit(t, px0 + 15, py0 - 3.6, 4.6, BERRY, (120, 16, 30))      # a cranberry and a pea that rolled to the rim
    bit(t, px1 - 13, py0 - 3.4, 4.4, LEAF, LEAF_D)
    t.commit()
    # the bird: the breast is the top step, the thighs and drumsticks the two shoulders
    bx0, by0, bx1, by1 = cell_box(ROAST_BODY)
    tx0, ty0, tx1, ty1 = cell_box(ROAST_TOP)
    t = art.tile(bx0 - 16, ty0, bx1 + 16, by1 + 14, pad=16)
    m = t.either(t.rect(tx0, ty0, tx1, ty1 + 30, 17), t.rect(bx0, by0, bx1, by1, 15))
    m = t.both(m, t.boxes([ROAST_TOP, ROAST_BODY]))
    cx = (bx0 + bx1) / 2.0
    t.blend(m, [(ty0, (240, 170, 82)), (ty0 + 60, (216, 132, 54)), (by0 + 60, (190, 104, 40)), (by1, (138, 66, 26))])
    dome = t.ell(cx, by1 - 4, (bx1 - bx0) * 0.44, (by1 - ty0) * 1.04)
    t.fill(t.both(t.soft(t.less(m, dome), 16), m), SKIN_K, 0.72)   # round: its corners fall into shadow
    t.fill(t.both(t.soft(t.less(dome, t.shift(dome, 0, 7)), 5), m), (255, 206, 120), 0.38)   # light along the round back
    for i in range(7):                                         # browned patches on the breast
        x = cx + rng.uniform(-120, 120)
        y = ty0 + rng.uniform(14, 70)
        t.fill(t.both(t.soft(t.ell(x, y, rng.uniform(22, 44), rng.uniform(8, 16)), 7), m), (150, 70, 26), 0.4)
    for i in range(46):                                        # roasted speckles
        x = rng.uniform(bx0 + 10, bx1 - 10)
        y = rng.uniform(ty0 + 10, by1 - 8)
        r = rng.uniform(1.2, 3.0)
        t.fill(t.both(t.ell(x, y, r * 1.5, r), m), SKIN_D if i % 3 else SKIN_K, 0.25)
    # the shine
    t.fill(t.both(t.soft(t.ell(cx - 58, ty0 + 22, 62, 10), 5), m), SKIN_H, 0.95)
    t.fill(t.both(t.soft(t.ell(cx - 80, ty0 + 18, 24, 4.5), 1.5), m), (255, 250, 226), 0.95)
    t.fill(t.both(t.soft(t.ell(cx + 74, ty0 + 30, 36, 6), 4), m), SKIN_H, 0.6)
    # the drumsticks: a fat thigh low on each shoulder, tapering up and out to the bone
    for s in (-1, 1):
        ox = bx0 if s < 0 else bx1                              # the bird's outer side
        mx, my = ox - s * 40, by0 + 72                          # the middle of the meat
        tipx, tipy = ox + s * 9, by0 - 9                        # the bone's end, just past the shoulder's corner
        ux, uy = tipx - mx, tipy - my
        ln = math.hypot(ux, uy)
        ux, uy = ux / ln, uy / ln
        nx, ny = -uy, ux
        ang = math.atan2(ux, -uy)                               # the lean, from straight up
        leg = t.either(t.poly(oval(mx, my, 38, 50, ang)),
                       t.poly([(mx + ux * 20 + nx * 30, my + uy * 20 + ny * 30), (tipx - ux * 16 + nx * 8, tipy - uy * 16 + ny * 8),
                               (tipx - ux * 16 - nx * 8, tipy - uy * 16 - ny * 8), (mx + ux * 20 - nx * 30, my + uy * 20 - ny * 30)]))
        leg = t.both(leg, m)
        seam = t.soft(t.less(t.either(t.shift(leg, -s * 7, 2), t.shift(leg, 0, 6)), leg), 3.5)
        t.fill(t.both(seam, m), SKIN_K, 0.7)                    # the shadow where it lies on the body
        t.blend(leg, [(by0, (246, 180, 90)), (by0 + 70, (206, 120, 46)), (by1, (150, 76, 28))])
        t.fill(t.both(t.soft(t.poly(oval(mx + s * 8 - ux * 4, my - 14, 11, 30, ang)), 6), leg), SKIN_H, 0.7)
        for i in range(8):
            x = mx + rng.uniform(-24, 24)
            y = my + rng.uniform(-30, 40)
            t.fill(t.both(t.ell(x, y, 2.6, 1.8), leg), SKIN_D, 0.3)
        t.fill(t.both(t.edge(leg, 2.2), t.shift(leg, -s * 3, 2)), SKIN_K, 0.55)
        # the paper frill on the bone (small, mostly inside the corner)
        fx, fy = tipx - ux * 9, tipy - uy * 9
        frill = t.poly(oval(fx, fy, 10, 13, ang, 24))
        t.fill(frill, CHINA)
        for k in (-1, 0, 1):
            a0 = (fx + nx * k * 5 - ux * 9, fy + ny * k * 5 - uy * 9)
            a1 = (fx + nx * k * 5 + ux * 9, fy + ny * k * 5 + uy * 9)
            t.fill(t.both(t.line([a0, a1], 1.4), frill), CHINA_D, 0.9)
        t.fill(t.edge(frill, 1.4), CHINA_D)
        t.fill(t.poly(oval(fx - ux * 13, fy - uy * 13, 10, 5, ang, 20)), CHINA_S)      # its cuff
        t.fill(t.edge(t.poly(oval(fx - ux * 13, fy - uy * 13, 10, 5, ang, 20)), 1.2), CHINA_D)
    t.fill(t.edge(m, 2.5), SKIN_K, 0.85)
    t.fill(t.top(m, 3.5), SKIN_H, 0.9)                          # where you stand
    # garnish where the bird meets the platter (inside the blocks)
    gy = by1
    for i in range(24):
        x = bx0 + 12 + i * (bx1 - bx0 - 24) / 23.0 + rng.uniform(-3, 3)
        leaf = t.ell(x, gy + rng.uniform(-2, 3), rng.uniform(9, 13), rng.uniform(6, 9))
        t.fill(leaf, LEAF_D if i % 2 else LEAF)
        t.fill(t.top(leaf, 2), mix(LEAF, (220, 240, 150), 0.5), 0.8)
    for i in range(9):
        x = bx0 + 28 + i * (bx1 - bx0 - 56) / 8.0 + rng.uniform(-6, 6)
        berry = t.ell(x, gy + 3, 4.5, 4.5)
        t.fill(berry, BERRY)
        t.fill(t.ell(x - 1.2, gy + 1.6, 1.5, 1.5), (255, 190, 190))
    t.commit()


def paint_candle(art, spec, rng):
    """A brass candlestick with a white candle in its wax tray. The flame is the page's."""
    c0, c1, r0, r1, tray = spec
    x0, x1 = c0 * C, (c1 + 1) * C
    y0, yt, y1 = r0 * C, tray * C, (r1 + 1) * C
    t = art.tile(x0 - 60, y0 - 8, x1 + 60, y1)
    # the brass stick, a column with turned rings
    stick = t.rect(x0, yt, x1, y1)
    t.blend(stick, [(x0, BRASS_D), (x0 + 14, BRASS_L), (x0 + 24, BRASS_H), (x0 + 38, BRASS), (x1, BRASS_D)], down=False)
    for (ya, hh) in ((yt + 34, 26), (yt + 110, 14), (yt + 150, 14), (y1 - 100, 30), (y1 - 34, 34)):
        ring = t.both(t.rect(x0, ya, x1, ya + hh), stick)
        t.blend(ring, [(x0, BRASS_K), (x0 + 12, BRASS), (x0 + 22, BRASS_L), (x0 + 40, BRASS_D), (x1, BRASS_K)], down=False)
        t.fill(t.top(ring, 2.5), BRASS_H, 0.9)
        t.fill(t.bottom(ring, 2.5), BRASS_K, 0.7)
    t.fill(t.both(t.rect(x0, y1 - 8, x1, y1), stick), BRASS_K, 0.45)
    t.fill(t.edge(stick, 2), BRASS_K, 0.9)
    # the wax tray: a shallow brass dish, wider than the stick
    tx0, tx1 = x0 - 60, x1 + 60
    dish = t.poly([(tx0, yt), (tx1, yt), (tx1, yt + 6), (x1 + 16, yt + 19), (x1 - 4, yt + 27), (x0 + 4, yt + 27),
                   (x0 - 16, yt + 19), (tx0, yt + 6)])
    dish = t.rounded(dish, 3)
    t.blend(dish, [(yt, BRASS_L), (yt + 10, BRASS), (yt + 27, BRASS_D)])
    t.fill(t.both(t.soft(t.rect(x0 + 6, yt, x0 + 22, yt + 30), 3), dish), BRASS_H, 0.7)
    t.fill(t.edge(dish, 2), BRASS_K, 0.9)
    t.fill(t.both(t.top(dish, 3), t.rect(tx0, yt, tx1, yt + 4)), BRASS_H)
    # the candle
    wax = t.rect(x0, y0, x1, yt, 6)
    wax = t.either(wax, t.rect(x0, y0 + 20, x1, yt))
    t.blend(wax, [(x0, WAX_S), (x0 + 16, WAX), (x0 + 30, WAX), (x1 - 8, WAX_S), (x1, WAX_D)], down=False)
    t.blend(t.both(t.rect(x0, yt - 30, x1, yt), wax), [(yt - 30, WAX), (yt, mix(WAX, BRASS_L, 0.5))], a=0.35)
    for (dx, ln, w) in ((9, rng.uniform(34, 60), 9), (40, rng.uniform(50, 86), 10), (53, rng.uniform(20, 34), 7), (25, rng.uniform(14, 24), 8)):
        drip = t.both(t.rect(x0 + dx - w / 2.0, y0 - 6, x0 + dx + w / 2.0, y0 + ln, w / 2.0), t.rect(x0, y0, x1, yt + 12))
        t.fill(t.both(t.shift(drip, 2.5, 2), t.either(wax, dish)), WAX_D, 0.6)
        t.fill(drip, WAX)
        t.fill(t.left(drip, 2), CLOTH_H)
    pool = t.both(t.rect(x0, y0, x1, y0 + 7), wax)             # the melted top
    t.fill(pool, mix(WAX, BRASS_H, 0.35))
    t.fill(t.edge(wax, 1.8), WAX_D, 0.9)
    t.fill(t.top(wax, 3), CLOTH_H)
    t.fill(t.rect((x0 + x1) / 2.0 - 1.5, y0 - 7, (x0 + x1) / 2.0 + 1.5, y0 + 1), (40, 28, 24))   # the wick
    t.commit()


def bit(t, x, y, r, c, dark):
    """A pea, a cranberry: a small ball with a dark edge and a glint."""
    m = t.ell(x, y, r, r)
    t.fill(m, c)
    t.fill(t.edge(m, 1.1), dark, 0.9)
    t.fill(t.ell(x - r * 0.3, y - r * 0.35, r * 0.3, r * 0.3), mix(c, (255, 255, 255), 0.6))


def paint_plate(t, x0, x1, y, deep=15.0, rim=GOLD):
    """A china plate seen from the side: a flat top, a curved underside, a foot ring."""
    w = x1 - x0
    cx = (x0 + x1) / 2.0
    m = t.poly([(x0, y), (x1, y), (x1, y + 4), (x1 - 12, y + 9), (cx + w * 0.26, y + deep), (cx + w * 0.2, y + deep),
                (cx + w * 0.18, y + deep + 6), (cx - w * 0.18, y + deep + 6), (cx - w * 0.2, y + deep), (cx - w * 0.26, y + deep),
                (x0 + 12, y + 9), (x0, y + 4)])
    m = t.rounded(m, 2.5)
    t.blend(m, [(y, CHINA), (y + 6, CHINA), (y + deep + 6, CHINA_S)])
    t.fill(t.both(t.rect(x0, y + 4.5, x1, y + 6.5), m), rim, 0.95)
    t.fill(t.both(t.soft(t.rect(cx - w * 0.3, y + 8, cx - w * 0.1, y + 12), 2), m), CLOTH_H, 0.9)
    t.fill(t.edge(m, 1.6), CHINA_D)
    t.fill(t.both(t.top(m, 3), t.rect(x0, y, x1, y + 3.5)), CLOTH_H)
    return m


def paint_boat(art, rng):
    """The silver gravy boat on its tiered stand: two plates on a thin brass rod, the boat
    on top, full to the brim, a long spout at one end and an ear for a handle at the other."""
    hx0, hy0, hx1, hy1 = cell_box(BOAT_HULL)
    fx0, fy0, fx1, fy1 = cell_box(BOAT_FOOT)
    sx0 = BOAT_SPOUT[0] * C
    ax0, ax1, ay = BOAT_HANDLE[0] * C, (BOAT_HANDLE[1] + 1) * C, BOAT_HANDLE[2] * C
    t = art.tile(sx0 - 6, hy0 - 6, max(ax1, (PLATES[-1][1] + 1) * C) + 6, 1020)
    # the rod (thin: not a wall) and the plates
    rod_x = (fx0 + fx1) / 2.0
    rod = t.rect(rod_x - 3.5, fy1 - 4, rod_x + 3.5, 1020)
    t.blend(rod, [(rod_x - 3.5, BRASS_D), (rod_x - 1, BRASS_L), (rod_x + 3.5, BRASS_K)], down=False)
    base = t.poly([(rod_x - 16, 1020), (rod_x - 5, 1010), (rod_x + 5, 1010), (rod_x + 16, 1020)])
    t.blend(base, [(1008, BRASS_L), (1020, BRASS_D)])
    for (c0, c1, r) in PLATES:
        paint_plate(t, c0 * C, (c1 + 1) * C, r * C)
        t.fill(t.rect(rod_x - 6, r * C - 0.5, rod_x + 6, r * C + 3, 1.5), BRASS)
    c0, c1, r = PLATES[-1]                                     # three peas left on the low plate
    for (dx, rr) in ((22, 4.6), (33, 4.2), (47, 4.8)):
        bit(t, (c1 + 1) * C - dx, r * C - rr + 1.0, rr, LEAF, LEAF_D)
    # the handle: an ear; its flat top is the ledge
    ear = t.either(t.rect(ax0 - 8, ay, ax1, ay + 11, 4), t.rect(ax1 - 11, ay, ax1, ay + 34, 5))
    ear = t.either(ear, t.rect(ax0 - 8, ay, ax1 - 6, ay + 11))
    ear = t.either(ear, t.line([(ax1 - 5.5, ay + 30), (ax1 - 16, ay + 46), (ax0 - 6, ay + 53)], 10))
    t.blend(ear, [(ay, SILVER_L), (ay + 30, SILVER), (ay + 56, SILVER_D)])
    t.fill(t.both(t.shift(t.top(ear, 2.5), 0, 4), ear), SILVER_H, 0.7)
    t.fill(t.edge(ear, 1.8), SILVER_K)
    t.fill(t.both(t.top(ear, 3), t.rect(ax0 - 8, ay, ax1, ay + 3.5)), SILVER_H)
    # the boat
    hull = t.either(t.rect(hx0, hy0, hx1, hy1, 24), t.rect(hx0, hy0, hx1, hy0 + 26))
    foot = t.either(t.rect(fx0, fy0 - 4, fx1, fy1, 5), t.rect(fx0, fy0 - 4, fx1, fy0 + 10))
    spout = t.rounded(t.poly([(sx0, hy0), (hx0 + 4, hy0), (hx0 + 4, hy0 + 31), (sx0 + 26, hy0 + 25), (sx0 + 2, hy0 + 17)]), 4)
    m = t.either(t.either(hull, foot), spout)
    t.blend(m, [(hy0, SILVER_L), (hy0 + 22, SILVER), (hy0 + 46, SILVER_L), (fy0, SILVER_D), (fy1 - 12, SILVER), (fy1, SILVER_D)])
    for (x, wd) in ((hx0 + 22, 14), (hx0 + 70, 8), (hx0 + 118, 18), (hx0 + 150, 6)):          # the room in the silver
        t.fill(t.both(t.soft(t.rect(x, hy0 + 14, x + wd, hy1 - 8), 3.5), hull), SILVER_H, 0.75)
    t.fill(t.both(t.soft(t.ell(hx0 + 44, hy0 + 28, 30, 8), 3), m), CLOTH_H, 0.95)
    t.fill(t.both(t.soft(t.right(hull, 12), 5), m), SILVER_D, 0.6)
    t.fill(t.both(t.soft(t.rect(fx0 - 10, fy0 - 5, fx1 + 10, fy0 + 5), 3), m), SILVER_K, 0.45)   # the waist over the foot
    t.fill(t.both(t.rect(fx0, fy1 - 12, fx1, fy1 - 10), m), SILVER_K, 0.5)
    gravy = t.both(t.rect(sx0, hy0, hx1, hy0 + 9), m)                                # the gravy, to the brim
    t.blend(gravy, [(hy0, GRAVY_L), (hy0 + 9, GRAVY)])
    t.fill(t.both(t.rect(sx0, hy0 + 9, hx1, hy0 + 11.5), m), SILVER_H)                # the rim under it
    t.fill(t.both(t.rect(sx0, hy0 + 11.5, hx1, hy0 + 13), m), SILVER_D, 0.8)
    t.fill(t.edge(m, 2), SILVER_K)
    t.fill(t.both(t.edge(m, 2), t.rect(sx0, hy0, hx1, hy0 + 9)), GRAVY_D)
    t.fill(t.both(t.top(m, 3), t.rect(sx0, hy0, hx1, hy0 + 4)), mix(GRAVY_L, (255, 232, 176), 0.6))   # where you stand
    drip = t.either(t.rect(sx0 + 3, hy0 + 4, sx0 + 10, hy0 + 30, 3.5), t.ell(sx0 + 6.5, hy0 + 31, 5, 6.5))   # a drip off the spout
    t.fill(drip, GRAVY)
    t.fill(t.ell(sx0 + 5, hy0 + 29, 1.5, 2.4), GRAVY_L)
    t.commit()


def paint_pie(art, rng):
    """The pie on its cake stand: a crimped crust, pumpkin filling, a small cream dollop."""
    sx0, sy0, sx1, sy1 = cell_box(PIE_STEM)
    px0, py0, px1, py1 = cell_box(PIE)
    lx0, lx1, ly = PIE_PLATE[0] * C, (PIE_PLATE[1] + 1) * C, PIE_PLATE[2] * C
    t = art.tile(lx0, py0 - 14, lx1, sy1)
    # the stand's stem: white china, a column with a waist and a foot
    stem = t.rect(sx0, sy0, sx1, sy1)
    t.blend(stem, [(sx0, CHINA_S), (sx0 + 16, CHINA), (sx0 + 30, CHINA), (sx1 - 10, CHINA_S), (sx1, CHINA_D)], down=False)
    for (ya, hh) in ((sy0 + 22, 12), (sy0 + 74, 10), (sy1 - 34, 34)):
        ring = t.both(t.rect(sx0, ya, sx1, ya + hh), stem)
        t.fill(t.top(ring, 2.5), CLOTH_H)
        t.fill(t.bottom(ring, 2.5), CHINA_D, 0.9)
    t.fill(t.both(t.rect(sx0, sy1 - 20, sx1, sy1 - 17), stem), GOLD)
    t.fill(t.both(t.soft(t.rect(sx0, sy0, sx1, sy0 + 16), 5), stem), CHINA_D, 0.6)     # the plate's shadow
    t.fill(t.edge(stem, 2), CHINA_D)
    # the stand's plate (a ledge), with a few crumbs
    paint_plate(t, lx0, lx1, ly, deep=13.0)
    for (x, w) in ((lx0 + 16, 5), (lx0 + 27, 3.5), (lx0 + 38, 4.5), (lx1 - 19, 4.5), (lx1 - 31, 3.5)):
        crumb = t.poly([(x - w, ly), (x - w * 0.4, ly - w), (x + w * 0.7, ly - w * 0.8), (x + w, ly)])
        t.fill(crumb, CRUST)
        t.fill(t.top(crumb, 1.2), CRUST_L)
    # the pie
    m = t.rect(px0, py0, px1, py1)
    m = t.both(m, t.either(t.rect(px0, py0, px1, py0 + 30), t.poly([(px0, py0), (px1, py0), (px1 - 9, py1 + 1), (px0 + 9, py1 + 1)])))
    m = t.either(m, t.rect(px0 + 8, py1 - 8, px1 - 8, py1))
    t.blend(m, [(py0, CRUST_L), (py0 + 22, CRUST), (py1, CRUST_D)])
    for i in range(13):                                         # the fluted side
        x = px0 + 10 + i * (px1 - px0 - 20) / 12.0
        t.fill(t.both(t.poly([(x - 1.5, py0 + 20), (x + 1.5, py0 + 20), (x + 1.5 + (x - (px0 + px1) / 2) * -0.07, py1), (x - 1.5 + (x - (px0 + px1) / 2) * -0.07, py1)]), m), CRUST_D, 0.6)
    fill = t.both(t.rect(px0 + 16, py0, px1 - 16, py0 + 9), m)  # the pumpkin filling shows between the crimps
    t.blend(fill, [(py0, mix(PUMPKIN, (255, 190, 90), 0.4)), (py0 + 9, PUMPKIN)])
    n = 9
    for i in range(n):                                          # the crimped edge: a row of bumps under the top line
        x = px0 + 10 + i * (px1 - px0 - 20) / (n - 1.0)
        bump = t.both(t.ell(x, py0 + 12, 11, 10), m)
        t.fill(bump, CRUST_L if i % 2 == 0 else CRUST)
        t.fill(t.both(t.bottom(bump, 2.5), m), CRUST_D, 0.9)
    t.fill(t.edge(m, 2), CRUST_K, 0.85)
    t.fill(t.both(t.top(m, 3), t.rect(px0, py0, px1, py0 + 4)), mix(CRUST_L, CLOTH_H, 0.55))   # where you stand
    # a small dollop of cream in the middle (low: it hides nothing)
    cx = (px0 + px1) / 2.0
    dol = t.either(t.ell(cx, py0 - 1, 15, 7), t.ell(cx + 1, py0 - 6, 8, 5))
    dol = t.either(dol, t.poly([(cx - 2, py0 - 9), (cx + 4, py0 - 14), (cx + 5, py0 - 8)]))
    t.fill(dol, CREAM)
    t.fill(t.both(t.bottom(dol, 2), t.rect(cx - 20, py0 - 6, cx + 20, py0 + 8)), CHINA_S)
    t.fill(t.edge(dol, 1.2), CHINA_D, 0.8)
    t.commit()


def paint_lamp(art):
    """The lamp over the table: a warm shade with brass bands, on a cord from the beam."""
    x0, y0, x1, y1 = cell_box(LAMP)
    cx = (x0 + x1) / 2.0
    t = art.tile(x0 - 20, 56, x1 + 20, y1 + 26)
    cord = t.rect(cx - 2, 58, cx + 2, y0)
    t.fill(cord, BRASS_K)
    t.fill(t.left(cord, 1.2), BRASS_D)
    cap = t.poly([(cx - 22, 58), (cx + 22, 58), (cx + 12, 72), (cx - 12, 72)])
    t.blend(cap, [(58, BRASS_D), (72, BRASS)])
    hub = t.poly([(cx - 14, y0), (cx - 8, y0 - 12), (cx + 8, y0 - 12), (cx + 14, y0)])
    t.blend(hub, [(y0 - 12, BRASS_L), (y0, BRASS_D)])
    bulb = t.ell(cx, y1 + 2, 15, 13)                            # the bulb peeks out under the shade
    t.fill(t.soft(t.ell(cx, y1 + 4, 34, 20), 8), (255, 220, 140), 0.55)
    t.fill(bulb, (255, 246, 210))
    m = t.rect(x0, y0, x1, y1, 7)
    m = t.either(m, t.rect(x0, y0 + 20, x1, y1))
    t.blend(m, [(y0, SHADE_D), (y0 + 16, SHADE), (y1 - 8, SHADE_L), (y1, SHADE)])
    glow = t.soft(t.ell(cx, y1 - 6, (x1 - x0) * 0.36, 26), 10)
    t.fill(t.both(glow, m), (255, 246, 206), 0.6)               # lit from inside
    for i in range(1, 12):                                      # pleats
        x = x0 + i * (x1 - x0) / 12.0
        t.fill(t.both(t.rect(x - 1, y0 + 8, x + 1, y1 - 8), m), SHADE_D, 0.35)
    for (ya, yb) in ((y0, y0 + 8), (y1 - 8, y1)):
        band = t.both(t.rect(x0, ya, x1, yb), m)
        t.blend(band, [(x0, BRASS_D), (x0 + 60, BRASS_L), (cx, BRASS_H), (x1 - 60, BRASS), (x1, BRASS_D)], down=False)
        t.fill(t.bottom(band, 1.5), BRASS_K, 0.6)
    t.fill(t.edge(m, 2), BRASS_K, 0.9)
    t.fill(t.top(m, 3), BRASS_H)                                # where you stand
    t.commit()


def silver(t, m, y, deep):
    """Fill a piece of cutlery: silver, a dark edge, a bright top line."""
    t.blend(m, [(y, SILVER_L), (y + deep * 0.45, SILVER), (y + deep, SILVER_D)])
    t.fill(t.both(t.shift(t.top(m, 2.5), 0, 4), m), SILVER_H, 0.75)
    t.fill(t.edge(m, 1.8), SILVER_K)
    t.fill(t.both(t.top(m, 3), t.rect(-100, y, W + 100, y + 3.5)), SILVER_H)


def paint_cutlery(art, kind, c0, c1, row, head):
    """A fork, a knife or a spoon lying flat, its top edge the ledge. head: the end with
    the tines, the tip or the bowl (-1 left, 1 right)."""
    x0, x1, y = c0 * C, (c1 + 1) * C, row * C
    t = art.tile(x0, y, x1, y + 34)
    w = x1 - x0

    def fx(u):                 # u runs from the handle's end (0) to the head's end (w)
        return x0 + u if head > 0 else x1 - u

    def span(u0, u1, ya, yb, r=0.0):
        a, b = fx(u0), fx(u1)
        return t.rect(min(a, b), y + ya, max(a, b), y + yb, r)

    if kind == "spoon":
        bowl_w = min(74.0, w * 0.4)
        m = span(0, w - bowl_w + 10, 0, 12, 6)
        m = t.either(m, span(7, w - bowl_w + 10, 0, 12))
        m = t.either(m, t.poly([(fx(w - bowl_w - 26), y), (fx(w - bowl_w + 8), y), (fx(w - bowl_w + 8), y + 17), (fx(w - bowl_w - 26), y + 10)]))
        bx = fx(w - bowl_w / 2.0)
        bowl = t.both(t.ell(bx, y + 1, bowl_w / 2.0, 27), t.rect(x0 - 5, y, x1 + 5, y + 40))
        m = t.either(m, bowl)
        silver(t, m, y, 27)
        hollow = t.both(t.ell(bx, y + 4, bowl_w / 2.0 - 8, 16), t.rect(x0, y + 5, x1, y + 40))
        t.blend(hollow, [(y + 5, SILVER_D), (y + 20, SILVER_L)], a=0.85)
        t.fill(t.both(t.soft(t.ell(bx - head * 8, y + 13, 9, 3.5), 1.5), hollow), SILVER_H, 0.95)
    elif kind == "fork":
        head_w = min(84.0, w * 0.42)
        root = 30.0
        m = span(0, w - head_w + 6, 0, 12, 6)
        m = t.either(m, span(7, w - head_w + 6, 0, 12))
        m = t.either(m, t.poly([(fx(w - head_w - 24), y), (fx(w - head_w + 4), y), (fx(w - head_w + 4), y + 22), (fx(w - head_w - 24), y + 10)]))
        m = t.either(m, span(w - head_w, w - head_w + root, 0, 27, 6))
        m = t.either(m, span(w - head_w, w - head_w + root - 8, 0, 20))
        for i in range(3):                                      # the tines
            ya = i * 10.5
            tine = span(w - head_w + root - 8, w, ya, ya + 6, 3)
            tine = t.either(tine, span(w - head_w + root - 8, w - 6, ya, ya + 6))
            m = t.either(m, tine)
        silver(t, m, y, 27)
        for i in range(2):                                      # the dark between the tines' roots
            ya = 6 + i * 10.5
            t.fill(t.both(span(w - head_w + root - 9, w - head_w + root - 5, ya - 1, ya + 5.5), m), SILVER_K, 0.5)
    else:  # a knife: a dark wood handle with brass pins, a blade with its back up
        hw = min(120.0, w * 0.36)
        handle = span(0, hw, 0, 15, 7)
        handle = t.either(handle, span(8, hw, 0, 15))
        blade = t.poly([(fx(hw), y), (fx(w), y), (fx(w - 5), y + 5), (fx(w - 26), y + 14), (fx(w - 70), y + 20), (fx(hw + 10), y + 21),
                        (fx(hw), y + 16)])
        blade = t.rounded(blade, 2)
        silver(t, blade, y, 21)
        t.fill(t.both(t.shift(t.bottom(blade, 2), 0, -3.5), blade), SILVER_H, 0.9)   # the ground edge
        t.blend(handle, [(y, WOOD_L), (y + 7, WOOD), (y + 15, WOOD_D)])
        for u in (hw * 0.3, hw * 0.7):
            t.fill(t.ell(fx(u), y + 8, 2.6, 2.6), BRASS_L)
        bol = span(hw - 5, hw + 5, 0, 17, 2)
        t.blend(bol, [(y, BRASS_H), (y + 17, BRASS_D)])
        t.fill(t.edge(bol, 1.2), BRASS_K, 0.8)
        t.fill(t.edge(handle, 1.8), WOOD_K)
        t.fill(t.both(t.top(handle, 3), t.rect(x0, y, x1, y + 3.5)), mix(WOOD_L, BRASS_H, 0.6))
    t.commit()


def paint_spare(art, rows, claimed):
    """Any block or ledge the pictures above do not cover: plain wood, plain silver."""
    spare = 0
    for r in range(ROWS):
        for c in range(COLS):
            if (c, r) in claimed or rows[r][c] not in "#=":
                continue
            spare += 1
            t = art.tile(c * C, r * C, (c + 1) * C, (r + 1) * C, pad=2)
            if rows[r][c] == "#":
                m = t.rect(c * C, r * C, (c + 1) * C, (r + 1) * C)
                t.blend(m, [(r * C, WOOD_L), ((r + 1) * C, WOOD)])
                if rows[r - 1][c] != "#":
                    t.fill(t.top(m, 3), BRASS_H)
            else:
                m = t.rect(c * C, r * C, (c + 1) * C, r * C + 12)
                t.blend(m, [(r * C, SILVER_L), (r * C + 12, SILVER_D)])
                t.fill(t.top(m, 3), SILVER_H)
            t.commit()
    return spare


# ---------------------------------------------------------------- the map's runs, and the check
def solid_runs(rows, r):
    """Runs of block along row r: [first col, last col]."""
    out, start = [], -1
    for c in range(COLS + 1):
        s = c < COLS and rows[r][c] == "#"
        if s and start < 0:
            start = c
        elif not s and start >= 0:
            out.append((start, c - 1))
            start = -1
    return out


def wall_runs(rows, c):
    """Runs of block down column c between the ceiling and the floor: [first row, last row]."""
    out, start = [], -1
    for r in range(2, 35):
        s = r < 34 and rows[r][c] == "#"
        if s and start < 0:
            start = r
        elif not s and start >= 0:
            out.append((start, r - 1))
            start = -1
    return out


def claim(rows, claimed, box, ch, what):
    for r in range(box[2], box[3] + 1):
        for c in range(box[0], box[1] + 1):
            if rows[r][c] != ch:
                sys.exit("make_table_art: %s expects '%s' at col %d row %d, the map has '%s': update the boxes at the top" % (what, ch, c, r, rows[r][c]))
            claimed.add((c, r))


def check(front, rows):
    """The picture against the map: every block cell covered, every ledge's top there,
    the air (nearly) clear. Returns the cells that are off. (A block may lose a little at a
    round corner, the spout tapers, and small things may reach into the air: the lamp's
    bulb, the handle's ear, the cream.)"""
    a = np.array(front)[..., 3].astype(np.float32) / 255.0
    s = C // (SHRINK // K)          # a cell in the shrunk picture
    thin = set((c, r) for c in range(BOAT_SPOUT[0], BOAT_SPOUT[1] + 1) for r in range(BOAT_SPOUT[2], BOAT_SPOUT[3] + 1))
    bad = []
    for r in range(ROWS):
        for c in range(COLS):
            cell = a[r * s:(r + 1) * s, c * s:(c + 1) * s]
            ch = rows[r][c]
            if ch == "#" and cell.mean() < (0.6 if (c, r) in thin else 0.75):
                bad.append((c, r, "block %.0f%% covered" % (cell.mean() * 100)))
            elif ch == "#" and r > 0 and rows[r - 1][c] != "#" and cell[0:2, :].mean() < 0.6:
                bad.append((c, r, "block top %.0f%% covered" % (cell[0:2, :].mean() * 100)))
            elif ch == "=" and cell[0:2, :].mean() < 0.85:
                bad.append((c, r, "ledge top %.0f%% covered" % (cell[0:2, :].mean() * 100)))
            elif ch not in "#=" and cell.mean() > 0.45:
                bad.append((c, r, "air %.0f%% covered" % (cell.mean() * 100)))
    return bad


def make_front(rows, rng):
    art = Art()
    claimed = set()
    for r in (0, 1, 34, 35):
        for c in range(COLS):
            if rows[r][c] == "#":
                claimed.add((c, r))
    for c in (0, 1, COLS - 2, COLS - 1):
        for r in range(2, 34):
            if rows[r][c] == "#":
                claimed.add((c, r))
    for (box, what) in ((ROAST_TOP, "the roast"), (ROAST_BODY, "the roast"), (PLATTER, "the platter"), (BOAT_HULL, "the gravy boat"),
                        (BOAT_SPOUT, "the gravy boat's spout"), (BOAT_FOOT, "the gravy boat's foot"), (PIE, "the pie"),
                        (PIE_STEM, "the pie stand"), (LAMP, "the lamp")):
        claim(rows, claimed, box, "#", what)
    for (c0, c1, r0, r1, tray) in CANDLES:
        claim(rows, claimed, (c0, c1, r0, r1), "#", "a candlestick")
        claim(rows, claimed, (c0 - 2, c0 - 1, tray, tray), "=", "a wax tray")
        claim(rows, claimed, (c1 + 1, c1 + 2, tray, tray), "=", "a wax tray")
    for (c0, c1, r) in PLATES + [PIE_PLATE, BOAT_HANDLE]:
        claim(rows, claimed, (c0, c1, r, r), "=", "a plate or the handle")
    for (kind, c0, c1, r, head) in CUTLERY:
        claim(rows, claimed, (c0, c1, r, r), "=", "a " + kind)
    paint_wood(art, rows)
    paint_cloth(art, rows, rng)
    paint_lamp(art)
    for (kind, c0, c1, r, head) in CUTLERY:
        paint_cutlery(art, kind, c0, c1, r, head)
    paint_boat(art, rng)
    paint_pie(art, rng)
    for spec in CANDLES:
        paint_candle(art, spec, rng)
    paint_roast(art, rng)
    spare = paint_spare(art, rows, claimed)
    if spare:
        print("make_table_art: %d cells of the map have no picture of their own (painted plain)" % spare)
    front = art.img.resize((W * K // SHRINK, H * K // SHRINK), Image.LANCZOS)
    return front


# ================================================================ the room behind, out of focus
def vblend(w, h, stops):
    ys = np.arange(h) + 0.5
    line = np.stack([np.interp(ys, [s[0] for s in stops], [s[1][i] for s in stops]) for i in range(3)], axis=-1)
    return Image.fromarray(np.ascontiguousarray(np.broadcast_to(line[:, None, :], (h, w, 3))).astype(np.uint8), "RGB")


def glow_at(img, x, y, rx, ry, c, a):
    """Add a soft round light to an RGB picture."""
    arr = np.array(img).astype(np.float32)
    yy, xx = np.mgrid[0:img.size[1], 0:img.size[0]].astype(np.float32)
    d = np.sqrt(((xx - x) / rx) ** 2 + ((yy - y) / ry) ** 2)
    k = np.clip(1.0 - d, 0.0, 1.0) ** 2 * a
    arr += k[..., None] * np.array(c, np.float32)[None, None, :]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def make_back(rows, rng):
    # the wall: deep blue-green, so the warm things in front stand out
    img = vblend(W, H, [(0, (26, 40, 50)), (560, (40, 58, 62)), (700, (46, 60, 60)), (H, (38, 44, 44))])
    d = ImageDraw.Draw(img)
    for row in range(0, 24):                                   # a faint wallpaper pattern
        for col in range(0, 34):
            x = col * 60 + (30 if row % 2 else 0)
            y = 40 + row * 28
            d.polygon([(x, y - 9), (x + 6, y), (x, y + 9), (x - 6, y)], fill=(52, 74, 76))
    # the wainscot under a rail
    d.rectangle([0, 706, W, H], fill=(52, 36, 30))
    d.rectangle([0, 694, W, 712], fill=(84, 58, 42))
    for x in range(40, W, 230):
        d.rectangle([x, 744, x + 180, 1000], outline=(72, 50, 38), width=6)
    # the window: dusk outside, bare trees, the first stars
    wx0, wy0, wx1, wy1 = 170, 84, 610, 520
    sky = vblend(wx1 - wx0, wy1 - wy0, [(0, (26, 34, 84)), (150, (62, 48, 106)), (270, (128, 70, 92)), (360, (184, 100, 66)),
                                         (wy1 - wy0, (204, 146, 92))])
    img.paste(sky, (wx0, wy0))
    for i in range(22):
        x = rng.uniform(wx0 + 10, wx1 - 10)
        y = rng.uniform(wy0 + 8, wy0 + 170)
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(230, 226, 255))
    d.ellipse([500, 126, 548, 174], fill=(244, 236, 214))      # a thin moon
    d.ellipse([486, 118, 534, 166], fill=(40, 46, 104))
    hill = [(wx0, wy1)]
    for i in range(0, 12):
        hill.append((wx0 + i * (wx1 - wx0) / 11.0, wy1 - 46 - 26 * math.sin(i * 0.9) - 10 * math.sin(i * 2.3)))
    hill.append((wx1, wy1))
    d.polygon(hill, fill=(38, 30, 50))
    for (tx, th) in ((250, 190), (430, 150), (560, 120)):       # bare trees
        d.line([(tx, wy1 - 30), (tx + 4, wy1 - th)], fill=(30, 24, 40), width=12)
        for k in range(7):
            ang = -math.pi / 2 + (k - 3) * 0.36
            ln = th * (0.3 + 0.1 * (k % 3))
            by = wy1 - th * (0.45 + 0.08 * k)
            d.line([(tx + 3, by), (tx + 3 + math.cos(ang) * ln, by + math.sin(ang) * ln)], fill=(30, 24, 40), width=6)
    frame = (150, 138, 118)
    d.rectangle([wx0 - 22, wy0 - 22, wx1 + 22, wy1 + 22], outline=frame, width=22)
    d.rectangle([(wx0 + wx1) // 2 - 7, wy0, (wx0 + wx1) // 2 + 7, wy1], fill=frame)
    d.rectangle([wx0, wy0 + 190, wx1, wy0 + 204], fill=frame)
    d.rectangle([wx0 - 44, wy1 + 20, wx1 + 44, wy1 + 46], fill=(170, 156, 132))
    for (cx0, cx1) in ((70, 210), (570, 710)):                  # the curtains
        d.rectangle([cx0, 60, cx1, 610], fill=(104, 30, 40))
        for k in range(6):
            x = cx0 + 8 + k * (cx1 - cx0) / 6.0
            d.rectangle([x, 60, x + 9, 610], fill=(70, 18, 28))
            d.rectangle([x + 12, 60, x + 16, 610], fill=(136, 48, 54))
    d.rectangle([50, 54, 730, 66], fill=(150, 108, 48))
    # a painting with its own little light, and the sideboard under it
    d.rectangle([1300, 150, 1700, 440], fill=(120, 92, 50))
    land = vblend(352, 242, [(0, (104, 106, 96)), (110, (132, 106, 74)), (150, (88, 62, 34)), (242, (52, 44, 28))])
    img.paste(land, (1324, 174))
    for i in range(9):
        x = 1350 + i * 38
        d.ellipse([x - 26, 268 - (i % 3) * 14, x + 26, 330], fill=[(120, 52, 24), (140, 88, 30), (100, 38, 24)][i % 3])
    d.rectangle([1440, 118, 1560, 132], fill=(170, 124, 54))
    d.rectangle([1180, 640, W, H], fill=(46, 30, 26))
    d.rectangle([1160, 622, W, 650], fill=(88, 58, 40))
    for x in range(1210, W, 220):
        d.rectangle([x, 690, x + 180, 990], outline=(70, 46, 34), width=7)
        d.ellipse([x + 150, 830, x + 166, 846], fill=(170, 124, 54))
    # on the sideboard: a covered dish, a stack of plates, a vase of autumn branches, two candles
    d.pieslice([1560, 520, 1760, 720], 180, 360, fill=(120, 128, 140))
    d.rectangle([1540, 612, 1780, 626], fill=(150, 156, 168))
    d.ellipse([1648, 500, 1672, 524], fill=(150, 156, 168))
    for k in range(5):
        d.rectangle([1226, 606 - k * 11, 1356, 614 - k * 11], fill=(170, 170, 176))
    d.polygon([(1420, 622), (1404, 560), (1420, 520), (1450, 520), (1466, 560), (1450, 622)], fill=(60, 84, 110))
    for k in range(9):
        ang = -math.pi / 2 + (k - 4) * 0.2
        ex, ey = 1435 + math.cos(ang) * (170 + 20 * (k % 2)), 520 + math.sin(ang) * (170 + 20 * (k % 2))
        d.line([(1435, 520), (ex, ey)], fill=(50, 34, 26), width=5)
        for j in range(4):
            u = 0.45 + j * 0.17
            lx, ly = 1435 + (ex - 1435) * u + (10 if j % 2 else -10), 520 + (ey - 520) * u
            d.ellipse([lx - 12, ly - 8, lx + 12, ly + 8], fill=[(190, 80, 30), (214, 150, 40), (160, 44, 34)][(k + j) % 3])
    # chair backs across the table: big dark shapes
    chairs = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chairs)
    for cx in (470, 960, 1450):
        wood, rim = (40, 26, 24, 255), (70, 46, 36, 255)
        cd.rounded_rectangle([cx - 190, 610, cx + 190, 690], radius=34, fill=wood)
        cd.rounded_rectangle([cx - 184, 614, cx + 184, 628], radius=7, fill=rim)
        for px in (cx - 190, cx + 152):
            cd.rectangle([px, 650, px + 38, H], fill=wood)
            cd.rectangle([px, 650, px + 6, H], fill=rim)
        for k in range(4):
            sx = cx - 112 + k * 62
            cd.rectangle([sx, 686, sx + 34, 940], fill=wood)
        cd.rectangle([cx - 160, 930, cx + 160, 972], fill=wood)
    far = img.filter(ImageFilter.GaussianBlur(10))
    chairs = chairs.filter(ImageFilter.GaussianBlur(7))
    far.paste(chairs, (0, 0), chairs)
    # soft candle light: the two candles, the lamp over the middle, the sideboard's candles
    out = far
    for (x, y, rx, ry, c, a) in ((510, 590, 420, 380, (255, 150, 60), 0.24), (1410, 590, 420, 380, (255, 150, 60), 0.24),
                                 (960, 300, 520, 300, (255, 190, 110), 0.2), (960, 620, 700, 460, (255, 170, 90), 0.1),
                                 (1262, 590, 44, 44, (255, 200, 120), 0.6), (1790, 606, 40, 40, (255, 200, 120), 0.5),
                                 (1262, 590, 170, 150, (255, 150, 60), 0.22), (1790, 606, 160, 140, (255, 150, 60), 0.2),
                                 (1500, 140, 230, 150, (255, 190, 110), 0.2)):
        out = glow_at(out, x, y, rx, ry, c, a)
    # darker toward the corners, and dark where the table and the beam have their gaps
    arr = np.array(out).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1.0 - 0.42 * np.clip(((xx - W / 2) / (W / 2)) ** 2 * 0.7 + ((yy - H * 0.52) / (H / 2)) ** 2 * 0.6, 0, 1)
    arr *= v[..., None]
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    hole = Image.new("L", (W, H), 0)
    hd = ImageDraw.Draw(hole)
    for r in (0, 34):
        for c in range(COLS):
            if rows[r][c] != "#":
                hd.rectangle([c * C, r * C + (6 if r else 0), (c + 1) * C - 1, r * C + (60 if r else 54)], fill=255)
    hole = hole.filter(ImageFilter.GaussianBlur(5))
    out.paste(Image.new("RGB", (W, H), (10, 7, 9)), (0, 0), hole.point(lambda v: int(v * 0.9)))
    # the cloth's hem hangs a little way into each gap of the table (thin, in shadow)
    d = ImageDraw.Draw(out)
    for c in range(1, COLS):
        if (rows[34][c - 1] == "#") != (rows[34][c] == "#"):
            x = c * C
            xa = x if rows[34][c] != "#" else x - 8
            d.rectangle([xa, 1030, xa + 7, H], fill=(124, 118, 122))
            d.rectangle([xa + (5 if rows[34][c] != "#" else 0), 1030, xa + (7 if rows[34][c] != "#" else 2), H], fill=(84, 78, 86))
    return out.resize((W // 2, H // 2), Image.LANCZOS)


# ================================================================ a look at both, about as the page shows them
def preview(back, front, rows, path):
    dark = np.array([0.80, 0.72, 0.66], np.float32)             # client/table_view.gd DARK
    b = np.array(back.resize((W, H), Image.NEAREST)).astype(np.float32) / 255.0
    f = np.array(front.resize((W, H), Image.NEAREST)).astype(np.float32) / 255.0
    # the soft dark fringe client/edges_view.gd draws behind every block and ledge
    halo = Image.new("L", (W, H), 0)
    hd = ImageDraw.Draw(halo)
    for r in range(ROWS):
        for c in range(COLS):
            if rows[r][c] == "#":
                hd.rectangle([c * C - 6, r * C - 6, (c + 1) * C + 5, (r + 1) * C + 5], fill=110)
            elif rows[r][c] == "=":
                hd.rectangle([c * C - 3, r * C - 3, (c + 1) * C + 2, r * C + 20], fill=100)
    h = np.array(halo).astype(np.float32)[..., None] / 255.0
    scene = b * (1.0 - h)
    scene = scene * (1.0 - f[..., 3:4]) + f[..., :3] * f[..., 3:4]
    lit = scene * dark
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    for r in range(ROWS):                                       # the torches' lights (world.gd), roughly
        for c in range(COLS):
            if rows[r][c] in "abcdefgh":
                x, y = c * C + 15, r * C + 15 - 30
                k = np.clip(1.0 - np.sqrt((xx - x) ** 2 + (yy - y) ** 2) / 330.0, 0, 1) ** 2 * 0.75
                lit += scene * k[..., None] * np.array([1.0, 0.7, 0.42], np.float32)
    img = Image.fromarray((np.clip(lit, 0, 1) * 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    team = [(232, 65, 60), (60, 140, 232), (95, 211, 90), (242, 194, 48), (168, 90, 232), (240, 138, 44), (53, 214, 208), (240, 106, 168)]
    for (c0, c1, r0, r1, tray) in CANDLES:                      # a flame on each candle
        x, y = (c0 + c1 + 1) * C / 2.0, r0 * C - 8
        d.polygon([(x - 8, y), (x, y - 32), (x + 8, y), (x, y + 6)], fill=(255, 170, 60))
        d.polygon([(x - 4, y), (x, y - 18), (x + 4, y), (x, y + 4)], fill=(255, 244, 190))
    img.resize((400, 225), Image.LANCZOS).save(os.path.join(path, "table_card.png"))   # the lobby's card size (assets/arena_cards.png)
    for r in range(ROWS):                                       # a stand-in fighter on each spawn spot (36 x 63)
        for c in range(COLS):
            if rows[r][c].isdigit():
                x, y = c * C, (r + 1) * C
                col = team[int(rows[r][c]) % 8]
                d.rounded_rectangle([x - 20, y - 65, x + 19, y + 1], radius=12, fill=(255, 255, 255))
                d.rounded_rectangle([x - 17, y - 62, x + 16, y - 2], radius=10, fill=col)
                d.ellipse([x - 9, y - 54, x + 9, y - 36], fill=(20, 16, 24))
    img.save(os.path.join(path, "table_preview.png"))
    img.resize((693, 390), Image.LANCZOS).save(os.path.join(path, "table_preview_phone.png"))


def main():
    rows = read_map()
    rng = random.Random(1124)
    back = make_back(rows, rng)
    front = make_front(rows, rng)
    bad = check(front, rows)
    for (c, r, why) in bad[:20]:
        print("make_table_art: col %d row %d: %s" % (c, r, why))
    back.save(os.path.join(OUT, "table_back.png"), optimize=True)
    front.save(os.path.join(OUT, "table_front.png"), optimize=True)
    print("wrote table_back.png (%d bytes), table_front.png (%d bytes) in %s; %d cells off the map" % (
        os.path.getsize(os.path.join(OUT, "table_back.png")), os.path.getsize(os.path.join(OUT, "table_front.png")), OUT, len(bad)))
    if "--preview" in sys.argv:
        pdir = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(pdir, exist_ok=True)
        preview(back, front, rows, pdir)
        print("preview in %s" % pdir)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
