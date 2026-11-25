#!/usr/bin/env python3
"""SANTA'S WORKSHOP's art (bench/sim/level.gd, theme "workshop"), made here, never by hand.

The workshop cut open like a doll's house: warm and bright. Everything is drawn by this
code (no copied art). It reads the map from bench/sim/level.gd and works out what each
block and ledge is from where it stands (the rules are in kinds_of below), so a change
to the map needs only a new run of this tool. The art is drawn four times too big and
shrunk, so its edges are smooth.

    python3 tools/make_workshop_art.py [--preview DIR]      (needs Pillow and numpy)

writes bench/assets/:
  workshop_back.png    the room behind the play space, a little out of focus and dimmer
                       than the platforms: wood walls, wallpaper in the wings' rooms, two
                       frosty windows, the big tree, the fireplace with stockings, toy
                       shelves, the gift chute, garlands, the dark tunnels
                       (960 x 540; the page draws it twice as big)
  workshop_front.png   the blocks and ledges, and nothing outside their own cells: wood
                       beams, candy-cane posts, wrapped presents, the star on its drum,
                       fir boughs, shelves, workbenches, the floor with the train's rail,
                       the trapdoors. Every top you can stand on has a white icing lip
  workshop_parts.png   the moving parts, at the page's own size (512 x 128): the toy
                       engine, two wagons, wheels, the crossing sign, a signal lamp, the
                       chute's little presents, a lantern (PARTS below; the page's copy
                       of those boxes is client/workshop_view.gd PARTS)
--preview DIR: also DIR/workshop_preview.png (back and front as the page shows them,
with stand-in fighters on the spawn spots and the train on its track),
DIR/workshop_preview_phone.png (a phone's size) and DIR/workshop_card.png (400 x 225, no
fighters: the size of the lobby's arena cards).
The moving parts (the train, the signals, snow in the windows, the tree's lights, the
fire, the chute's presents) are client/workshop_view.gd's. Where they go is written in
both files: WINDOWS, FIRE, CHUTE, PARTS and CARS here are the same numbers there.
"""
import math
import os
import random
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVEL = os.path.join(ROOT, "bench", "sim", "level.gd")
OUT = os.path.join(ROOT, "bench", "assets")
W, H = 1920, 1080         # the arena, in screen pixels: every number below is in these
C = 30                    # a map cell
COLS, ROWS = 64, 36
SS = 2                    # the pictures are drawn at SS canvas pixels a screen pixel,
SHRINK = 4                # then shrunk by this: 960 x 540

# ---------------------------------------------------------------- where the moving parts go
# (client/workshop_view.gd has the same numbers)
WINDOWS = [(600, 100, 780, 290), (1140, 100, 1320, 290)]   # the two windows' glass: x0, y0, x1, y1
FIRE = (1440, 246, 1620, 330)                              # the firebox's opening
CHUTE = [(420, 338), (118, 506)]                           # the gift chute's slide, top to bottom (the presents slide along it)
TREE_TOP = 430                                             # the tree's tip (under the star)

# ---------------------------------------------------------------- what a cell is
EMPTY, SOLID, LEDGE = 0, 1, 2
K_CEIL, K_FLOOR, K_WALL, K_CANE, K_COLLAR_L, K_COLLAR_R, K_BEAM, K_TABLE, K_MANTEL, K_STAR, K_DRUM, K_GIFT = range(1, 13)
L_TRAP, L_BOUGH, L_BENCH, L_SHELF = 1, 2, 3, 4

# ---------------------------------------------------------------- the palette
ICING = (255, 251, 242)
ICING_S = (226, 214, 205)
WOOD = (186, 126, 74)
WOOD_L = (222, 168, 108)
WOOD_D = (128, 80, 44)
WOOD_K = (74, 42, 24)
PLANK = (236, 190, 128)
PLANK_D = (176, 122, 70)
PLANK_K = (86, 50, 28)
BENCH = (214, 150, 96)
LOG = (150, 92, 56)
LOG_L = (184, 124, 80)
LOG_D = (104, 60, 36)
LOG_K = (60, 32, 20)
ROOF = (104, 62, 42)
ROOF_D = (70, 40, 28)
ROOF_L = (150, 100, 66)
FLOOR = (170, 116, 70)
FLOOR_D = (112, 70, 42)
FLOOR_K = (70, 42, 26)
STEEL_H = (236, 242, 250)
STEEL = (158, 170, 188)
STEEL_D = (84, 94, 112)
TIE = (78, 48, 30)
CANE_R = (214, 40, 46)
CANE_RD = (150, 22, 34)
CANE_W = (252, 246, 240)
CANE_WD = (206, 196, 200)
CANE_K = (96, 18, 26)
BRICK = (176, 88, 62)
BRICK_L = (206, 118, 84)
BRICK_D = (124, 56, 42)
MORTAR = (226, 204, 180)
TIN = (176, 192, 204)
TIN_L = (226, 236, 244)
TIN_D = (104, 120, 138)
GOLD = (246, 198, 62)
GOLD_L = (255, 236, 150)
GOLD_D = (184, 124, 28)
GOLD_K = (110, 68, 14)
FIR = (38, 132, 82)
FIR_L = (74, 170, 108)
FIR_D = (20, 86, 56)
FIR_K = (10, 52, 36)
HOLLY = (206, 36, 44)
# wrapping papers: deep colours (the fighters wear the bright ones), each with its ribbon
PAPERS = [((170, 34, 50), (252, 226, 150)), ((24, 110, 72), (250, 240, 214)), ((38, 76, 150), (246, 206, 96)),
          ((112, 48, 124), (250, 232, 170)), ((16, 104, 116), (252, 244, 226)), ((196, 96, 30), (250, 244, 220))]


def read_map():
    src = open(LEVEL).read()
    i = src.index('"name": "SANTA\'S WORKSHOP"')
    j = src.index('"map": [', i)
    k = src.index("]}", j)
    rows = re.findall(r'"([#=.0-9a-h]{64})"', src[j:k])
    assert len(rows) == ROWS, len(rows)
    return rows


def grid_of(rows):
    g = np.zeros((ROWS, COLS), dtype=np.uint8)
    for r in range(ROWS):
        for c in range(COLS):
            ch = rows[r][c]
            g[r, c] = SOLID if ch == "#" else (LEDGE if ch == "=" else EMPTY)
    return g


def marks(rows):
    """The spawn spots (feet, screen px) and the torches (a cell's middle), in their order."""
    spots, lights = {}, {}
    for r in range(ROWS):
        for c in range(COLS):
            ch = rows[r][c]
            if ch.isdigit():
                spots[int(ch)] = (c * C, (r + 1) * C)
            elif "a" <= ch <= "h":
                lights[ch] = (c * C + C // 2, r * C + C // 2)
    return [spots[k] for k in sorted(spots)], [lights[k] for k in sorted(lights)]


def kinds_of(g):
    """What each block is made of, from where it stands: the frame (ceiling, floor, side
    walls); a column one cell wide and four or more high is a candy cane; a short stub
    under the ceiling is the chute's mouth (left) or the chimney pot (right); a row five
    or more long with air under it is a beam (a floor of a wing, or up top the sorting
    table on the left and the mantel on the right); the two cells in the middle of the
    arena are the star, with its drum under it; the rest are presents."""
    k = np.zeros((ROWS, COLS), dtype=np.uint8)
    inner = np.zeros((ROWS, COLS), dtype=bool)
    for r in range(ROWS):
        for c in range(COLS):
            if g[r, c] != SOLID:
                continue
            if r < 2:
                k[r, c] = K_CEIL
            elif r >= ROWS - 2:
                k[r, c] = K_FLOOR
            elif c < 2 or c >= COLS - 2:
                k[r, c] = K_WALL
            else:
                inner[r, c] = True
    for c in range(2, COLS - 2):                       # canes
        r = 2
        while r < ROWS - 2:
            if not inner[r, c]:
                r += 1
                continue
            r1 = r
            while r1 < ROWS - 2 and inner[r1, c]:
                r1 += 1
            thin = all(not inner[q, c - 1] and not inner[q, c + 1] for q in range(r, r1))
            if r1 - r >= 4 and thin:
                k[r:r1, c] = K_CANE
            elif r == 2 and thin and r1 - r <= 3:
                k[r:r1, c] = K_COLLAR_L if c < COLS // 2 else K_COLLAR_R
            r = r1
    for r in range(2, ROWS - 2):                       # beams
        c = 0
        while c < COLS:
            if not (g[r, c] == SOLID and k[r, c] in (0, K_WALL)):
                c += 1
                continue
            c1 = c
            while c1 < COLS and g[r, c1] == SOLID and k[r, c1] in (0, K_WALL):
                c1 += 1
            cells = [q for q in range(c, c1) if k[r, q] == 0]
            if len(cells) >= 5 and all(g[r + 1, q] != SOLID for q in cells):
                walled = c < 2 or c1 > COLS - 2
                kind = K_BEAM if walled or r > 8 else (K_TABLE if (cells[0] + cells[-1]) < COLS else K_MANTEL)
                for q in cells:
                    k[r, q] = kind
            c = c1
    mid = [COLS // 2 - 1, COLS // 2]                   # the star on its drum
    tops = [r for r in range(2, ROWS - 2) if inner[r, mid[0]] and inner[r, mid[1]] and k[r, mid[0]] == 0]
    if tops:
        r0 = tops[0]
        for r in tops:
            for c in mid:
                k[r, c] = K_STAR if r < r0 + 2 else K_DRUM
    k[(k == 0) & inner] = K_GIFT
    return k


def boxes_of(k, kind):
    """The cells of one kind as boxes [c0, c1, r0, r1]: each row's runs, joined downwards
    while the run is the same."""
    out = []
    open_ = {}
    for r in range(ROWS + 1):
        runs = []
        if r < ROWS:
            c = 0
            while c < COLS:
                if k[r, c] == kind:
                    c1 = c
                    while c1 < COLS and k[r, c1] == kind:
                        c1 += 1
                    runs.append((c, c1 - 1))
                    c = c1
                else:
                    c += 1
        nxt = {}
        for run in runs:
            if run in open_:
                nxt[run] = open_.pop(run)
            else:
                nxt[run] = r
        for run, r0 in open_.items():
            out.append([run[0], run[1], r0, r - 1])
        open_ = nxt
    return out


def ledge_runs(g, k):
    """Every run of ledge: [c0, c1, row, kind]. The floor's are trapdoors; the tree's
    (a run that is centred on the arena, or touches the star's drum, below the star's
    top) are fir boughs; the lowest ones (90 px over the floor) are workbenches; the
    rest are shelves."""
    star_rows = [r for r in range(ROWS) if (k[r] == K_STAR).any()]
    star_top = star_rows[0] if star_rows else 0
    out = []
    for r in range(ROWS):
        c = 0
        while c < COLS:
            if g[r, c] != LEDGE:
                c += 1
                continue
            c1 = c
            while c1 < COLS and g[r, c1] == LEDGE:
                c1 += 1
            centred = abs((c + c1) - COLS) <= 1
            by_drum = (c > 0 and k[r, c - 1] in (K_DRUM, K_STAR)) or (c1 < COLS and k[r, c1] in (K_DRUM, K_STAR))
            if r >= ROWS - 2:
                kind = L_TRAP
            elif r > star_top and (centred or by_drum):
                kind = L_BOUGH
            elif r == ROWS - 5:
                kind = L_BENCH
            else:
                kind = L_SHELF
            out.append([c, c1 - 1, r, kind])
            c = c1
    return out


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def h2(x, y, salt=0):
    """A steady random number 0..1 for a place."""
    n = (int(x) * 73856093) ^ (int(y) * 19349663) ^ (int(salt) * 83492791)
    n = (n ^ (n >> 13)) * 1274126177 & 0x7FFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


# ================================================================ the drawing kit
class Cv:
    """A canvas drawn in screen pixels, SS times as fine. Colours blend where a < 255.
    With `cover` (the front): every shape drawn solid also marks what the picture covers."""

    def __init__(self, w=W, h=H, bg=(0, 0, 0), ss=SS, cover=False):
        self.ss = ss
        self.w, self.h = w, h
        self.img = Image.new("RGB", (w * ss, h * ss), bg)
        self.d = ImageDraw.Draw(self.img, "RGBA")
        self.alpha = Image.new("L", (w * ss, h * ss), 0) if cover else None
        self.da = ImageDraw.Draw(self.alpha) if cover else None

    def _col(self, c, a):
        return (int(round(c[0])), int(round(c[1])), int(round(c[2])), int(round(a)))

    def rect(self, x0, y0, x1, y1, c, a=255):
        s = self.ss
        box = [x0 * s, y0 * s, x1 * s - 1, y1 * s - 1]
        if box[2] < box[0] or box[3] < box[1]:
            return
        self.d.rectangle(box, fill=self._col(c, a))
        if self.da is not None and a >= 255:
            self.da.rectangle(box, fill=255)

    def rrect(self, x0, y0, x1, y1, rad, c, a=255):
        s = self.ss
        box = [x0 * s, y0 * s, x1 * s - 1, y1 * s - 1]
        if box[2] < box[0] or box[3] < box[1]:
            return
        self.d.rounded_rectangle(box, radius=rad * s, fill=self._col(c, a))
        if self.da is not None and a >= 255:
            self.da.rounded_rectangle(box, radius=rad * s, fill=255)

    def poly(self, pts, c, a=255):
        s = self.ss
        q = [(x * s, y * s) for (x, y) in pts]
        self.d.polygon(q, fill=self._col(c, a))
        if self.da is not None and a >= 255:
            self.da.polygon(q, fill=255)

    def line(self, pts, c, w, a=255):
        s = self.ss
        q = [(x * s, y * s) for (x, y) in pts]
        self.d.line(q, fill=self._col(c, a), width=max(1, int(round(w * s))), joint="curve")
        if self.da is not None and a >= 255:
            self.da.line(q, fill=255, width=max(1, int(round(w * s))), joint="curve")

    def oval(self, cx, cy, rx, ry, c, a=255):
        s = self.ss
        box = [(cx - rx) * s, (cy - ry) * s, (cx + rx) * s, (cy + ry) * s]
        self.d.ellipse(box, fill=self._col(c, a))
        if self.da is not None and a >= 255:
            self.da.ellipse(box, fill=255)

    def arc(self, cx, cy, rx, ry, a0, a1, c, w, a=255):
        s = self.ss
        box = [(cx - rx) * s, (cy - ry) * s, (cx + rx) * s, (cy + ry) * s]
        self.d.arc(box, a0, a1, fill=self._col(c, a), width=max(1, int(round(w * s))))

    def vgrad(self, x0, y0, x1, y1, top, bot, a=255):
        """A box with one colour at the top and another at the bottom."""
        s = self.ss
        w, h = int((x1 - x0) * s), int((y1 - y0) * s)
        if w <= 0 or h <= 0:
            return
        t = np.linspace(0.0, 1.0, h)[:, None, None]
        arr = np.asarray(top, dtype=np.float32)[None, None, :] * (1 - t) + np.asarray(bot, dtype=np.float32)[None, None, :] * t
        lay = Image.fromarray(np.broadcast_to(arr, (h, w, 3)).astype(np.uint8), "RGB")
        if a >= 255:
            self.img.paste(lay, (int(x0 * s), int(y0 * s)))
            if self.da is not None:
                self.da.rectangle([x0 * s, y0 * s, x1 * s - 1, y1 * s - 1], fill=255)
        else:
            self.img.paste(lay, (int(x0 * s), int(y0 * s)), Image.new("L", (w, h), int(a)))
        self.d = ImageDraw.Draw(self.img, "RGBA")

    def glow(self, cx, cy, rx, ry, c, a):
        """A soft round light (added)."""
        s = self.ss
        x0, y0 = int((cx - rx) * s), int((cy - ry) * s)
        w, h = int(2 * rx * s), int(2 * ry * s)
        if w <= 0 or h <= 0:
            return
        yy, xx = np.mgrid[0:h, 0:w]
        d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
        k = np.clip(1.0 - d, 0.0, 1.0) ** 2 * (a / 255.0)
        bx0, by0 = max(0, x0), max(0, y0)
        bx1, by1 = min(self.img.width, x0 + w), min(self.img.height, y0 + h)
        if bx1 <= bx0 or by1 <= by0:
            return
        k = k[by0 - y0:by1 - y0, bx0 - x0:bx1 - x0, None]
        base = np.asarray(self.img.crop((bx0, by0, bx1, by1)), dtype=np.float32)
        out = np.clip(base + np.asarray(c, dtype=np.float32)[None, None, :] * k, 0, 255).astype(np.uint8)
        self.img.paste(Image.fromarray(out, "RGB"), (bx0, by0))
        self.d = ImageDraw.Draw(self.img, "RGBA")

    def shade(self, x0, y0, x1, y1, c, a_top, a_bot):
        """A box of one colour, its strength going from a_top to a_bot down the box."""
        s = self.ss
        w, h = int((x1 - x0) * s), int((y1 - y0) * s)
        if w <= 0 or h <= 0:
            return
        m = np.linspace(a_top, a_bot, h)[:, None]
        mask = Image.fromarray(np.broadcast_to(m, (h, w)).astype(np.uint8), "L")
        self.img.paste(Image.new("RGB", (w, h), tuple(int(v) for v in c)), (int(x0 * s), int(y0 * s)), mask)
        self.d = ImageDraw.Draw(self.img, "RGBA")


def star_pts(cx, cy, r_out, r_in, n=5, turn=-90.0):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(turn + i * 180.0 / n)
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


# ================================================================ the front: each kind of block
def icing(cv, x0, x1, y, deep=6, drips=True, seed=0):
    """The white icing on a top you can stand on: a band, and little drips under it."""
    cv.rect(x0, y, x1, y + deep, ICING)
    cv.rect(x0, y + deep, x1, y + deep + 2, ICING_S)
    if drips:
        x = x0 + 5 + h2(x0, y, seed) * 8
        while x < x1 - 5:
            r = 3.0 + h2(x, y, seed + 1) * 2.5
            d = 1.0 + h2(x, y, seed + 2) * 5.0
            cv.rect(x - r, y + deep - 1, x + r, y + deep + d, ICING)
            cv.oval(x, y + deep + d, r, r, ICING)
            x += 13 + h2(x, y, seed + 3) * 15


def wood_grain(cv, x0, y0, x1, y1, dark, light, seed):
    n = max(1, int((y1 - y0) / 7))
    for i in range(n):
        y = y0 + 4 + i * (y1 - y0 - 6) / max(1, n) + h2(x0, i, seed) * 2
        x = x0 + h2(i, y0, seed) * 40
        while x < x1 - 8:
            ln = 26 + h2(x, i, seed) * 60
            cv.rect(x, y, min(x1 - 3, x + ln), y + 1.5, dark, 110)
            x += ln + 12 + h2(x, i, seed + 5) * 40
    for i in range(int((x1 - x0) / 90) + 1):
        kx = x0 + 30 + i * 90 + h2(i, y0, seed + 9) * 40
        if kx < x1 - 14 and h2(i, y0, seed + 11) < 0.5:
            ky = (y0 + y1) / 2 + (h2(i, x0, seed + 12) - 0.5) * (y1 - y0) * 0.4
            cv.oval(kx, ky, 5, 3, dark, 150)
            cv.oval(kx, ky, 2.5, 1.5, light, 160)


def paint_ceiling(cv, g, k):
    for b in boxes_of(k, K_CEIL):
        x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
        cv.vgrad(x0, y0, x1, y1, ROOF_D, ROOF)
        x = x0
        while x < x1:                                   # the rafters' ends
            cv.rect(x + 22, y0 + 8, x + 38, y1 - 14, ROOF_D)
            cv.rect(x + 24, y0 + 10, x + 36, y1 - 16, mix(ROOF, ROOF_L, 0.4))
            x += 60
        cv.rect(x0, y1 - 10, x1, y1 - 6, ROOF_L)        # the trim, and the garland along it
        cv.rect(x0, y1 - 6, x1, y1, ROOF_D)
        x = x0 + 6
        i = 0
        while x < x1 - 2:
            cv.oval(x, y1 - 6, 8, 6, FIR_D if i % 2 else FIR)
            cv.oval(x - 2, y1 - 8, 4, 3, FIR_L, 200)
            if i % 4 == 1:
                cv.oval(x, y1 - 5, 3.2, 3.2, HOLLY)
                cv.oval(x - 1, y1 - 6, 1.2, 1.2, (255, 190, 190))
            elif i % 4 == 3:
                cv.oval(x, y1 - 5, 2.6, 2.6, GOLD)
            x += 11
            i += 1
        if b[0] > 0:                                    # an opening's edge
            cv.rect(x0, y0, x0 + 4, y1, ROOF_D)
        if b[1] < COLS - 1:
            cv.rect(x1 - 4, y0, x1, y1, ROOF_D)


def paint_floor(cv, g, k):
    top = (ROWS - 2) * C
    for b in boxes_of(k, K_FLOOR):
        x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
        cv.vgrad(x0, y0, x1, y1, FLOOR, FLOOR_D)
        x = x0
        i = 0
        while x < x1:                                   # the floor's joists, seen from the end
            cv.rect(x, y0 + 16, x + 3, y1, FLOOR_K, 170)
            cv.rect(x + 3, y0 + 16, x + 5, y1, mix(FLOOR, WOOD_L, 0.5), 120)
            x += 30
            i += 1
        cv.rect(x0, y0 + 13, x1, y0 + 16, FLOOR_K, 200)
        if b[0] > 0 and b[2] == top:
            cv.rect(x0, y0 + 10, x0 + 4, y1, FLOOR_K)
        if b[1] < COLS - 1 and b[2] == top:
            cv.rect(x1 - 4, y0 + 10, x1, y1, FLOOR_K)
    rail(cv, 0, W, top)


def rail(cv, x0, x1, y):
    """The toy train's track along a top: sleepers, and one bright steel rail on them."""
    x = x0 - (x0 % 30) + 4
    while x < x1:
        a, b = max(x0, x), min(x1, x + 16)
        if b > a:
            cv.rect(a, y + 5, b, y + 13, TIE)
            cv.rect(a, y + 5, b, y + 7, mix(TIE, WOOD_L, 0.35))
        x += 30
    cv.rect(x0, y, x1, y + 3, STEEL_H)
    cv.rect(x0, y + 3, x1, y + 6, STEEL)
    cv.rect(x0, y + 6, x1, y + 7.5, STEEL_D)


def paint_walls(cv, g, k):
    for b in boxes_of(k, K_WALL):
        x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
        left = b[0] < COLS // 2
        cv.rect(x0, y0, x1, y1, LOG)
        r = b[2]
        while r <= b[3]:                                # a log to a cell, round: light on top, dark under
            y = r * C
            cv.vgrad(x0, y, x1, y + 12, LOG_L, LOG)
            cv.vgrad(x0, y + 12, x1, y + 27, LOG, LOG_D)
            cv.rect(x0, y + 27, x1, y + 30, LOG_K)
            for i in range(2):
                gx = x0 + 6 + h2(r, i, 3) * 36
                cv.rect(gx, y + 8 + i * 9, gx + 14, y + 9.5 + i * 9, LOG_D, 140)
            r += 1
        ix = x1 - 6 if left else x0                     # the wall's face to the room
        cv.rect(ix, y0, ix + 6, y1, LOG_K)
        cv.rect(ix + (0 if left else 4), y0, ix + (2 if left else 6), y1, mix(LOG_K, LOG_L, 0.35))
        if g[(b[2] - 1) % ROWS, b[0]] == EMPTY:         # an opening above: its sill (snow on it)
            icing(cv, x0, x1, y0, 6, True, b[2])
        if g[(b[3] + 1) % ROWS, b[0]] == EMPTY:         # an opening below
            deep = (b[3] + 1) * C >= (ROWS - 5) * C     # the tunnel: a stone arch; the window: a lintel with icicles
            if deep:
                cv.rect(x0, y1 - 42, x1, y1, (120, 124, 138))
                for i in range(2):
                    for j in range(3):
                        bx = x0 + j * 22 - (11 if i else 0)
                        cv.rect(max(x0, bx), y1 - 42 + i * 21, min(x1, bx + 20), y1 - 23 + i * 21, (164, 168, 182))
                        cv.rect(max(x0, bx), y1 - 42 + i * 21, min(x1, bx + 20), y1 - 39 + i * 21, (204, 208, 220))
                cv.rect(x0, y1 - 5, x1, y1, (58, 60, 74))
                kx = x1 - 30 if left else x0 + 2        # the signal's two lamps on the arch (dark here: the page lights them)
                cv.rrect(kx, y1 - 38, kx + 28, y1 - 9, 5, (28, 28, 36))
                for j in range(2):
                    cv.oval(kx + 14, y1 - 31 + j * 15, 5.5, 5.5, (92, 26, 30))
                    cv.oval(kx + 12.5, y1 - 32.5 + j * 15, 2, 2, (150, 70, 70))
            else:
                cv.rect(x0, y1 - 12, x1, y1, WOOD_K)
                cv.rect(x0, y1 - 12, x1, y1 - 9, WOOD_L)
                x = x0 + 5
                while x < x1 - 4:                       # icicles
                    ln = 4 + h2(x, b[3], 5) * 7
                    cv.poly([(x - 2.5, y1 - 9), (x + 2.5, y1 - 9), (x, y1 - 9 + ln)], (224, 240, 255))
                    x += 8 + h2(x, b[3], 6) * 5


def paint_beams(cv, g, k):
    for kind in (K_BEAM, K_TABLE, K_MANTEL):
        for b in boxes_of(k, kind):
            x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
            open_l = k[b[2], b[0] - 1] == 0 and g[b[2], b[0] - 1] != LEDGE
            open_r = k[b[2], (b[1] + 1) % COLS] == 0 and g[b[2], (b[1] + 1) % COLS] != LEDGE
            if kind == K_MANTEL:                        # bricks under a pale stone shelf
                cv.rect(x0, y0, x1, y1, BRICK)
                for i in range(2):
                    y = y0 + 8 + i * 11
                    x = x0 - (9 if i else 0)
                    while x < x1:
                        a, c2 = max(x0, x), min(x1, x + 17)
                        if c2 > a:
                            cv.rect(a, y, c2, y + 9, BRICK if (int(x) // 18 + i) % 3 else BRICK_L)
                            cv.rect(a, y + 7.5, c2, y + 9, BRICK_D, 150)
                        x += 18.5
                cv.rect(x0, y1 - 3, x1, y1, BRICK_D)
                cv.rect(x0, y0, x1, y0 + 9, (232, 224, 214))
                cv.rect(x0, y0 + 9, x1, y0 + 11, (150, 138, 132))
            else:
                cv.vgrad(x0, y0, x1, y1, WOOD_L if kind == K_TABLE else WOOD, WOOD_D if kind == K_TABLE else mix(WOOD, WOOD_D, 0.6))
                wood_grain(cv, x0, y0 + 9, x1, y1 - 3, WOOD_D, WOOD_L, b[2])
                cv.rect(x0, y1 - 3, x1, y1, WOOD_K)
                if kind == K_TABLE:                     # the sorting table's steel band and bolts
                    cv.rect(x0, y0 + 14, x1, y0 + 21, TIN_D)
                    cv.rect(x0, y0 + 14, x1, y0 + 16, TIN_L)
                    x = x0 + 9
                    while x < x1 - 4:
                        cv.oval(x, y0 + 18, 2, 2, TIN_L)
                        x += 30
            icing(cv, x0, x1, y0, 6, kind != K_MANTEL, b[2] * 7 + b[0])
            for side, opened, x in ((0, open_l, x0), (1, open_r, x1)):
                if not opened:
                    continue
                e0 = x if side == 0 else x - 4          # the beam's cut end: rings
                cv.rect(e0, y0 + 8, e0 + 4, y1, WOOD_K if kind != K_MANTEL else BRICK_D)


def paint_collars(cv, g, k):
    for kind in (K_COLLAR_L, K_COLLAR_R):
        for b in boxes_of(k, kind):
            x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
            if kind == K_COLLAR_R:                      # the chimney pot: brick
                cv.rect(x0, y0, x1, y1, BRICK)
                y = y0
                i = 0
                while y < y1:
                    x = x0 - (8 if i % 2 else 0)
                    while x < x1:
                        a, c2 = max(x0, x), min(x1, x + 15)
                        if c2 > a:
                            cv.rect(a, y + 1, c2, y + 9, BRICK_L if (i + int(x)) % 3 == 0 else BRICK)
                        x += 16.5
                    cv.rect(x0, y + 9, x1, y + 10.5, MORTAR, 200)
                    y += 10.5
                    i += 1
                cv.rect(x0, y1 - 7, x1, y1, BRICK_D)
                cv.rect(x0, y1 - 9, x1, y1 - 7, MORTAR)
            else:                                       # the chute's mouth: striped tin
                cv.vgrad(x0, y0, x1, y1, TIN_L, TIN)
                for i in range(int((y1 - y0) / 20) + 1):
                    cv.rect(x0, y0 + 6 + i * 20, x1, y0 + 14 + i * 20, CANE_R)
                    cv.rect(x0, y0 + 12.5 + i * 20, x1, y0 + 14 + i * 20, CANE_RD)
                cv.rect(x0, y1 - 6, x1, y1, TIN_D)
                cv.rect(x0, y1 - 8, x1, y1 - 6, TIN_L)
                for i in range(int((y1 - y0) / 20) + 1):
                    cv.oval(x0 + 15, y0 + 20 + i * 20, 2, 2, TIN_D)
            cv.rect(x0, y0, x0 + 3, y1, (40, 30, 34), 200)
            cv.rect(x1 - 3, y0, x1, y1, (40, 30, 34), 200)


def paint_canes(cv, g, k):
    for b in boxes_of(k, K_CANE):
        x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
        cv.rect(x0, y0, x1, y1, CANE_W)
        y = y0 - 40.0                                   # the red stripes, slanting
        while y < y1 + 10:
            pts = [(x0, y + 26), (x1, y), (x1, y + 17), (x0, y + 43)]
            pts = [(px, min(max(py, y0), y1)) for (px, py) in pts]
            cv.poly(pts, CANE_R)
            y += 46.0
        cv.rect(x0, y0, x0 + 3, y1, CANE_K)             # round: an edge each side, a shine, a shade
        cv.rect(x1 - 3, y0, x1, y1, CANE_K)
        cv.rect(x0 + 6, y0, x0 + 10, y1, (255, 255, 255), 190)
        cv.rect(x1 - 10, y0, x1 - 3, y1, CANE_RD, 80)
        cv.rect(x0, y1 - 3, x1, y1, CANE_K)
        if g[b[2] - 1, b[0]] == EMPTY:                  # its top, level with the shelf it stands in
            icing(cv, x0, x1, y0, 5, False)
        else:
            cv.rect(x0, y0, x1, y0 + 3, CANE_K)


def gift(cv, x0, y0, x1, y1, n, snow=True):
    """One wrapped present: its paper, a ribbon up and across, a lid, a flat bow."""
    paper, ribbon = PAPERS[n % len(PAPERS)]
    dark = mix(paper, (0, 0, 0), 0.45)
    lite = mix(paper, (255, 255, 255), 0.28)
    cv.rect(x0, y0, x1, y1, dark)
    cv.vgrad(x0 + 3, y0 + 3, x1 - 3, y1 - 3, lite, paper)
    pat = n % 3                                         # the paper's pattern
    if pat == 0:
        yy = y0 + 20
        while yy < y1 - 6:
            xx = x0 + 9 + (8 if int(yy) % 2 else 0)
            while xx < x1 - 6:
                cv.oval(xx, yy, 2.2, 2.2, mix(paper, (255, 255, 255), 0.5), 200)
                xx += 16
            yy += 11
    elif pat == 1:
        xx = x0 + 9
        while xx < x1 - 6:
            cv.rect(xx, y0 + 15, xx + 3, y1 - 3, mix(paper, (255, 255, 255), 0.4), 150)
            xx += 11
    else:
        yy = y0 + 19
        while yy < y1 - 6:
            cv.rect(x0 + 3, yy, x1 - 3, yy + 2.5, mix(paper, (0, 0, 0), 0.25), 150)
            yy += 9
    mx = (x0 + x1) / 2
    cv.rect(mx - 6, y0 + 3, mx + 6, y1 - 3, ribbon)
    cv.rect(mx + 3.5, y0 + 3, mx + 6, y1 - 3, mix(ribbon, (120, 80, 20), 0.35))
    if y1 - y0 > 45:
        my = y0 + 13 + (y1 - y0 - 13) / 2
        cv.rect(x0 + 3, my - 5, x1 - 3, my + 5, ribbon)
        cv.rect(x0 + 3, my + 3, x1 - 3, my + 5, mix(ribbon, (120, 80, 20), 0.35))
    cv.rect(x0, y0 + 12, x1, y0 + 15, dark)             # under the lid
    for sgn in (-1, 1):                                 # the bow, flat on the lid's front
        cv.poly([(mx, y0 + 9), (mx + sgn * 15, y0 + 3.5), (mx + sgn * 17, y0 + 12), (mx + sgn * 5, y0 + 12)], mix(ribbon, (255, 255, 255), 0.25))
        cv.poly([(mx, y0 + 9), (mx + sgn * 12, y0 + 6.5), (mx + sgn * 13, y0 + 11)], mix(ribbon, (120, 80, 20), 0.3))
    cv.oval(mx, y0 + 9, 3.5, 3.5, ribbon)
    if snow:
        icing(cv, x0, x1, y0, 5, False)


def chest(cv, x0, y0, x1, y1):
    """A toy chest: planks, brass bands, a lock."""
    cv.rect(x0, y0, x1, y1, WOOD_K)
    cv.vgrad(x0 + 3, y0 + 3, x1 - 3, y1 - 3, WOOD_L, WOOD)
    y = y0 + 16
    while y < y1 - 4:
        cv.rect(x0 + 3, y, x1 - 3, y + 1.5, WOOD_D)
        y += 12
    cv.rect(x0, y0 + 17, x1, y0 + 20, WOOD_K)           # the lid's line
    for bx in (x0 + 12, x1 - 22):
        cv.rect(bx, y0 + 3, bx + 10, y1 - 3, GOLD)
        cv.rect(bx + 7, y0 + 3, bx + 10, y1 - 3, GOLD_D)
        for by in (y0 + 10, y0 + 30, y1 - 10):
            cv.oval(bx + 5, by, 2, 2, GOLD_K)
    mx = (x0 + x1) / 2
    cv.rrect(mx - 9, y0 + 14, mx + 9, y0 + 34, 3, GOLD)
    cv.oval(mx, y0 + 22, 3, 3, GOLD_K)
    cv.rect(mx - 1.2, y0 + 22, mx + 1.2, y0 + 30, GOLD_K)
    icing(cv, x0, x1, y0, 5, False)


def paint_gifts(cv, g, k):
    n = 0
    for b in sorted(boxes_of(k, K_GIFT)):
        x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
        if b[1] - b[0] >= 3 and (b[0] == 2 or b[1] == COLS - 3):
            chest(cv, x0, y0, x1, y1)
        else:
            gift(cv, x0, y0, x1, y1, n + b[0])
        n += 1


def paint_star(cv, g, k):
    for b in boxes_of(k, K_DRUM):                       # the toy drum the star stands on
        x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
        cv.rect(x0, y0, x1, y1, CANE_K)
        cv.vgrad(x0 + 3, y0, x1 - 3, y1, CANE_R, CANE_RD)
        cv.rect(x0 + 8, y0, x0 + 12, y1, (255, 150, 150), 110)
        cv.rect(x0, y0, x1, y0 + 8, GOLD)
        cv.rect(x0, y0 + 6, x1, y0 + 8, GOLD_D)
        cv.rect(x0, y1 - 8, x1, y1, GOLD)
        cv.rect(x0, y1 - 8, x1, y1 - 6, GOLD_L)
        cv.rect(x0, y1 - 2, x1, y1, GOLD_K)
        n = 4
        for i in range(n):                              # the cords: a zigzag
            ax = x0 + 3 + i * (x1 - x0 - 6) / n
            bx = ax + (x1 - x0 - 6) / n
            cv.line([(ax, y0 + 9), ((ax + bx) / 2, y1 - 9), (bx, y0 + 9)], ICING, 2.2)
    for b in boxes_of(k, K_STAR):
        x0, y0, x1, y1 = b[0] * C, b[2] * C, (b[1] + 1) * C, (b[3] + 1) * C
        cv.rect(x0, y0, x1, y1, GOLD_K)
        cv.vgrad(x0 + 3, y0 + 3, x1 - 3, y1 - 3, GOLD, GOLD_D)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2 + 3
        cv.poly(star_pts(cx, cy, 25, 11), GOLD_K)
        cv.poly(star_pts(cx, cy, 22, 9.5), GOLD_L)
        cv.poly(star_pts(cx - 1.5, cy - 1.5, 12, 5.5), (255, 252, 226))
        icing(cv, x0, x1, y0, 5, False)


def bracket(cv, x, y, sgn, dark, lite):
    """A small strut under a ledge's end, where it meets a wall or a post."""
    cv.poly([(x, y + 11), (x + sgn * 16, y + 11), (x, y + 27)], dark)
    cv.poly([(x + sgn * 2, y + 11), (x + sgn * 11, y + 11), (x + sgn * 2, y + 20)], lite)


def paint_ledges(cv, g, k):
    for (c0, c1, r, kind) in ledge_runs(g, k):
        x0, x1, y = c0 * C, (c1 + 1) * C, r * C
        wall_l = g[r, c0 - 1] == SOLID
        wall_r = g[r, (c1 + 1) % COLS] == SOLID
        if kind == L_TRAP:                              # a hatch in the floor: red and white bars, the rail across it
            cv.rect(x0, y, x1, y + 11, CANE_W)
            x = x0
            i = 0
            while x < x1:
                if i % 2 == 0:
                    cv.rect(x, y + 6, min(x1, x + 15), y + 11, CANE_R)
                x += 15
                i += 1
            cv.rect(x0, y + 10, x1, y + 12, CANE_K)
            cv.rect(x0, y, x1, y + 3, STEEL_H)
            cv.rect(x0, y + 3, x1, y + 6, STEEL)
            for hx in (x0 + 2, x1 - 8):                 # its hinges
                cv.rect(hx, y + 5, hx + 6, y + 12, STEEL_D)
        elif kind == L_BOUGH:                           # a fir bough under snow: needles hang from it
            x = x0 + 2
            i = 0
            while x < x1 - 3:
                ln = 11 + h2(x, r, 2) * 8
                wd = 9 + h2(x, r, 3) * 4
                cv.poly([(x - 1, y + 8), (x + wd, y + 8), (x + wd * 0.5 + (h2(x, r, 4) - 0.5) * 6, y + 8 + ln)], FIR_D if i % 2 else FIR_K)
                x += wd - 2
                i += 1
            cv.rect(x0, y + 4, x1, y + 11, FIR)
            cv.rect(x0, y + 9, x1, y + 11, FIR_D)
            x = x0 + 4
            while x < x1 - 6:                           # lighter needles along it
                cv.rect(x, y + 6, x + 6, y + 7.5, FIR_L)
                x += 11 + h2(x, r, 6) * 9
            cv.rect(x0, y, x1, y + 5, ICING)            # the snow on top, heaped at the ends
            cv.rect(x0, y + 5, x1, y + 6.5, ICING_S)
            for ex in (x0, x1):
                cv.oval(ex + (5 if ex == x0 else -5), y + 5, 6, 5, ICING)
        else:
            body, dark, edge = (BENCH, PLANK_D, PLANK_K) if kind == L_BENCH else (PLANK, PLANK_D, PLANK_K)
            if wall_l:
                bracket(cv, x0, y, 1, edge, dark)
            if wall_r:
                bracket(cv, x1, y, -1, edge, dark)
            cv.rect(x0, y, x1, y + 11, body)
            cv.rect(x0, y + 8, x1, y + 11, dark)
            cv.rect(x0, y + 10.5, x1, y + 12.5, edge)
            cv.rect(x0, y, x1, y + 4.5, ICING)
            cv.rect(x0, y + 4.5, x1, y + 5.5, ICING_S)
            if not wall_l:
                cv.rect(x0, y, x0 + 2.5, y + 12, edge)
            if not wall_r:
                cv.rect(x1 - 2.5, y, x1, y + 12, edge)
            x = x0 + 60
            while x < x1 - 20:                          # where two boards meet
                cv.rect(x, y + 5, x + 1.5, y + 10.5, edge)
                x += 60
            if kind == L_BENCH:                         # the workbench's apron and its two pegs
                cv.rect(x0 + 6, y + 12, x1 - 6, y + 18, dark)
                cv.rect(x0 + 6, y + 17, x1 - 6, y + 19, edge)
                for px in (x0 + 16, x1 - 16):
                    cv.oval(px, y + 15, 2.5, 2.5, edge)


def cover_mask(g):
    """Where the front may be: a block's whole cell, a ledge's whole cell (its plank is
    the top 11 px; a strut or a bough's needles hang in the rest)."""
    m = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(m)
    for r in range(ROWS):
        for c in range(COLS):
            if g[r, c] != EMPTY:
                d.rectangle([c * C * SS, r * C * SS, (c + 1) * C * SS - 1, (r + 1) * C * SS - 1], fill=255)
    return m


def make_front(rows):
    g = grid_of(rows)
    k = kinds_of(g)
    cv = Cv(cover=True)
    paint_walls(cv, g, k)
    paint_ceiling(cv, g, k)
    paint_floor(cv, g, k)
    paint_beams(cv, g, k)
    paint_collars(cv, g, k)
    paint_gifts(cv, g, k)
    paint_star(cv, g, k)
    paint_ledges(cv, g, k)
    paint_canes(cv, g, k)
    # nothing outside a block's or a ledge's own cell; then shrink (the colour weighed by what it covers)
    alpha = np.minimum(np.asarray(cv.alpha, dtype=np.float32), np.asarray(cover_mask(g), dtype=np.float32)) / 255.0
    rgb = np.asarray(cv.img, dtype=np.float32) * alpha[:, :, None]
    size = (W * SS // SHRINK, H * SS // SHRINK)
    small_a = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8), "L").resize(size, Image.LANCZOS), dtype=np.float32) / 255.0
    small = np.asarray(Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").resize(size, Image.LANCZOS), dtype=np.float32)
    out = np.where(small_a[:, :, None] > 0.003, small / np.maximum(small_a[:, :, None], 0.003), 0.0)
    front = Image.fromarray(np.dstack([np.clip(out, 0, 255), small_a * 255]).astype(np.uint8), "RGBA")
    check(front, g)
    return front


def check(front, g):
    """Every block is drawn (no see-through cell), every ledge has its plank, and no
    empty cell has paint in it."""
    a = np.asarray(front)[:, :, 3]
    s = C * SS // SHRINK                                 # a cell in the picture: 15 px
    bad = []
    for r in range(ROWS):
        for c in range(COLS):
            cell = a[r * s:(r + 1) * s, c * s:(c + 1) * s]
            if g[r, c] == SOLID and cell[1:-1, 1:-1].min() < 250:
                bad.append("block (%d, %d) is not all drawn" % (c, r))
            elif g[r, c] == LEDGE and cell[1:5, 1:-1].min() < 250:
                bad.append("ledge (%d, %d) has no plank" % (c, r))
            elif g[r, c] == EMPTY and cell[1:-1, 1:-1].max() > 8:
                bad.append("paint in the empty cell (%d, %d)" % (c, r))
    assert not bad, "; ".join(bad[:12])


# ================================================================ the back: the room
WALL_A = (172, 122, 72)          # the hall's boards
WALL_B = (162, 114, 68)
WALL_K = (112, 72, 44)
WAINSCOT = (112, 64, 44)
WAINSCOT_D = (84, 46, 32)
WAINSCOT_L = (140, 86, 58)
NIGHT_T = (18, 30, 78)
NIGHT_B = (58, 92, 156)
SNOW = (226, 236, 250)
FRAME = (226, 208, 178)
FRAME_D = (150, 124, 96)


def room_boxes(g, k):
    """The wings' rooms: the space between a side wall and its candy-cane post, cut into
    rooms by the wing's beams. [x0, y0, x1, y1, which side, which room from the top]."""
    out = []
    canes = [b for b in boxes_of(k, K_CANE) if b[3] - b[2] >= 8]
    for side in (0, 1):
        post = [b for b in canes if (b[0] < COLS // 2) == (side == 0)]
        if not post:
            continue
        pc = post[0][0]
        c0, c1 = (2, pc - 1) if side == 0 else (pc + 1, COLS - 3)
        wall_c = 2 if side == 0 else COLS - 3
        floors = [r for r in range(2, ROWS - 2) if k[r, wall_c] == K_BEAM]
        tops = [2] + [r + 1 for r in floors]
        ends = floors + [ROWS - 2]
        for i in range(len(tops)):
            out.append([c0 * C, tops[i] * C, (c1 + 1) * C, ends[i] * C, side, i])
    return out


def toy_bear(cv, x, y, s, c=(170, 112, 62)):
    """A teddy bear sitting, its feet at (x, y), s its size (1: 44 px high)."""
    d = mix(c, (0, 0, 0), 0.35)
    li = mix(c, (255, 240, 210), 0.45)
    cv.oval(x - 11 * s, y - 5 * s, 7 * s, 5 * s, d)              # legs
    cv.oval(x + 11 * s, y - 5 * s, 7 * s, 5 * s, d)
    cv.oval(x, y - 14 * s, 13 * s, 14 * s, c)                    # body
    cv.oval(x, y - 12 * s, 7 * s, 8 * s, li)
    cv.oval(x - 13 * s, y - 20 * s, 5 * s, 7 * s, c)             # arms
    cv.oval(x + 13 * s, y - 20 * s, 5 * s, 7 * s, c)
    cv.oval(x - 9 * s, y - 41 * s, 5 * s, 5 * s, d)              # ears
    cv.oval(x + 9 * s, y - 41 * s, 5 * s, 5 * s, d)
    cv.oval(x, y - 33 * s, 11 * s, 10 * s, c)                    # head
    cv.oval(x, y - 30 * s, 5 * s, 4 * s, li)
    cv.oval(x - 4 * s, y - 35 * s, 1.5 * s, 1.5 * s, (30, 20, 16))
    cv.oval(x + 4 * s, y - 35 * s, 1.5 * s, 1.5 * s, (30, 20, 16))
    cv.oval(x, y - 31 * s, 1.8 * s, 1.4 * s, (30, 20, 16))
    cv.rect(x - 6 * s, y - 25 * s, x + 6 * s, y - 22 * s, HOLLY)    # a ribbon


def toy_drum(cv, x, y, s):
    cv.rect(x - 14 * s, y - 22 * s, x + 14 * s, y, (176, 40, 44))
    cv.rect(x - 14 * s, y - 22 * s, x + 14 * s, y - 18 * s, GOLD)
    cv.rect(x - 14 * s, y - 4 * s, x + 14 * s, y, GOLD)
    for i in range(3):
        ax = x - 14 * s + i * 28 * s / 3
        cv.line([(ax, y - 18 * s), (ax + 14 * s / 3, y - 4 * s), (ax + 28 * s / 3, y - 18 * s)], ICING, 1.6 * s)
    cv.oval(x, y - 22 * s, 14 * s, 3.5 * s, (240, 226, 200))


def toy_soldier(cv, x, y, s, coat=(196, 40, 44)):
    cv.rect(x - 5 * s, y - 14 * s, x - 1 * s, y, (30, 40, 90))                # legs
    cv.rect(x + 1 * s, y - 14 * s, x + 5 * s, y, (30, 40, 90))
    cv.rect(x - 6 * s, y - 2 * s, x + 6 * s, y, (20, 20, 24))
    cv.rect(x - 7 * s, y - 30 * s, x + 7 * s, y - 14 * s, coat)               # coat
    cv.line([(x - 6 * s, y - 29 * s), (x + 6 * s, y - 16 * s)], ICING, 1.6 * s)
    cv.line([(x + 6 * s, y - 29 * s), (x - 6 * s, y - 16 * s)], ICING, 1.6 * s)
    cv.rect(x - 10 * s, y - 29 * s, x - 7 * s, y - 16 * s, coat)              # arms
    cv.rect(x + 7 * s, y - 29 * s, x + 10 * s, y - 16 * s, coat)
    cv.oval(x, y - 35 * s, 5.5 * s, 5.5 * s, (240, 196, 160))                 # face
    cv.rect(x - 6 * s, y - 50 * s, x + 6 * s, y - 38 * s, (24, 24, 30))       # the tall hat
    cv.rect(x - 6 * s, y - 40 * s, x + 6 * s, y - 38 * s, GOLD)
    cv.oval(x, y - 50 * s, 2.5 * s, 2.5 * s, HOLLY)


def toy_ball(cv, x, y, r, c1, c2):
    cv.oval(x, y - r, r, r, c1)
    cv.poly([(x - r * 0.3, y - 2 * r), (x + r * 0.3, y - 2 * r), (x + r * 0.9, y - r * 0.6), (x + r * 0.5, y - r * 0.15)], c2)
    cv.oval(x - r * 0.35, y - r * 1.4, r * 0.25, r * 0.25, (255, 255, 255), 170)


def toy_blocks(cv, x, y, s):
    cols = [(196, 60, 50), (60, 130, 190), (230, 180, 60), (70, 150, 90)]
    for i, (dx, dy) in enumerate([(-14, 0), (2, 0), (-6, -15), (18, 0)]):
        bx, by = x + dx * s, y + dy * s
        cv.rect(bx, by - 15 * s, bx + 15 * s, by, cols[i % 4])
        cv.rect(bx + 3 * s, by - 12 * s, bx + 12 * s, by - 3 * s, mix(cols[i % 4], (255, 255, 255), 0.45))


def toy_gift(cv, x, y, w, h, n):
    paper, ribbon = PAPERS[n % len(PAPERS)]
    cv.rect(x - w / 2, y - h, x + w / 2, y, paper)
    cv.rect(x - w / 2, y - h, x + w / 2, y - h + 3, mix(paper, (255, 255, 255), 0.3))
    cv.rect(x - 2.5, y - h, x + 2.5, y, ribbon)
    cv.rect(x - w / 2, y - h * 0.55, x + w / 2, y - h * 0.55 + 4, ribbon)


def toy_horse(cv, x, y, s):
    """A rocking horse, the rocker's lowest point at (x, y)."""
    body = (200, 150, 96)
    dark = (120, 78, 44)
    cv.arc(x, y - 36 * s, 46 * s, 36 * s, 35, 145, (176, 40, 44), 5 * s)                 # the rocker
    cv.rect(x - 22 * s, y - 34 * s, x - 17 * s, y - 6 * s, dark)                          # legs
    cv.rect(x + 14 * s, y - 34 * s, x + 19 * s, y - 6 * s, dark)
    cv.rrect(x - 26 * s, y - 50 * s, x + 22 * s, y - 30 * s, 9 * s, body)                 # body
    cv.poly([(x + 10 * s, y - 46 * s), (x + 24 * s, y - 72 * s), (x + 34 * s, y - 66 * s), (x + 22 * s, y - 38 * s)], body)   # neck
    cv.rrect(x + 22 * s, y - 76 * s, x + 44 * s, y - 62 * s, 5 * s, body)                 # head
    cv.poly([(x + 24 * s, y - 76 * s), (x + 27 * s, y - 84 * s), (x + 30 * s, y - 76 * s)], dark)
    cv.poly([(x + 12 * s, y - 50 * s), (x + 22 * s, y - 74 * s), (x + 17 * s, y - 76 * s), (x + 6 * s, y - 50 * s)], dark)    # mane
    cv.poly([(x - 26 * s, y - 46 * s), (x - 38 * s, y - 30 * s), (x - 30 * s, y - 28 * s)], dark)                              # tail
    cv.rect(x - 8 * s, y - 52 * s, x + 6 * s, y - 44 * s, (176, 40, 44))                 # saddle
    cv.oval(x + 38 * s, y - 71 * s, 1.6 * s, 1.6 * s, (30, 20, 16))


def cabinet(cv, x0, y0, x1, y1, seed):
    """A toy cabinet set in the wall: a dark frame, shelves, and a toy in each pigeonhole."""
    frame = (92, 56, 36)
    inside = (64, 40, 30)
    cv.rect(x0, y0, x1, y1, frame)
    nx = max(2, int((x1 - x0) / 84))
    ny = max(1, int((y1 - y0) / 80))
    cw = (x1 - x0 - 8) / nx
    ch = (y1 - y0 - 8) / ny
    n = seed
    for j in range(ny):
        for i in range(nx):
            ax, ay = x0 + 8 + i * cw, y0 + 8 + j * ch
            bx, by = ax + cw - 8, ay + ch - 8
            cv.vgrad(ax, ay, bx, by, inside, mix(inside, (120, 80, 50), 0.5))
            mx = (ax + bx) / 2
            pick = n % 7
            if pick == 0:
                toy_bear(cv, mx, by, 1.15)
            elif pick == 1:
                toy_drum(cv, mx - 10, by, 1.2)
                toy_ball(cv, mx + 20, by, 10, (60, 130, 190), (236, 200, 80))
            elif pick == 2:
                toy_soldier(cv, mx - 14, by, 1.05)
                toy_soldier(cv, mx + 12, by, 1.05, (40, 110, 80))
            elif pick == 3:
                toy_gift(cv, mx - 14, by, 28, 30, n)
                toy_gift(cv, mx + 16, by, 22, 20, n + 2)
            elif pick == 4:
                toy_blocks(cv, mx - 6, by, 1.2)
            elif pick == 5:
                toy_bear(cv, mx - 12, by, 0.9, (214, 190, 150))
                toy_gift(cv, mx + 18, by, 22, 26, n + 1)
            else:
                toy_ball(cv, mx - 14, by, 13, (196, 60, 50), (250, 240, 220))
                toy_soldier(cv, mx + 14, by, 1.0, (60, 90, 170))
            n += 3
    cv.rect(x0, y0, x1, y0 + 4, mix(frame, (255, 220, 170), 0.3))


def window(cv, box, moon):
    x0, y0, x1, y1 = box
    cv.rect(x0 - 16, y0 - 16, x1 + 16, y1 + 22, FRAME_D)
    cv.rect(x0 - 12, y0 - 12, x1 + 12, y1 + 12, FRAME)
    cv.vgrad(x0, y0, x1, y1, NIGHT_T, NIGHT_B)
    if moon:
        cv.glow(x0 + 52, y0 + 50, 60, 60, (120, 140, 200), 150)
        cv.oval(x0 + 52, y0 + 50, 17, 17, (244, 240, 214))
        cv.oval(x0 + 59, y0 + 45, 14, 14, mix(NIGHT_T, NIGHT_B, 0.25))
    for i in range(9):                                    # stars
        sx = x0 + 10 + h2(i, x0, 1) * (x1 - x0 - 20)
        sy = y0 + 8 + h2(i, x0, 2) * (y1 - y0) * 0.45
        cv.rect(sx, sy, sx + 2, sy + 2, (236, 240, 255), 210)
    hill = [(x0, y1)]                                     # far snowy hills and a few firs
    n = 12
    for i in range(n + 1):
        hx = x0 + (x1 - x0) * i / n
        hill.append((hx, y1 - 34 - 14 * math.sin(i * 0.9 + x0 * 0.01) - 8 * math.sin(i * 2.1)))
    hill.append((x1, y1))
    cv.poly(hill, (150, 176, 220))
    for i in range(4):
        tx = x0 + 22 + i * (x1 - x0 - 44) / 3 + (h2(i, x0, 4) - 0.5) * 18
        ty = y1 - 28 - h2(i, x0, 5) * 10
        for j in range(3):
            cv.poly([(tx - 11 + j * 2.5, ty - j * 11), (tx + 11 - j * 2.5, ty - j * 11), (tx, ty - 17 - j * 11)], (36, 70, 96))
    cv.poly([(x0, y1), (x0, y1 - 22), (x0 + (x1 - x0) * 0.4, y1 - 12), (x1, y1 - 26), (x1, y1)], SNOW)
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):   # frost in the corners
        cv.poly([(cx, cy), (cx + sx * 46, cy), (cx + sx * 30, cy + sy * 10), (cx + sx * 12, cy + sy * 26), (cx, cy + sy * 44)], (226, 240, 255), 150)
        cv.poly([(cx, cy), (cx + sx * 22, cy), (cx, cy + sy * 20)], (244, 250, 255), 200)
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    cv.rect(mx - 4, y0, mx + 4, y1, FRAME)                # the bars
    cv.rect(x0, my - 4, x1, my + 4, FRAME)
    cv.rect(mx + 2, y0, mx + 4, y1, FRAME_D)
    cv.rect(x0, my + 2, x1, my + 4, FRAME_D)
    cv.rect(x0 - 22, y1 + 10, x1 + 22, y1 + 24, mix(FRAME, FRAME_D, 0.55))    # the sill (plain: a white top is a platform's sign)
    cv.rect(x0 - 22, y1 + 20, x1 + 22, y1 + 24, FRAME_D)


def wreath(cv, cx, cy, r):
    for i in range(26):
        a = i * math.tau / 26
        px, py = cx + math.cos(a) * r, cy + math.sin(a) * r
        cv.oval(px, py, r * 0.3, r * 0.3, FIR_D if i % 2 else FIR)
    for i in range(26):
        a = i * math.tau / 26 + 0.12
        px, py = cx + math.cos(a) * r * 0.96, cy + math.sin(a) * r * 0.96
        cv.oval(px, py, r * 0.13, r * 0.13, FIR_L, 200)
    for i in range(7):
        a = i * math.tau / 7 + 0.5
        cv.oval(cx + math.cos(a) * r, cy + math.sin(a) * r, 4.5, 4.5, HOLLY)
    by = cy + r                                            # the bow
    for sgn in (-1, 1):
        cv.poly([(cx, by), (cx + sgn * 26, by - 13), (cx + sgn * 28, by + 9)], (206, 36, 44))
        cv.poly([(cx, by), (cx + sgn * 12, by + 30), (cx + sgn * 3, by + 28)], (170, 26, 36))
    cv.oval(cx, by, 7, 7, (226, 60, 60))


def stocking(cv, x, y, c):
    cv.rect(x - 8, y, x + 8, y + 26, c)
    cv.rrect(x - 8, y + 20, x + 18, y + 36, 7, c)
    cv.rect(x - 10, y, x + 10, y + 8, ICING)
    cv.rect(x - 10, y + 6, x + 10, y + 8, ICING_S)
    cv.oval(x + 12, y + 30, 4, 4, mix(c, (255, 255, 255), 0.5))


def tree(cv, tiers, top_y, floor_y):
    """The big fir behind its boughs: a skirt of needles ending at each tier, lighter on
    top; the trunk and its pot at the floor; baubles, and strings for the lights."""
    cx = W / 2
    cv.rect(cx - 16, tiers[-1][2] - 30, cx + 16, floor_y, (86, 54, 34))        # the trunk (behind the track)
    cv.poly([(cx - 58, floor_y - 62), (cx + 58, floor_y - 62), (cx + 48, floor_y), (cx - 48, floor_y)], (70, 44, 32))   # its tub: dark wood
    cv.rect(cx - 62, floor_y - 68, cx + 62, floor_y - 58, (96, 62, 44))
    cv.rect(cx - 51, floor_y - 30, cx + 51, floor_y - 24, (52, 34, 28))
    prev_y, prev_w = top_y, 14.0
    for i, (x0, x1, y) in enumerate(tiers):
        half = (x1 - x0) / 2 - 8
        y1 = y + 30
        pts = [(cx - prev_w * 0.62, prev_y - 6)]
        n = max(6, int(half / 22))
        for j in range(n + 1):                                # the skirt's hem: scallops
            px = cx + half - 2 * half * j / n
            pts.append((px, y1 + (9 if j % 2 else -3)))
        pts.append((cx + prev_w * 0.62, prev_y - 6))
        pts = [pts[0]] + pts[1:][::-1]
        cv.poly(pts, FIR_D)
        lite = [(cx - prev_w * 0.5, prev_y - 4), (cx + prev_w * 0.5, prev_y - 4), (cx + half * 0.72, y - 14), (cx - half * 0.72, y - 14)]
        cv.poly(lite, mix(FIR_D, FIR, 0.55))
        for j in range(int(half / 13)):                       # needles' shade
            nx = cx - half + 12 + j * (2 * half - 24) / max(1, int(half / 13) - 1)
            t = (prev_y + 12) + h2(j, i, 7) * (y - prev_y - 16)
            lim = prev_w * 0.6 + (half - prev_w * 0.6) * (t - prev_y) / max(1.0, y1 - prev_y)
            if abs(nx - cx) < lim - 8:
                cv.poly([(nx - 7, t), (nx + 7, t), (nx, t + 13)], FIR_K, 150)
        prev_y, prev_w = y, half
    # strings for the lights (the page's bulbs sit on them) and baubles
    prev_y, prev_w = top_y, 14.0
    k = 0
    for i, (x0, x1, y) in enumerate(tiers):
        half = (x1 - x0) / 2 - 8
        for t in (0.42, 0.8):
            yy = prev_y + (y - prev_y) * t
            wd = prev_w * 0.6 + (half * 0.9 - prev_w * 0.6) * t
            cv.arc(cx, yy - 26, wd, 34, 25, 155, (226, 196, 120), 2.0, 180)
        for j in range(2 + i * 2):
            t = 0.3 + 0.6 * h2(j, i, 11)
            yy = prev_y + (y - prev_y) * t
            wd = prev_w * 0.6 + (half * 0.85 - prev_w * 0.6) * t
            bx = cx + (h2(j, i, 12) * 2 - 1) * wd
            col = [(206, 50, 56), (236, 190, 70), (70, 130, 200), (226, 226, 236)][k % 4]
            cv.oval(bx, yy, 7.5, 7.5, col)
            cv.oval(bx - 2.5, yy - 2.5, 2.2, 2.2, (255, 255, 255), 190)
            k += 1
        prev_y, prev_w = y, half


def make_back(rows):
    g = grid_of(rows)
    k = kinds_of(g)
    runs = ledge_runs(g, k)
    cv = Cv(bg=WALL_A)
    floor_y = (ROWS - 2) * C
    # the hall's wall: boards
    x = 0
    i = 0
    while x < W:
        cv.rect(x, 0, x + 60, H, WALL_A if i % 2 else WALL_B)
        cv.rect(x, 0, x + 2, H, WALL_K, 150)
        cv.rect(x + 2, 0, x + 4, H, mix(WALL_A, (255, 230, 190), 0.25), 110)
        for j in range(5):
            ky = 80 + h2(i, j, 21) * 900
            if h2(i, j, 22) < 0.45:
                cv.oval(x + 14 + h2(i, j, 23) * 30, ky, 5, 9, WALL_K, 110)
        x += 60
        i += 1
    # the wings' rooms: wallpaper, each its own
    papers = [[None, ((112, 138, 104), (96, 122, 92)), ((104, 124, 150), (90, 110, 138))],
              [None, ((158, 104, 96), (142, 90, 84)), ((166, 138, 88), (150, 122, 76))]]
    for (x0, y0, x1, y1, side, n) in room_boxes(g, k):
        paper = papers[side][n] if n < 3 else None
        if paper is None or y1 > floor_y - 100 and n >= 3:
            continue
        cv.rect(x0, y0, x1, y1, paper[0])
        xx = x0
        j = 0
        while xx < x1:                                    # stripes
            if j % 2:
                cv.rect(xx, y0, min(x1, xx + 20), y1, paper[1])
            xx += 20
            j += 1
        cv.rect(x0, y0, x1, y0 + 26, mix(paper[1], (40, 24, 16), 0.45), 200)     # shade under the floor above
        cv.rect(x0, y1 - 26, x1, y1 - 20, FRAME_D)        # a skirting board
        cv.rect(x0, y1 - 20, x1, y1, mix(FRAME_D, (60, 40, 30), 0.5))
    # the wainscot behind the track
    wy = floor_y - 180
    cv.rect(0, wy, W, floor_y, WAINSCOT)
    cv.rect(0, wy, W, wy + 8, WAINSCOT_L)
    cv.rect(0, wy + 8, W, wy + 12, WAINSCOT_D)
    x = 30
    while x < W:
        cv.rect(x, wy + 28, x + 96, floor_y - 18, WAINSCOT_D)
        cv.rect(x + 5, wy + 33, x + 91, floor_y - 23, mix(WAINSCOT, WAINSCOT_L, 0.35))
        x += 120
    # the rafters' shade up top
    cv.shade(0, 60, W, 200, (40, 24, 16), 130, 0)
    # ---- the two windows, and a wreath between them
    for i, box in enumerate(WINDOWS):
        window(cv, box, i == 0)
    wreath(cv, 915, 128, 44)
    # ---- ropes for the ledges that hang (the bridge, the rafter)
    for (c0, c1, r, kind) in runs:
        if kind != L_SHELF or r > 12 or g[r, c0 - 1] == SOLID or g[r, (c1 + 1) % COLS] == SOLID:
            continue
        for rx in (c0 * C + 22, (c1 + 1) * C - 22):
            cv.rect(rx - 2, 60, rx + 2, r * C + 4, (196, 164, 110))
            y = 64
            while y < r * C:
                cv.rect(rx - 2, y, rx + 2, y + 2, (130, 100, 60))
                y += 8
    # ---- the tree
    tiers = sorted([(c0 * C, (c1 + 1) * C, r * C) for (c0, c1, r, kind) in runs if kind == L_BOUGH and abs((c0 + c1 + 1) - COLS) <= 1],
                   key=lambda t: t[2])
    by_drum = [(c0 * C, (c1 + 1) * C, r * C) for (c0, c1, r, kind) in runs if kind == L_BOUGH and abs((c0 + c1 + 1) - COLS) > 1]
    if by_drum:                                           # the top boughs, in two parts beside the drum
        tiers = [(min(t[0] for t in by_drum), max(t[1] for t in by_drum), by_drum[0][2])] + tiers
    if tiers:
        cv.glow(W / 2, 640, 520, 420, (60, 50, 20), 120)
        tree(cv, tiers, TREE_TOP, floor_y)
    # ---- the fireplace under the mantel: bricks, the dark firebox, logs, stockings
    fx0, fy0, fx1, fy1 = FIRE
    cv.rect(fx0 - 30, 60, fx1 - 30, fy0 - 36, BRICK_D)                       # the chimney breast, up to the pot
    y = 64
    i = 0
    while y < fy0 - 40:
        xx = fx0 - 30 - (12 if i % 2 else 0)
        while xx < fx1 - 30:
            a, b = max(fx0 - 30, xx), min(fx1 - 30, xx + 22)
            if b > a:
                cv.rect(a, y, b, y + 10, mix(BRICK, BRICK_D, 0.35 + 0.3 * h2(xx, y, 3)))
            xx += 24
        y += 12
        i += 1
    cv.rect(fx0 - 50, fy0 - 6, fx1 + 50, fy1, BRICK)
    y = fy0 - 4
    i = 0
    while y < fy1:
        xx = fx0 - 50 - (12 if i % 2 else 0)
        while xx < fx1 + 50:
            a, b = max(fx0 - 50, xx), min(fx1 + 50, xx + 22)
            if b > a:
                cv.rect(a, y, b, y + 10, mix(BRICK_L, BRICK_D, 0.2 + 0.5 * h2(xx, y, 5)))
            xx += 24
        y += 12
        i += 1
    cv.glow((fx0 + fx1) / 2, fy1 - 10, 300, 200, (120, 60, 14), 170)
    cv.rrect(fx0, fy0, fx1, fy1 + 12, 26, (30, 12, 10))
    cv.rect(fx0, fy0 + 40, fx1, fy1, (30, 12, 10))
    cv.glow((fx0 + fx1) / 2, fy1 - 8, 96, 60, (255, 120, 30), 220)
    for (lx, lw) in ((fx0 + 34, 70), (fx0 + 78, 76)):                         # the logs
        cv.rrect(lx, fy1 - 16, lx + lw, fy1 - 3, 6, (92, 52, 30))
        cv.oval(lx + lw - 4, fy1 - 9.5, 5, 6.5, (176, 120, 70))
    for i, sx in enumerate((fx0 - 38, fx0 - 14, fx1 + 14, fx1 + 38)):
        stocking(cv, sx, fy0 - 4, [(196, 40, 46), (30, 120, 76)][i % 2])
    # (the page draws the flames over the logs; then the fire guard, client/workshop_view.gd)
    # ---- the gift chute: a tin pipe down from its mouth, the slide, the bin
    (cx0, cy0), (cx1, cy1) = CHUTE
    cv.vgrad(cx0 - 28, 60, cx0 + 28, cy0 + 6, TIN_D, mix(TIN, TIN_D, 0.4))
    cv.rect(cx0 - 28, 60, cx0 - 22, cy0 + 6, mix(TIN_L, TIN, 0.4))
    y = 96
    while y < cy0:
        cv.rect(cx0 - 30, y, cx0 + 30, y + 9, (170, 44, 48))
        y += 62
    dx, dy = cx1 - cx0, cy1 - cy0
    ln = math.hypot(dx, dy)
    ux, uy = dx / ln, dy / ln
    nx_, ny_ = -uy, ux                                    # the slide's own "down"
    if ny_ < 0:
        nx_, ny_ = -nx_, -ny_
    a0 = (cx0 + 26, cy0 - 14)
    a1 = (cx1 - ux * 6, cy1 - uy * 6)
    cv.poly([a0, a1, (a1[0] + nx_ * 26, a1[1] + ny_ * 26), (a0[0] + nx_ * 26, a0[1] + ny_ * 26)], mix(TIN, TIN_D, 0.55))
    cv.line([(a0[0] + nx_ * 26, a0[1] + ny_ * 26), (a1[0] + nx_ * 26, a1[1] + ny_ * 26)], (60, 70, 86), 5)
    cv.line([a0, a1], TIN_L, 3)
    n = int(ln / 40)
    for i in range(1, n):                                 # its rollers
        px, py = a0[0] + (a1[0] - a0[0]) * i / n, a0[1] + (a1[1] - a0[1]) * i / n
        cv.oval(px + nx_ * 16, py + ny_ * 16, 5, 5, (70, 80, 96))
        cv.oval(px + nx_ * 16, py + ny_ * 16, 2, 2, TIN_L)
    for t in (0.3, 0.72):                                 # brackets to the wall
        px, py = a0[0] + (a1[0] - a0[0]) * t, a0[1] + (a1[1] - a0[1]) * t
        cv.rect(px - 4, py + 22, px + 4, py + 60, (70, 60, 60))
    bx0, by0 = cx1 - 62, cy1 + 4                          # the bin the presents drop in
    cv.poly([(bx0, by0), (bx0 + 96, by0), (bx0 + 86, by0 + 52), (bx0 + 10, by0 + 52)], (30, 110, 72))
    cv.rect(bx0 - 4, by0 - 4, bx0 + 100, by0 + 8, (44, 140, 92))
    cv.poly(star_pts(bx0 + 48, by0 + 30, 14, 6), GOLD)
    toy_gift(cv, bx0 + 30, by0 - 2, 26, 22, 0)
    toy_gift(cv, bx0 + 62, by0 - 2, 22, 28, 2)
    # ---- toy cabinets in the wings' rooms, a rocking horse on the workshop's wall
    for (x0, y0, x1, y1, side, n) in room_boxes(g, k):
        if n == 2 and side == 0:
            cabinet(cv, x0 + 96, y0 + 14, x1 - 60, y1 - 34, 1)
        elif n == 1 and side == 1:
            cabinet(cv, x0 + 70, y0 + 14, x1 - 76, y1 - 34, 4)
        elif n == 2 and side == 1:
            px0, py0, px1, py1 = x0 + 150, y0 + 16, x1 - 130, y1 - 96           # a board of tools
            cv.rect(px0, py0, px1, py1, (120, 84, 54))
            cv.rect(px0 + 5, py0 + 5, px1 - 5, py1 - 5, (176, 140, 96))
            hx = px0 + 30                                                       # a hammer, a saw, a brush
            cv.rect(hx - 3, py0 + 24, hx + 3, py1 - 14, (130, 86, 50))
            cv.rect(hx - 14, py0 + 16, hx + 14, py0 + 30, (90, 96, 110))
            sx = px0 + 78
            cv.poly([(sx, py0 + 22), (sx + 56, py0 + 30), (sx + 56, py0 + 44), (sx, py0 + 40)], (150, 160, 176))
            cv.rect(sx - 16, py0 + 20, sx + 2, py0 + 44, (150, 70, 40))
            bx = px1 - 26
            cv.rect(bx - 3, py0 + 16, bx + 3, py0 + 52, (150, 100, 60))
            cv.rect(bx - 6, py0 + 52, bx + 6, py0 + 70, (206, 60, 56))
            toy_horse(cv, x0 + 250, y1 - 28, 1.1)
            toy_blocks(cv, x0 + 120, y1 - 28, 1.4)
    # ---- the workbenches' legs, the wall brackets of the shelves that touch no wall
    for (c0, c1, r, kind) in runs:
        x0, x1, y = c0 * C, (c1 + 1) * C, r * C
        if kind == L_BENCH:
            for lx in (x0 + 12, x1 - 22):
                cv.rect(lx, y + 12, lx + 10, floor_y, (86, 52, 32))
                cv.rect(lx, y + 12, lx + 3, floor_y, (124, 80, 50))
            cv.rect(x0 + 12, y + 50, x1 - 12, y + 56, (86, 52, 32))
        elif kind == L_SHELF and r > 12 and g[r, c0 - 1] != SOLID and g[r, (c1 + 1) % COLS] != SOLID:
            for bx in (x0 + 34, x1 - 34):
                cv.poly([(bx - 5, y + 10), (bx + 5, y + 10), (bx + 5, y + 16), (bx, y + 34), (bx - 5, y + 16)], (76, 48, 32))
    # ---- a crossing sign by each tunnel mouth (its lamps are on the arch: the page lights them)
    for side in (0, 1):
        px = 75 if side == 0 else W - 75
        cv.rect(px - 4, floor_y - 150, px + 4, floor_y, (206, 206, 214))
        y = floor_y - 150
        j = 0
        while y < floor_y:
            if j % 2:
                cv.rect(px - 4, y, px + 4, min(floor_y, y + 16), (60, 60, 70))
            y += 16
            j += 1
        for sgn in (-1, 1):
            cv.line([(px - 24, floor_y - 150 - sgn * 17), (px + 24, floor_y - 150 + sgn * 17)], (176, 36, 40), 12)
            cv.line([(px - 22, floor_y - 150 - sgn * 15.5), (px + 22, floor_y - 150 + sgn * 15.5)], (244, 240, 232), 7)
    # ---- what is behind the openings: the tunnels, the night in the windows of the side
    # walls, the chute and the chimney, the shafts under the trapdoors
    for r in range(ROWS):
        for c in (0, 1, COLS - 2, COLS - 1):
            if g[r, c] != EMPTY:
                continue
            x0, y0 = c * C, r * C
            if r >= ROWS - 6:
                cv.rect(x0, y0, x0 + C, y0 + C, (22, 15, 18))
            else:
                t0 = (r % 4) / 4.0
                cv.vgrad(x0, y0, x0 + C, y0 + C, mix(NIGHT_T, NIGHT_B, (r - 15) / 4.0), mix(NIGHT_T, NIGHT_B, (r - 14) / 4.0))
                if g[r + 1, c] != EMPTY:
                    cv.oval(x0 + 15, y0 + 30, 26, 11, SNOW)
    for c in range(COLS):
        for r in (0, 1, ROWS - 2, ROWS - 1):
            if g[r, c] == SOLID:
                continue
            x0, y0 = c * C, r * C
            if r < 2:
                cv.rect(x0, y0, x0 + C, y0 + C, (44, 52, 62) if c < COLS // 2 else (34, 22, 20))
            else:
                cv.vgrad(x0, y0, x0 + C, y0 + C, (40, 26, 22), (14, 9, 10))
    for (c0, c1, r, kind) in runs:                        # under each trapdoor: two arrows down (you can drop through it)
        if kind != L_TRAP:
            continue
        for ax in (c0 * C + 34, (c1 + 1) * C - 34):
            for ay in (r * C + 22, r * C + 36):
                cv.line([(ax - 13, ay), (ax, ay + 10), (ax + 13, ay)], (236, 214, 170), 4.5)
    # ---- out of focus, quieter and a little dimmer than the platforms
    img = cv.img.filter(ImageFilter.GaussianBlur(1.7 * SS))
    arr = np.asarray(img, dtype=np.float32)
    flat = np.asarray(WALL_A, dtype=np.float32)[None, None, :]
    arr = (arr * 0.86 + flat * 0.14) * BACK_DIM
    yy = np.linspace(0.0, 1.0, arr.shape[0])[:, None, None]
    xx = np.linspace(-1.0, 1.0, arr.shape[1])[None, :, None]
    arr *= 1.0 - 0.10 * xx * xx - 0.06 * (yy - 0.5) ** 2
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    return out.resize((W // 2, H // 2), Image.LANCZOS)


BACK_DIM = 0.78                  # the room behind is this much dimmer than it is painted


# ================================================================ the moving parts
# name: (x, y, w, h) in workshop_parts.png. The engine and the wagons face right and
# stand on the sheet's rows with the rail GROUND px under each box's top; the page's
# copy of this table is client/workshop_view.gd PARTS.
PARTS = {"engine": (0, 0, 120, 80), "wagon_a": (120, 0, 80, 80), "wagon_b": (200, 0, 80, 80),
         "wheel_big": (280, 0, 28, 28), "wheel_small": (280, 28, 22, 22), "lamp_on": (280, 50, 20, 20),
         "gift_0": (308, 0, 16, 16), "gift_1": (324, 0, 16, 16), "gift_2": (340, 0, 16, 16),
         "lantern": (356, 0, 32, 44)}
SHEET = (512, 128)
GROUND = 76                      # the rail's top in the engine's and the wagons' boxes
CAR_Z = 1.2                      # the engine and the wagons are painted in a 62 px high design, this much bigger
PS = 4                           # the parts are drawn this many times too big


class Zoom:
    """A canvas seen through a lens: what is drawn at (x, y) lands z times as far from
    (ox, oy), around (to_x, to_y). The engine and the wagons are painted through one."""

    def __init__(self, cv, ox, oy, to_x, to_y, z):
        self.cv, self.ox, self.oy, self.tx, self.ty, self.z = cv, ox, oy, to_x, to_y, z

    def _x(self, x):
        return self.tx + (x - self.ox) * self.z

    def _y(self, y):
        return self.ty + (y - self.oy) * self.z

    def rect(self, x0, y0, x1, y1, c, a=255):
        self.cv.rect(self._x(x0), self._y(y0), self._x(x1), self._y(y1), c, a)

    def rrect(self, x0, y0, x1, y1, rad, c, a=255):
        self.cv.rrect(self._x(x0), self._y(y0), self._x(x1), self._y(y1), rad * self.z, c, a)

    def poly(self, pts, c, a=255):
        self.cv.poly([(self._x(x), self._y(y)) for (x, y) in pts], c, a)

    def line(self, pts, c, w, a=255):
        self.cv.line([(self._x(x), self._y(y)) for (x, y) in pts], c, w * self.z, a)

    def oval(self, cx, cy, rx, ry, c, a=255):
        self.cv.oval(self._x(cx), self._y(cy), rx * self.z, ry * self.z, c, a)

    def arc(self, cx, cy, rx, ry, a0, a1, c, w, a=255):
        self.cv.arc(self._x(cx), self._y(cy), rx * self.z, ry * self.z, a0, a1, c, w * self.z, a)


def paint_engine(cv, ox, oy):
    """The toy engine, facing right, in its design: its rail 62 px under oy, its front
    (the cowcatcher's tip) at x 92; its wheels are the page's."""
    g0 = oy + 62
    red, red_d, red_l = (216, 42, 48), (150, 24, 34), (250, 110, 104)
    grn, grn_d, grn_l = (34, 140, 86), (18, 92, 58), (96, 196, 136)
    blk = (36, 34, 44)
    cv.rect(ox + 12, g0 - 14, ox + 82, g0 - 8, blk)                            # the frame
    cv.poly([(ox + 80, g0 - 14), (ox + 92, g0 - 1), (ox + 78, g0 - 1), (ox + 76, g0 - 8)], GOLD)   # the cowcatcher
    cv.line([(ox + 82, g0 - 11), (ox + 87, g0 - 2)], GOLD_D, 1.4)
    cv.line([(ox + 79, g0 - 9), (ox + 82, g0 - 2)], GOLD_D, 1.4)
    cv.rrect(ox + 30, g0 - 40, ox + 78, g0 - 14, 9, red_d)                     # the boiler
    cv.rrect(ox + 31, g0 - 39, ox + 77, g0 - 17, 8, red)
    cv.rrect(ox + 34, g0 - 37, ox + 72, g0 - 32, 2.5, red_l)
    for bx in (44, 60):                                                       # its brass bands
        cv.rect(ox + bx, g0 - 40, ox + bx + 4, g0 - 14, GOLD)
        cv.rect(ox + bx + 3, g0 - 40, ox + bx + 4, g0 - 14, GOLD_D)
    cv.rrect(ox + 72, g0 - 40, ox + 82, g0 - 14, 4, blk)                       # the smokebox
    cv.oval(ox + 83, g0 - 30, 5, 5, GOLD_D)                                    # the lamp
    cv.oval(ox + 83.5, g0 - 30, 3.6, 3.6, (255, 244, 170))
    cv.rect(ox + 62, g0 - 54, ox + 72, g0 - 38, blk)                           # the funnel
    cv.poly([(ox + 59, g0 - 58), (ox + 75, g0 - 58), (ox + 72, g0 - 51), (ox + 62, g0 - 51)], blk)
    cv.rect(ox + 59, g0 - 60, ox + 75, g0 - 57, GOLD)
    cv.rect(ox + 62, g0 - 46, ox + 72, g0 - 43, CANE_R)
    cv.oval(ox + 51, g0 - 40, 6, 6, GOLD)                                      # the dome
    cv.oval(ox + 49.5, g0 - 42, 2, 2, GOLD_L)
    cv.rect(ox + 10, g0 - 46, ox + 34, g0 - 14, grn_d)                         # the cab
    cv.rect(ox + 12, g0 - 44, ox + 32, g0 - 14, grn)
    cv.rect(ox + 12, g0 - 44, ox + 15, g0 - 14, grn_l)
    cv.rect(ox + 15, g0 - 40, ox + 29, g0 - 26, GOLD_K)                        # its window
    cv.rect(ox + 16.5, g0 - 38.5, ox + 27.5, g0 - 27.5, (255, 240, 170))
    cv.rect(ox + 7, g0 - 50, ox + 37, g0 - 45, red_d)                          # its roof
    cv.rect(ox + 7, g0 - 50, ox + 37, g0 - 48, red)
    cv.rect(ox + 12, g0 - 22, ox + 32, g0 - 19, GOLD)


def paint_wagon(cv, ox, oy, which):
    """A wagon of presents in its design: its rail 62 px under oy, 56 px long from x 4 to
    60; its wheels are the page's."""
    g0 = oy + 62
    body, dark, lite = ((34, 140, 86), (18, 92, 58), (96, 196, 136)) if which == 0 else ((216, 42, 48), (150, 24, 34), (250, 110, 104))
    blk = (36, 34, 44)
    # the load first: it stands in the wagon
    if which == 0:
        toy_gift(cv, ox + 18, g0 - 24, 20, 18, 2)
        toy_gift(cv, ox + 42, g0 - 24, 22, 23, 0)
        toy_gift(cv, ox + 30, g0 - 24, 14, 12, 5)
    else:
        toy_bear(cv, ox + 20, g0 - 22, 0.62)
        toy_gift(cv, ox + 44, g0 - 24, 20, 20, 3)
        toy_gift(cv, ox + 33, g0 - 24, 12, 11, 1)
    cv.rect(ox + 4, g0 - 12, ox + 60, g0 - 8, blk)                             # the frame
    cv.rrect(ox + 4, g0 - 28, ox + 60, g0 - 11, 3, dark)                       # the box
    cv.rect(ox + 6, g0 - 26, ox + 58, g0 - 13, body)
    cv.rect(ox + 6, g0 - 26, ox + 58, g0 - 23, lite)
    cv.rect(ox + 4, g0 - 30, ox + 60, g0 - 27, GOLD)
    for px in (17, 31, 45):
        cv.rect(ox + px, g0 - 26, ox + px + 2, g0 - 13, dark)


def paint_wheel(cv, ox, oy, size):
    r = size / 2.0
    cx, cy = ox + r, oy + r
    cv.oval(cx, cy, r - 0.5, r - 0.5, (36, 34, 44))
    cv.oval(cx, cy, r - 2.5, r - 2.5, GOLD)
    cv.oval(cx, cy, r - 4.5, r - 4.5, (170, 30, 40))
    for i in range(4):                                                         # spokes: the turning shows
        a = i * math.pi / 4
        cv.line([(cx - math.cos(a) * (r - 3), cy - math.sin(a) * (r - 3)), (cx + math.cos(a) * (r - 3), cy + math.sin(a) * (r - 3))], GOLD, 1.5)
    cv.oval(cx, cy, 2.6, 2.6, (36, 34, 44))
    cv.oval(cx + (r - 5.5), cy, 1.8, 1.8, (36, 34, 44))                        # the rod's pin


def paint_lantern(cv, ox, oy):
    iron = (44, 36, 36)
    cx = ox + 16
    cv.rect(cx - 7, oy + 2, cx + 7, oy + 4, iron)                              # the handle
    cv.rect(cx - 7, oy + 2, cx - 5, oy + 9, iron)
    cv.rect(cx + 5, oy + 2, cx + 7, oy + 9, iron)
    cv.poly([(cx - 9, oy + 13), (cx + 9, oy + 13), (cx + 6, oy + 8), (cx - 6, oy + 8)], iron)
    cv.rrect(cx - 10, oy + 13, cx + 10, oy + 38, 3, (255, 214, 120))           # the glass
    cv.rrect(cx - 6, oy + 18, cx + 6, oy + 36, 4, (255, 240, 180))
    cv.poly([(cx, oy + 20), (cx + 4, oy + 31), (cx, oy + 35), (cx - 4, oy + 31)], (255, 255, 236))
    cv.rect(cx - 11, oy + 13, cx - 9, oy + 38, iron)
    cv.rect(cx + 9, oy + 13, cx + 11, oy + 38, iron)
    cv.rect(cx - 1, oy + 13, cx + 1, oy + 17, iron)
    cv.rect(cx - 13, oy + 37, cx + 13, oy + 42, iron)


def make_parts():
    cv = Cv(SHEET[0], SHEET[1], (0, 0, 0), PS, cover=True)
    x, y, w, h = PARTS["engine"]
    paint_engine(Zoom(cv, 0, 62, x, y + GROUND, CAR_Z), 0, 0)
    for i, name in enumerate(("wagon_a", "wagon_b")):
        x, y, w, h = PARTS[name]
        paint_wagon(Zoom(cv, 0, 62, x, y + GROUND, CAR_Z), 0, 0, i)
    for name in ("wheel_big", "wheel_small"):
        x, y, w, h = PARTS[name]
        paint_wheel(cv, x, y, w)
    x, y, w, h = PARTS["lamp_on"]                                               # a signal lamp, lit
    cv.oval(x + 10, y + 10, 9.5, 9.5, (120, 20, 24))
    cv.oval(x + 10, y + 10, 8, 8, (255, 60, 50))
    cv.oval(x + 10, y + 10, 5, 5, (255, 170, 130))
    cv.oval(x + 8, y + 8, 2.2, 2.2, (255, 250, 240))
    for i in range(3):
        x, y, w, h = PARTS["gift_%d" % i]
        paper, ribbon = PAPERS[[0, 2, 1][i]]
        cv.rect(x + 1, y + 2, x + 15, y + 15, mix(paper, (0, 0, 0), 0.35))
        cv.rect(x + 2, y + 3, x + 14, y + 14, paper)
        cv.rect(x + 6.5, y + 3, x + 9.5, y + 14, ribbon)
        cv.rect(x + 2, y + 7, x + 14, y + 9.5, ribbon)
    x, y, w, h = PARTS["lantern"]
    paint_lantern(cv, x, y)
    # a dark rim round the engine and the wagons (their boxes have room for it), so they
    # stand out on any wall
    box = (0, 0, 280 * PS, 80 * PS)
    car = cv.alpha.crop(box)
    rim = car.filter(ImageFilter.MaxFilter(2 * int(1.5 * PS) + 1))
    under = Image.new("RGB", car.size, (30, 24, 34))
    under.paste(cv.img.crop(box), (0, 0), car)
    cv.img.paste(under, box[:2])
    cv.alpha.paste(rim, box[:2])
    alpha = np.asarray(cv.alpha, dtype=np.float32) / 255.0
    rgb = np.asarray(cv.img, dtype=np.float32) * alpha[:, :, None]
    size = SHEET
    small_a = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8), "L").resize(size, Image.LANCZOS), dtype=np.float32) / 255.0
    small = np.asarray(Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").resize(size, Image.LANCZOS), dtype=np.float32)
    out = np.where(small_a[:, :, None] > 0.003, small / np.maximum(small_a[:, :, None], 0.003), 0.0)
    return Image.fromarray(np.dstack([np.clip(out, 0, 255), small_a * 255]).astype(np.uint8), "RGBA")


# ================================================================ the preview
TEAM = [(232, 65, 60), (60, 140, 232), (95, 211, 90), (242, 194, 48), (168, 90, 232), (240, 138, 44), (53, 214, 208), (240, 106, 168)]
ROOM = (0.93, 0.88, 0.82)        # the room's light (client/workshop_view.gd DARK)


# The train's cars, front to back: (part, its length on the track, where its front is in
# its box, its wheels (x in the box, radius, part)). 92 + 6 + 68 + 6 + 68 = 240 px: sim/workshop.gd
# TRAIN_LEN. The page's copy is client/workshop_view.gd CARS.
CARS = [("engine", 92.0, 110.4, [(26.4, 14.0, "wheel_big"), (55.2, 14.0, "wheel_big"), (80.4, 11.0, "wheel_small")]),
        ("wagon_a", 68.0, 72.0, [(19.2, 11.0, "wheel_small"), (57.6, 11.0, "wheel_small")]),
        ("wagon_b", 68.0, 72.0, [(19.2, 11.0, "wheel_small"), (57.6, 11.0, "wheel_small")])]
CAR_GAP = 6.0


def part(parts, name):
    x, y, w, h = PARTS[name]
    return parts.crop((x, y, x + w, y + h))


def paste_train(img, parts, front_x, floor_y, way=1, turn=0.0):
    """The train with its front at front_x, heading way (1 right)."""
    x = front_x
    for name, ln, box_front, wheels in CARS:
        spr = part(parts, name)
        if way < 0:
            spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
            ox = x - (spr.width - box_front)
        else:
            ox = x - box_front
        img.alpha_composite(spr, (int(round(ox)), int(floor_y - GROUND)))
        for (wx, wr, wname) in wheels:
            wh = part(parts, wname).rotate(turn, resample=Image.BICUBIC)
            cx = x + way * (wx - box_front)
            img.alpha_composite(wh, (int(round(cx - wh.width / 2)), int(round(floor_y - wr - wh.height / 2))))
        x -= way * (ln + CAR_GAP)


def preview(back, front, parts, rows, path):
    spots, lights = marks(rows)
    b = np.asarray(back.resize((W, H), Image.BILINEAR), dtype=np.float32) / 255.0
    f = np.asarray(front.resize((W, H), Image.BILINEAR), dtype=np.float32) / 255.0
    a = f[:, :, 3:4]
    lit = b * (1 - a) + f[:, :, :3] * a
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    light = np.ones((H, W, 3), dtype=np.float32) * np.asarray(ROOM, dtype=np.float32)[None, None, :]
    for i, (lx, ly) in enumerate(lights):                 # the lanterns' and the fire's light (about what the page's LOW look adds)
        d = np.sqrt((xx - lx) ** 2 + (yy - ly) ** 2)
        k = np.clip(1.0 - d / 330.0, 0.0, 1.0) ** 2
        light += k[:, :, None] * np.asarray((0.30, 0.20, 0.10), dtype=np.float32)[None, None, :]
    img = Image.fromarray((np.clip(lit * light, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")
    img.resize((400, 225), Image.LANCZOS).convert("RGB").save(os.path.join(path, "workshop_card.png"))
    floor_y = (ROWS - 2) * C
    d = ImageDraw.Draw(img, "RGBA")
    # the tree's lights, the fire, the windows' snow, the signal: about as the page draws them
    for i in range(34):
        t = h2(i, 3, 1)
        y = TREE_TOP + 20 + t * (floor_y - 150 - TREE_TOP)
        half = 20 + (y - TREE_TOP) / (floor_y - 120 - TREE_TOP) * 280
        x = W / 2 + (h2(i, 5, 2) * 2 - 1) * half
        c = [(255, 220, 120), (255, 110, 100), (130, 200, 255), (150, 255, 170)][i % 4]
        d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=c + (70,))
        d.ellipse([x - 3.5, y - 3.5, x + 3.5, y + 3.5], fill=c + (255,))
    fx0, fy0, fx1, fy1 = FIRE
    for i in range(5):
        px = fx0 + 40 + i * 25
        hh = 34 + 14 * math.sin(i * 2.1)
        d.polygon([(px - 14, fy1 - 4), (px, fy1 - 4 - hh), (px + 14, fy1 - 4)], fill=(255, 150, 40, 235))
        d.polygon([(px - 7, fy1 - 4), (px, fy1 - 4 - hh * 0.6), (px + 7, fy1 - 4)], fill=(255, 236, 150, 255))
    for (x0, y0, x1, y1) in WINDOWS:
        for i in range(26):
            sx, sy = x0 + h2(i, x0, 31) * (x1 - x0), y0 + h2(i, x0, 32) * (y1 - y0)
            d.rectangle([sx, sy, sx + 3, sy + 3], fill=(255, 255, 255, 230))
    for (lx, ly) in lights[2:]:
        img.alpha_composite(part(parts, "lantern"), (int(lx - 16), int(ly - 22)))
    # the train on its way right, the signal by its mouth still lit
    for i in range(3):                                    # a puff of steam behind the funnel
        d.ellipse([1066 - i * 34 - 16 - i * 5, floor_y - 104 - i * 14 - 16 - i * 5, 1066 - i * 34 + 16 + i * 5, floor_y - 104 - i * 14 + 16 + i * 5],
                  fill=(255, 255, 255, 150 - i * 40))
    paste_train(img, parts, 1160, floor_y, 1, 20.0)
    for j in range(2):
        img.alpha_composite(part(parts, "lamp_on"), (44 - 10, floor_y - 121 + j * 15 - 10))
    # stand-in fighters: one on each spawn spot, more on the floor, a bench and a bough
    extra = [(300, floor_y), (1240, floor_y), (560, floor_y - 90), (1380, 900 - 0), (850, 900), (1700, floor_y)]
    for i, (sx, sy) in enumerate(spots + extra):
        c = TEAM[i % 8]
        d.rounded_rectangle([sx - 21, sy - 66, sx + 21, sy + 3], radius=9, fill=(255, 255, 255, 235))
        d.rounded_rectangle([sx - 18, sy - 63, sx + 18, sy], radius=7, fill=c + (255,))
        d.rounded_rectangle([sx - 18, sy - 63, sx + 18, sy - 40], radius=7, fill=tuple(min(255, int(v * 1.15)) for v in c) + (255,))
        d.rectangle([sx - 9, sy - 52, sx - 4, sy - 46], fill=(20, 20, 30, 255))
        d.rectangle([sx + 4, sy - 52, sx + 9, sy - 46], fill=(20, 20, 30, 255))
    for (ax, ay, ang) in ((700, 520, -0.3), (1280, 420, 2.9), (980, 980, 0.1)):   # arrows in the air
        dx, dy = math.cos(ang) * 30, math.sin(ang) * 30
        d.line([(ax - dx, ay - dy), (ax + dx, ay + dy)], fill=(255, 250, 235, 255), width=5)
        d.line([(ax - dx, ay - dy), (ax + dx * 0.4, ay + dy * 0.4)], fill=(150, 100, 60, 255), width=3)
    img = img.convert("RGB")
    img.save(os.path.join(path, "workshop_preview.png"))
    img.resize((693, 390), Image.LANCZOS).save(os.path.join(path, "workshop_preview_phone.png"))


def main():
    rows = read_map()
    front = make_front(rows)
    back = make_back(rows)
    parts = make_parts()
    os.makedirs(OUT, exist_ok=True)
    back.save(os.path.join(OUT, "workshop_back.png"), optimize=True)
    front.save(os.path.join(OUT, "workshop_front.png"), optimize=True)
    parts.save(os.path.join(OUT, "workshop_parts.png"), optimize=True)
    for name in ("workshop_back.png", "workshop_front.png", "workshop_parts.png"):
        print("%s: %d bytes" % (name, os.path.getsize(os.path.join(OUT, name))))
    if "--preview" in sys.argv:
        path = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(path, exist_ok=True)
        preview(back, front, parts, rows, path)
        print("preview: %s" % path)


if __name__ == "__main__":
    main()
