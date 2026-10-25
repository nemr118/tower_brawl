#!/usr/bin/env python3
"""THE BOILER ROOM's art (bench/sim/level.gd layout 4, theme "nightmare"), made here, never by hand.

Pixel art at half the arena's size (960 x 540; the page draws it twice as big). It reads the
map from bench/sim/level.gd, so the blocks and ledges are painted where the map has them.

    python3 tools/make_boiler_art.py            (needs Pillow and numpy)

writes bench/assets/:
  boiler_back.png     the back wall: bricks, pipes and gauges, an old boiler, a fan, claw marks
  boiler_front.png    the blocks and ledges: riveted steel walls, the great boiler and its firebox,
                      the furnaces, grating catwalks and pipe walkways, the beds, the lockers' insides
  boiler_front_n.png  its normal map (the bulbs and the fire catch the rivets and seams)
  boiler_parts.png    the moving parts (client/boiler_view.gd PARTS): the hook, chain links, a
                      locker door, hands, the tall shadow, a caged bulb, a valve wheel
An original look made for the game: no film's pictures are copied.
"""
import math
import os
import random
import re

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVEL = os.path.join(ROOT, "bench", "sim", "level.gd")
OUT = os.path.join(ROOT, "bench", "assets")
W, H = 960, 540
C = 15                    # a map cell (30 px) in art pixels
COLS, ROWS = 64, 36

# ---------------------------------------------------------------- the palette
BRICK = [(74, 31, 24), (82, 35, 26), (66, 28, 22), (90, 40, 29), (58, 25, 20), (78, 38, 30)]
MORTAR = (26, 13, 11)
STEEL_K = (18, 19, 23)
STEEL_D = (34, 36, 43)
STEEL = (54, 57, 66)
STEEL_M = (72, 76, 86)
STEEL_L = (100, 105, 116)
STEEL_H = (146, 150, 158)
RUST_D = (70, 36, 22)
RUST = (112, 58, 30)
RUST_L = (156, 86, 42)
BRASS_D = (94, 66, 26)
BRASS = (154, 114, 46)
BRASS_L = (210, 172, 88)
RED = (156, 34, 28)
RED_D = (104, 22, 20)
GREEN = (36, 100, 54)
GREEN_D = (22, 64, 36)
IRON_K = (14, 12, 14)
IRON_D = (28, 24, 26)
IRON = (46, 40, 42)
IRON_L = (78, 68, 64)
SOOT = (12, 9, 9)
SHEET = (196, 188, 170)
SHEET_D = (150, 140, 124)
SHEET_K = (104, 96, 86)
LOCKER_D = (52, 70, 64)
LOCKER = (84, 108, 96)
LOCKER_L = (124, 150, 134)
FLESH = (176, 182, 196)
FLESH_D = (118, 124, 142)


def read_map():
    src = open(LEVEL).read()
    i = src.index('"name": "THE BOILER ROOM"')
    j = src.index('"map": [', i)
    k = src.index("]}", j)
    rows = re.findall(r'"([#=.0-9a-h]{64})"', src[j:k])
    assert len(rows) == ROWS, len(rows)
    return rows


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c[:3])


class Art:
    """A picture and its height map (for the normal map), drawn together."""

    def __init__(self, w, h, bg=(0, 0, 0, 0)):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), bg)
        self.hgt = Image.new("L", (w, h), 0)
        self.d = ImageDraw.Draw(self.img)
        self.hd = ImageDraw.Draw(self.hgt)

    def rect(self, x0, y0, x1, y1, c, hg=None):
        if x1 < x0 or y1 < y0:
            return
        self.d.rectangle([x0, y0, x1, y1], fill=c + (255,) if len(c) == 3 else c)
        if hg is not None:
            self.hd.rectangle([x0, y0, x1, y1], fill=int(hg))

    def px(self, x, y, c, hg=None):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.img.putpixel((x, y), c + (255,) if len(c) == 3 else c)
            if hg is not None:
                self.hgt.putpixel((x, y), int(hg))

    def line(self, pts, c, width=1, hg=None):
        self.d.line(pts, fill=c + (255,) if len(c) == 3 else c, width=width)
        if hg is not None:
            self.hd.line(pts, fill=int(hg), width=width)

    def ellipse(self, x0, y0, x1, y1, c, hg=None, outline=None):
        self.d.ellipse([x0, y0, x1, y1], fill=(c + (255,) if len(c) == 3 else c) if c else None,
                       outline=(outline + (255,)) if outline else None)
        if hg is not None:
            self.hd.ellipse([x0, y0, x1, y1], fill=int(hg))

    def poly(self, pts, c, hg=None):
        self.d.polygon(pts, fill=c + (255,) if len(c) == 3 else c)
        if hg is not None:
            self.hd.polygon(pts, fill=int(hg))

    def rivet(self, x, y, c=STEEL_H, base=STEEL_D):
        self.px(x, y, c, 255)
        self.px(x + 1, y + 1, base, 120)

    def noise(self, x0, y0, x1, y1, amount, rng, only_opaque=True):
        a = np.array(self.img).astype(np.float32)
        n = rng.standard_normal((y1 - y0 + 1, x1 - x0 + 1, 1)).astype(np.float32) * amount
        region = a[y0:y1 + 1, x0:x1 + 1, :3]
        mask = a[y0:y1 + 1, x0:x1 + 1, 3:4] > 0 if only_opaque else 1.0
        a[y0:y1 + 1, x0:x1 + 1, :3] = np.clip(region * (1.0 + n * mask), 0, 255)
        self.img = Image.fromarray(a.astype(np.uint8), "RGBA")
        self.d = ImageDraw.Draw(self.img)

    def stripes(self, x0, y0, x1, y1, w=4, slant=1, hg=None, colors=(RED, GREEN)):
        """Diagonal warning stripes, worn at the edges."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                k = ((x + slant * y) // w) % 2
                c = colors[k]
                if (x * 7 + y * 13) % 11 == 0:
                    c = shade(c, 0.75)
                self.px(x, y, c, hg)

    def save(self, name):
        self.img.save(os.path.join(OUT, name))

    def normals(self, name, k=2.2):
        h = np.array(self.hgt).astype(np.float32) / 255.0
        hl = np.roll(h, 1, axis=1)
        hr = np.roll(h, -1, axis=1)
        hu = np.roll(h, 1, axis=0)
        hd = np.roll(h, -1, axis=0)
        nx = (hl - hr) * k
        ny = (hd - hu) * k          # (Godot reads +y as up, as tools/gen_assets.gd writes it)
        nz = np.ones_like(h)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        out = np.zeros((self.h, self.w, 4), np.uint8)
        out[..., 0] = ((nx / ln) * 0.5 + 0.5) * 255
        out[..., 1] = ((ny / ln) * 0.5 + 0.5) * 255
        out[..., 2] = ((nz / ln) * 0.5 + 0.5) * 255
        out[..., 3] = np.array(self.img)[..., 3]
        Image.fromarray(out, "RGBA").save(os.path.join(OUT, name))


# ================================================================ the back wall
def tiny_text(a, x, y, text, c, scale=1):
    """A 3 x 5 pixel font (capitals and digits) for the stencils."""
    font = {
        "A": "010101111101101", "B": "110101110101110", "D": "110101101101110", "E": "111100110100111",
        "G": "011100101101011", "H": "101101111101101", "K": "101101110101101", "L": "100100100100111",
        "N": "101111111111101", "O": "111101101101111", "P": "110101110100100", "R": "110101110101101",
        "T": "111010010010010", "U": "101101101101111", "Y": "101101010010010", "!": "010010010000010",
        "2": "111001111100111", "7": "111001001001001", " ": "000000000000000", "-": "000000111000000",
        "M": "101111111101101", "S": "011100010001110", "I": "111010010010111", "C": "011100100100011",
        "F": "111100110100100", "W": "101101111111101",
    }
    cx = x
    for ch in text:
        bits = font.get(ch, font[" "])
        for i, b in enumerate(bits):
            if b == "1":
                for sy in range(scale):
                    for sx in range(scale):
                        a.px(cx + (i % 3) * scale + sx, y + (i // 3) * scale + sy, c)
        cx += 4 * scale


def claw_marks(a, x, y, length, ang, rng):
    """Four long scratches side by side: a pale gouge with a dark lip."""
    dx, dy = math.cos(ang), math.sin(ang)
    nx, ny = -dy, dx
    for k in range(4):
        ox, oy = x + nx * k * 4.0, y + ny * k * 4.0
        ln = length * (0.85 + 0.3 * rng.random()) * (0.9 if k in (0, 3) else 1.0)
        for i in range(int(ln)):
            t = i / ln
            wob = math.sin(t * 6.0 + k) * 0.6
            px, py = ox + dx * i + nx * wob, oy + dy * i + ny * wob
            if t < 0.08 or t > 0.92:
                if rng.random() < 0.5:
                    continue
            a.px(int(px), int(py), (150, 112, 96))
            a.px(int(px + nx), int(py + ny), (34, 16, 14))
            if rng.random() < 0.3:
                a.px(int(px - nx), int(py - ny), (112, 76, 64))


def gauge(a, cx, cy, r, needle, rng, rim=BRASS):
    a.ellipse(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, IRON_K, 160)
    a.ellipse(cx - r, cy - r, cx + r, cy + r, rim, 200)
    a.ellipse(cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2, (200, 194, 172), 150)
    for i in range(9):
        t = math.pi * (0.75 + 1.5 * i / 8.0)
        x = cx + math.cos(t) * (r - 3)
        y = cy + math.sin(t) * (r - 3)
        a.px(int(round(x)), int(round(y)), (40, 30, 30))
    # the red zone
    for i in range(6):
        t = math.pi * (0.75 + 1.5 * (0.8 + 0.2 * i / 5.0))
        a.px(int(round(cx + math.cos(t) * (r - 3))), int(round(cy + math.sin(t) * (r - 3))), (190, 30, 24))
    t = math.pi * (0.75 + 1.5 * needle)
    a.line([(cx, cy), (cx + math.cos(t) * (r - 3), cy + math.sin(t) * (r - 3))], (170, 20, 16))
    a.px(cx, cy, IRON_K)


def valve_wheel(a, cx, cy, r, c=RED, cd=RED_D):
    a.ellipse(cx - r, cy - r, cx + r, cy + r, None, outline=c)
    a.ellipse(cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1, None, outline=cd)
    for k in range(4):
        t = k * math.pi / 2 + 0.4
        a.line([(cx, cy), (cx + math.cos(t) * (r - 1), cy + math.sin(t) * (r - 1))], cd)
    a.rect(cx - 1, cy - 1, cx + 1, cy + 1, IRON_L)


def back_pipe(a, x0, y0, x1, y1, r, c, rng, stripes=False):
    """A background pipe, horizontal (y0 == y1) or vertical (x0 == x1), round-shaded, with flanges."""
    if y0 == y1:
        for x in range(x0, x1 + 1):
            for dy in range(-r, r + 1):
                t = dy / r
                k = 0.55 + 0.45 * math.cos(t * 1.4 + 0.5)
                a.px(x, y0 + dy, shade(c, k))
        for x in range(x0 + 20, x1, 54):
            a.rect(x, y0 - r - 2, x + 3, y0 + r + 2, shade(c, 0.6))
            a.rect(x + 1, y0 - r - 2, x + 1, y0 + r + 2, shade(c, 1.15))
            a.px(x + 1, y0 - r, STEEL_H)
            a.px(x + 1, y0 + r, STEEL_H)
            if stripes:
                for xx in range(x + 7, x + 19):
                    for dy in range(-r, r + 1):
                        k = 0.55 + 0.45 * math.cos(dy / r * 1.4 + 0.5)
                        base = RED if ((xx - x - 7) // 4) % 2 == 0 else GREEN
                        a.px(xx, y0 + dy, shade(base, k * 0.85))
    else:
        for y in range(y0, y1 + 1):
            for dx in range(-r, r + 1):
                t = dx / r
                k = 0.55 + 0.45 * math.cos(t * 1.4 + 0.5)
                a.px(x0 + dx, y, shade(c, k))
        for y in range(y0 + 16, y1, 50):
            a.rect(x0 - r - 2, y, x0 + r + 2, y + 3, shade(c, 0.6))
            a.rect(x0 - r - 2, y + 1, x0 + r + 2, y + 1, shade(c, 1.15))
            if stripes:
                for yy in range(y + 7, y + 19):
                    for dx in range(-r, r + 1):
                        k = 0.55 + 0.45 * math.cos(dx / r * 1.4 + 0.5)
                        base = RED if ((yy - y - 7) // 4) % 2 == 0 else GREEN
                        a.px(x0 + dx, yy, shade(base, k * 0.85))


def make_back(rows, rng, nrng):
    """The back wall, kept dark and quiet so the play space stands out: three big brick
    arches (the boiler room's vaults) over dark machinery seen as shapes with a thin warm
    rim from the furnaces below, thin dim pipes (thinner and darker than any pipe you can
    stand on), a fan high on the right, chains, claw marks, stains."""
    a = Art(W, H, (10, 7, 7, 255))
    dark_bricks = [(46, 23, 19), (52, 26, 21), (42, 21, 18), (56, 29, 23), (38, 19, 16), (49, 27, 23)]
    for by in range(0, H, 6):
        off = 0 if (by // 6) % 2 == 0 else 8
        for bx in range(-off, W, 16):
            col = shade(rng.choice(dark_bricks), 0.92 + 0.14 * rng.random())
            a.rect(bx, by, bx + 14, by + 4, col)
            a.rect(bx, by, bx + 14, by, shade(col, 1.1))
            a.rect(bx, by + 5, bx + 15, by + 5, (15, 9, 8))
            a.rect(bx + 15, by, bx + 15, by + 5, (15, 9, 8))
    a.noise(0, 0, W - 1, H - 1, 0.05, nrng)

    # the vaults: three arches, their insides set back (darker), a ring of lighter bricks
    arches = [(40, 300, 150), (330, 630, 120), (660, 920, 150)]   # (x0, x1, top of the curve)
    arr = np.array(a.img).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    for (x0, x1, top) in arches:
        cx, r = (x0 + x1) / 2.0, (x1 - x0) / 2.0
        inside = ((xx > x0) & (xx < x1) & (yy > top + r)) | (((xx - cx) ** 2 + (yy - top - r) ** 2) < r * r)
        inside &= yy < 505
        arr[inside, :3] *= 0.55
    a.img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    a.d = ImageDraw.Draw(a.img)
    for (x0, x1, top) in arches:
        cx, r = (x0 + x1) / 2.0, (x1 - x0) / 2.0
        for k in range(0, 180, 6):                    # the ring's bricks
            t0 = math.radians(180 + k)
            for rr in range(int(r), int(r) + 7):
                x = int(cx + math.cos(t0) * rr)
                y = int(top + r + math.sin(t0) * rr)
                a.px(x, y, (70, 38, 30) if (k // 6) % 2 == 0 else (62, 33, 27))
        for x in (x0 - 8, x1 + 1):                   # the piers
            a.rect(x, int(top + r), x + 7, 505, (58, 31, 26))
            a.rect(x, int(top + r), x, 505, (74, 42, 34))

    def rim_shape(pts, body=(24, 20, 20), rim=(92, 52, 34)):
        a.poly(pts, body + (255,))
        # a thin warm rim along the lower edges (the furnaces light it from below)
        for i in range(len(pts)):
            p, q = pts[i], pts[(i + 1) % len(pts)]
            if abs(q[1] - p[1]) < abs(q[0] - p[0]) and (p[1] + q[1]) / 2 > 300:
                a.line([p, q], rim)

    # the old boiler in the middle arch (behind the great one): a domed tank, its rivets just showing
    for x in range(352, 609):
        t = (x - 352) / 256 * 2 - 1
        k = 0.5 + 0.3 * math.cos(t * 1.3 + 0.4)
        dome = 150 + int(46 * (1 - math.sqrt(max(0.0, 1 - t * t))))
        for y in range(dome, 470):
            c = shade((40, 32, 30), k)
            if (y - 150) % 46 in (0, 1):
                c = shade(c, 0.7)
            a.px(x, y, c)
        if (x - 352) % 8 == 4:
            for y in range(196, 470, 46):
                a.px(x, y + 3, shade((80, 66, 58), k))
    # tall tanks in the side arches
    for (x0, x1, y0) in [(120, 200, 230), (760, 830, 300)]:
        for x in range(x0, x1 + 1):
            t = (x - x0) / (x1 - x0) * 2 - 1
            k = 0.45 + 0.35 * math.cos(t * 1.3 + 0.5)
            for y in range(y0, 505):
                a.px(x, y, shade((36, 34, 34), k))
        a.ellipse(x0, y0 - 10, x1, y0 + 10, (44, 40, 40))
        for y in range(y0 + 30, 505, 40):
            a.rect(x0, y, x1, y, (20, 18, 18))
        gauge(a, (x0 + x1) // 2, y0 + 50, 7, rng.random(), rng, rim=(100, 76, 36))

    # thin dim pipes across the back (never as thick or as bright as a walkway pipe)
    dim = (46, 40, 38)
    back_pipe(a, 30, 50, 930, 50, 3, dim, rng)
    back_pipe(a, 30, 62, 340, 62, 2, dim, rng)
    back_pipe(a, 620, 62, 930, 62, 2, dim, rng)
    back_pipe(a, 30, 470, 350, 470, 2, dim, rng)
    back_pipe(a, 610, 470, 930, 470, 2, dim, rng)
    back_pipe(a, 96, 50, 96, 505, 3, dim, rng)
    back_pipe(a, 866, 50, 866, 505, 3, dim, rng)
    back_pipe(a, 250, 50, 250, 240, 2, dim, rng)
    back_pipe(a, 712, 50, 712, 250, 2, dim, rng)
    for (x, y) in [(96, 50), (866, 50), (96, 470), (866, 470), (250, 50), (712, 50)]:
        a.ellipse(x - 5, y - 5, x + 5, y + 5, (40, 34, 32))
    gauge(a, 96, 150, 7, 0.35, rng, rim=(100, 76, 36))
    gauge(a, 866, 200, 7, 0.65, rng, rim=(100, 76, 36))
    valve_wheel(a, 250, 228, 7, (110, 30, 26), (70, 20, 18))
    valve_wheel(a, 712, 238, 7, (110, 30, 26), (70, 20, 18))

    # the big fan's frame high on the right (the page turns its blades over a cold light)
    fx, fy, fr = 768, 132, 40
    a.ellipse(fx - fr - 5, fy - fr - 5, fx + fr + 5, fy + fr + 5, (30, 26, 26))
    a.ellipse(fx - fr - 2, fy - fr - 2, fx + fr + 2, fy + fr + 2, (54, 48, 46))
    a.ellipse(fx - fr, fy - fr, fx + fr, fy + fr, (8, 8, 10))
    for k in range(8):
        t = k * math.pi / 4
        a.px(int(fx + math.cos(t) * (fr + 3)), int(fy + math.sin(t) * (fr + 3)), (90, 92, 98))
    a.rect(fx - 16, 30, fx + 16, fy - fr - 6, (34, 30, 30))
    for y in range(36, fy - fr - 6, 12):
        a.rect(fx - 16, y, fx + 16, y, (22, 19, 19))

    # chains at the back
    for (x, y0, ln) in [(150, 30, 70), (395, 30, 100), (585, 30, 84), (330, 30, 40), (905, 30, 60)]:
        for y in range(y0, y0 + ln, 4):
            if (y // 4) % 2 == 0:
                a.rect(x - 1, y, x + 1, y + 3, (40, 36, 34))
                a.px(x, y + 1, (10, 8, 8))
            else:
                a.rect(x, y, x, y + 3, (52, 46, 44))
        a.line([(x, y0 + ln), (x + 3, y0 + ln + 5), (x, y0 + ln + 9), (x - 3, y0 + ln + 6)], (48, 42, 40))

    # soot over the furnaces, a little warm light low on the wall near them
    arr = np.array(a.img).astype(np.float32)
    for (fx2, fy2, w, hgt) in [(70, 330, 60, 240), (890, 380, 60, 260), (480, 300, 150, 260)]:
        d = np.exp(-((xx - fx2) / w) ** 2) * np.clip((fy2 - yy) / hgt, 0, 1) * np.clip((yy - (fy2 - hgt)) / 60.0, 0, 1)
        arr[..., :3] *= (1.0 - 0.4 * d)[..., None]
    for (fx2, fy2, r, k) in [(75, 370, 110, 0.3), (885, 412, 110, 0.3), (480, 430, 150, 0.25)]:
        d = np.exp(-(((xx - fx2) ** 2 + (yy - fy2) ** 2) / (r * r)))
        arr[..., 0] += 50 * k * d
        arr[..., 1] += 16 * k * d
    vig = np.clip(1.0 - 0.6 * (((xx - 480) / 560) ** 2 + ((yy - 320) / 360) ** 2), 0.3, 1.0)
    top = np.clip((yy - 20) / 160.0, 0.45, 1.0)
    arr[..., :3] *= (vig * top)[..., None]
    a.img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    a.d = ImageDraw.Draw(a.img)

    # claw marks (pale gouges), stencils, rust stains
    claw_marks(a, 200, 300, 40, 1.0, rng)
    claw_marks(a, 640, 330, 44, 2.0, rng)
    claw_marks(a, 860, 300, 34, 1.3, rng)
    claw_marks(a, 60, 120, 32, 1.1, rng)
    claw_marks(a, 372, 210, 40, 1.2, rng)
    tiny_text(a, 150, 288, "DANGER", (120, 104, 56), 2)
    tiny_text(a, 742, 300, "KEEP OUT", (118, 104, 58), 1)
    tiny_text(a, 560, 168, "B-2", (96, 78, 58), 2)
    for (x, y, ln) in [(96, 150, 60), (866, 200, 50), (250, 236, 40), (712, 246, 30), (430, 470, 30)]:
        for i in range(ln):
            if rng.random() < 0.8:
                a.px(x + int(math.sin(i * 0.3) * 1.5), y + 10 + i, shade((80, 44, 26), 1.0 - i / ln * 0.6))

    a.img = a.img.convert("RGB").convert("RGBA")
    a.save("boiler_back.png")


# ================================================================ the front: blocks and ledges
def cell_rect(c0, r0, c1, r1):
    return c0 * C, r0 * C, (c1 + 1) * C - 1, (r1 + 1) * C - 1


def paint_brick_wall(a, x0, y0, x1, y1, rng, dark=1.0):
    for by in range(y0 - (y0 % 6), y1 + 1, 6):
        off = 0 if (by // 6) % 2 == 0 else 8
        for bx in range(x0 - 16 - off, x1 + 1, 16):
            col = shade(rng.choice(BRICK), dark * (0.95 + 0.25 * rng.random()))
            for y in range(max(by, y0), min(by + 4, y1) + 1):
                for x in range(max(bx, x0), min(bx + 14, x1) + 1):
                    a.px(x, y, col, 150)
            for x in range(max(bx, x0), min(bx + 15, x1) + 1):
                if y0 <= by + 5 <= y1:
                    a.px(x, by + 5, MORTAR, 80)
            if x0 <= bx + 15 <= x1:
                for y in range(max(by, y0), min(by + 5, y1) + 1):
                    a.px(bx + 15, y, MORTAR, 80)


def paint_steel(a, x0, y0, x1, y1, rng, base=STEEL, panel=30):
    """Riveted steel plates: panels with seams, rivets along the seams, rust streaks."""
    a.rect(x0, y0, x1, y1, base, 140)
    for px0 in range(x0 - ((x0) % panel), x1 + 1, panel):
        for py0 in range(y0 - ((y0) % panel), y1 + 1, panel):
            sx0, sy0 = max(px0, x0), max(py0, y0)
            sx1, sy1 = min(px0 + panel - 1, x1), min(py0 + panel - 1, y1)
            tone = 0.88 + 0.2 * rng.random()
            a.rect(sx0, sy0, sx1, sy1, shade(base, tone), 140)
            a.rect(sx0, sy0, sx1, sy0, shade(base, tone * 1.25), 170)
            a.rect(sx0, sy0, sx0, sy1, shade(base, tone * 1.12), 160)
            a.rect(sx0, sy1, sx1, sy1, shade(base, tone * 0.62), 90)
            a.rect(sx1, sy0, sx1, sy1, shade(base, tone * 0.7), 100)
            for rx in range(sx0 + 3, sx1 - 1, 6):
                if sy0 + 2 <= y1:
                    a.rivet(rx, sy0 + 2)
                if sy1 - 3 >= y0:
                    a.rivet(rx, sy1 - 3)
            if rng.random() < 0.35:   # a rust streak running down from a rivet
                rx = rng.randint(sx0 + 2, max(sx0 + 2, sx1 - 2))
                for y in range(sy0 + 4, min(sy1, sy0 + 4 + rng.randint(6, 18))):
                    a.px(rx, y, mix(shade(base, tone), RUST, 0.55 if (y % 3) else 0.35))


def paint_front(rows, rng, nrng):
    a = Art(W, H)
    solid = [[rows[r][c] == "#" for c in range(COLS)] for r in range(ROWS)]
    ledge = [[rows[r][c] == "=" for c in range(COLS)] for r in range(ROWS)]

    def is_solid(c, r):
        return solid[r % ROWS][c % COLS]

    # every block first as dark riveted steel framed in brick at the outer walls
    for r in range(ROWS):
        for c in range(COLS):
            if not solid[r][c]:
                continue
            x0, y0, x1, y1 = cell_rect(c, r, c, r)
            outer = c <= 1 or c >= 62 or r <= 1 or r >= 34
            if outer:
                paint_brick_wall(a, x0, y0, x1, y1, rng, 0.85)
            else:
                a.rect(x0, y0, x1, y1, STEEL, 140)
    # steel panels over the inner blocks (merged into runs, so the seams line up)
    for r in range(ROWS):
        c = 0
        while c < COLS:
            if solid[r][c] and not (c <= 1 or c >= 62 or r <= 1 or r >= 34):
                c0 = c
                while c < COLS and solid[r][c] and not (c <= 1 or c >= 62):
                    c += 1
                x0, y0, x1, y1 = cell_rect(c0, r, c - 1, r)
                paint_steel(a, x0, y0, x1, y1, rng)
            else:
                c += 1

    # the ceiling: a heavy I-beam with warning stripes on its lower flange
    for c in range(COLS):
        if is_solid(c, 1):
            x0, _, x1, _ = cell_rect(c, 1, c, 1)
            a.rect(x0, 15, x1, 29, STEEL_D, 150)
            a.rect(x0, 15, x1, 16, STEEL_L, 190)
            a.stripes(x0, 22, x1, 28, 4, 1, 200)
            a.rect(x0, 21, x1, 21, STEEL_K, 100)
            a.rect(x0, 29, x1, 29, STEEL_K, 90)
            for x in range(x0 + 4, x1, 8):
                a.rivet(x, 18)
    # the floor: diamond plate along the top
    for c in range(COLS):
        if is_solid(c, 34):
            x0, _, x1, _ = cell_rect(c, 34, c, 34)
            a.rect(x0, 510, x1, 524, STEEL_D, 150)
            for y in range(512, 524):
                for x in range(x0, x1 + 1):
                    if ((x + y * 3) % 8 == 0) or ((x - y * 3) % 8 == 0 and (x + y) % 2 == 0):
                        a.px(x, y, STEEL_M, 200)
            a.rect(x0, 510, x1, 511, STEEL_H, 220)
            a.rect(x0, 524, x1, 524, STEEL_K, 60)
    # the side walls' inner faces: a steel column with rivets
    for r in range(2, 34):
        if is_solid(1, r) and not is_solid(2, r):
            y0, y1 = r * C, r * C + C - 1
            a.rect(24, y0, 29, y1, STEEL_D, 170)
            a.rect(28, y0, 29, y1, STEEL_L, 200)
            if r % 2 == 0:
                a.rivet(26, y0 + 6)
        if is_solid(62, r) and not is_solid(61, r):
            y0, y1 = r * C, r * C + C - 1
            a.rect(930, y0, 935, y1, STEEL_D, 170)
            a.rect(930, y0, 931, y1, STEEL_L, 200)
            if r % 2 == 0:
                a.rivet(932, y0 + 6)

    # ---- the great boiler (cols 27-36, rows 15-25): a riveted cylinder
    bx0, by0, bx1, by1 = cell_rect(27, 15, 36, 25)
    for x in range(bx0, bx1 + 1):
        t = (x - bx0) / (bx1 - bx0) * 2 - 1
        k = 0.55 + 0.5 * math.cos(t * 1.45 + 0.45)
        hcyl = int(255 * math.sqrt(max(0.0, 1 - t * t * 0.85)))
        for y in range(by0, by1 + 1):
            base = (78, 70, 66)
            a.px(x, y, shade(base, k), hcyl)
    for y in range(by0 + 14, by1, 26):   # riveted seams around it
        for x in range(bx0, bx1 + 1):
            t = (x - bx0) / (bx1 - bx0) * 2 - 1
            k = 0.55 + 0.5 * math.cos(t * 1.45 + 0.45)
            a.px(x, y, shade((40, 36, 34), k), 60)
            a.px(x, y + 1, shade((120, 110, 100), k), 220)
            if (x - bx0) % 6 == 2:
                a.px(x, y - 2, shade((150, 140, 130), k), 255)
                a.px(x, y + 3, shade((150, 140, 130), k), 255)
    for x in range(bx0, bx1 + 1):        # a band of warning stripes low on it
        for y in range(by1 - 22, by1 - 14):
            t = (x - bx0) / (bx1 - bx0) * 2 - 1
            k = 0.55 + 0.5 * math.cos(t * 1.45 + 0.45)
            base = RED if ((x + y) // 5) % 2 == 0 else GREEN
            a.px(x, y, shade(base, k), 200)
    a.rect(bx0, by0, bx1, by0 + 1, (170, 160, 150), 255)     # its top rim (you stand on it)
    a.rect(bx0, by0 + 2, bx1, by0 + 2, (60, 54, 50), 100)
    gauge(a, 480, by0 + 38, 14, 0.62, rng)                     # the big pressure gauge
    a.rect(476, by0 + 52, 484, by0 + 58, BRASS_D, 180)
    # a riveted hatch
    a.ellipse(452, by0 + 78, 508, by0 + 124, (54, 48, 46), 200)
    a.ellipse(455, by0 + 81, 505, by0 + 121, (92, 84, 78), 230)
    a.ellipse(460, by0 + 86, 500, by0 + 116, (70, 64, 60), 180)
    for k2 in range(12):
        t = k2 * math.pi / 6
        a.rivet(int(480 + math.cos(t) * 23), int(by0 + 101 + math.sin(t) * 18))
    a.rect(470, by0 + 98, 490, by0 + 103, (40, 36, 34), 200)
    a.rect(470, by0 + 98, 490, by0 + 98, (130, 120, 110), 230)
    claw_marks(a, 418, by0 + 40, 26, 1.25, rng)
    # its steam pipes' flanges (P0 out of its left side, P1 out of its right side)
    for (x, y, side) in [(bx0, 280, -1), (bx1, 325, 1)]:
        a.rect(x - 2 if side < 0 else x - 3, y - 9, x + 2 if side < 0 else x + 1, y + 9, STEEL_D, 200)
        a.rect(x - 2 if side < 0 else x - 3, y - 9, x - 2 if side < 0 else x - 3, y + 9, STEEL_L, 230)
        a.rivet(x, y - 6)
        a.rivet(x, y + 5)
    # the safety valve on top (cols 31-32, rows 12-14)
    vx0, vy0, vx1, vy1 = cell_rect(31, 12, 32, 14)
    a.rect(vx0, vy0, vx1, vy1, (0, 0, 0, 0))
    a.rect(vx0 + 4, vy0 + 12, vx1 - 4, vy1, BRASS_D, 180)
    for x in range(vx0 + 4, vx1 - 3):
        t = (x - vx0 - 4) / (vx1 - vx0 - 8) * 2 - 1
        k = 0.6 + 0.5 * math.cos(t * 1.4 + 0.5)
        for y in range(vy0 + 12, vy1 + 1):
            a.px(x, y, shade(BRASS, k), int(220 * math.sqrt(max(0, 1 - t * t * 0.8))))
    a.rect(vx0 + 1, vy0 + 8, vx1 - 1, vy0 + 13, BRASS_D, 200)
    a.rect(vx0 + 1, vy0 + 8, vx1 - 1, vy0 + 8, BRASS_L, 240)
    a.rect(vx0 + 9, vy0, vx1 - 9, vy0 + 8, BRASS, 220)       # the whistle
    a.rect(vx0 + 9, vy0, vx0 + 10, vy0 + 8, BRASS_L, 240)
    a.rect(vx0 + 7, vy0, vx1 - 7, vy0 + 1, BRASS_L, 240)
    a.line([(vx0 + 2, vy0 + 20), (vx1 + 6, vy0 + 14)], IRON_L, 2, 200)   # the lever
    a.ellipse(vx1 + 4, vy0 + 11, vx1 + 9, vy0 + 16, IRON, 230)
    a.rect(vx0 + 2, vy1 - 2, vx1 - 2, vy1, (170, 160, 150), 255)

    # ---- the firebox (cols 27-36, rows 30-33): brick with an iron front and a big door
    fx0, fy0, fx1, fy1 = cell_rect(27, 30, 36, 33)
    paint_brick_wall(a, fx0, fy0, fx1, fy1, rng, 0.9)
    a.rect(fx0, fy0, fx1, fy0 + 5, IRON_D, 200)               # the grate on top (the fire comes up through it)
    for x in range(fx0 + 2, fx1 - 1, 4):
        a.rect(x, fy0 + 1, x + 1, fy0 + 4, IRON_L, 230)
    a.rect(fx0, fy0, fx1, fy0, (150, 130, 120), 255)
    a.rect(fx0 + 30, fy0 + 12, fx1 - 30, fy1, IRON_D, 180)    # the door's frame
    a.rect(fx0 + 33, fy0 + 15, fx1 - 33, fy1 - 4, IRON, 200)
    a.rect(fx0 + 33, fy0 + 15, fx1 - 33, fy0 + 15, IRON_L, 230)
    for x in range(fx0 + 37, fx1 - 36, 5):                    # its grate (the page lights it from inside)
        a.rect(x, fy0 + 20, x + 2, fy1 - 10, (24, 10, 8), 60)
    for y in (fy0 + 18, fy1 - 8):
        for x in range(fx0 + 34, fx1 - 33, 7):
            a.rivet(x, y)
    a.rect(fx0 + 38, fy1 - 6, fx1 - 38, fy1 - 5, BRASS, 220)  # its handle
    tiny_text(a, fx0 + 8, fy0 + 26, "DANGER", (190, 160, 60), 1)

    # ---- the wall furnaces: F0 (cols 2-4, rows 21-26) and F1 (cols 59-61, rows 24-29)
    def furnace(c0, r0, c1, r1, mouth_y0, mouth_y1, face):
        """An iron furnace built into the wall: riveted black iron, a striped hood, a round
        grated door (the page lights it from inside) and the fire's mouth toward the room."""
        x0, y0, x1, y1 = cell_rect(c0, r0, c1, r1)
        for x in range(x0, x1 + 1):
            t = (x - x0) / max(1, x1 - x0)
            k = 0.75 + 0.35 * (t if face > 0 else 1 - t)       # lighter toward the room
            for y in range(y0, y1 + 1):
                a.px(x, y, shade(IRON, k), 160)
        for yy in range(y0 + 10, y1, 20):                     # plate seams and rivets
            a.rect(x0, yy, x1, yy, IRON_K, 90)
            a.rect(x0, yy + 1, x1, yy + 1, IRON_L, 190)
            for xx in range(x0 + 3, x1 - 1, 6):
                a.rivet(xx, yy + 4, (120, 108, 100), IRON_K)
        a.rect(x0, y0, x1, y0 + 6, IRON_D, 200)                # the hood, striped
        a.rect(x0, y0, x1, y0, (150, 136, 124), 255)
        a.stripes(x0, y0 + 2, x1, y0 + 5, 3, 1 if face > 0 else -1, 210)
        cx, cy = (x0 + x1) // 2, y0 + 30
        a.ellipse(cx - 17, cy - 17, cx + 17, cy + 17, IRON_K, 150)
        a.ellipse(cx - 15, cy - 15, cx + 15, cy + 15, (104, 92, 84), 230)
        a.ellipse(cx - 12, cy - 12, cx + 12, cy + 12, IRON_D, 120)
        a.ellipse(cx - 11, cy - 11, cx + 11, cy + 11, (26, 10, 8), 40)
        for k2 in range(5):
            xx = cx - 8 + k2 * 4
            a.rect(xx, cy - 10, xx + 1, cy + 10, IRON_L, 200)
        for k2 in range(8):
            t = k2 * math.pi / 4
            a.rivet(int(cx + math.cos(t) * 13.5), int(cy + math.sin(t) * 13.5), BRASS_L, IRON_K)
        hx = cx + 15 * face                                     # the door's handle
        a.rect(min(hx, hx + 4 * face), cy - 2, max(hx, hx + 4 * face), cy + 1, BRASS, 230)
        a.rect(x0 + 6, y1 - 20, x1 - 6, y1 - 13, BRASS_D, 200)  # a brass plate
        tiny_text(a, x0 + 13, y1 - 19, "HOT", (240, 210, 120), 1)
        a.rect(x0, y1 - 4, x1, y1, (20, 16, 16), 100)           # ash at its foot
        # the fire's mouth: a dark chute with an iron lip, scorched around
        mx = x1 if face > 0 else x0
        lip0, lip1 = (mx - 10, mx) if face > 0 else (mx, mx + 10)
        a.rect(lip0, mouth_y0 - 3, lip1, mouth_y1 + 3, IRON_D, 180)
        a.rect(lip0 + (3 if face > 0 else 0), mouth_y0, lip1 - (0 if face > 0 else 3), mouth_y1, (14, 6, 5), 30)
        a.rect(lip0, mouth_y0 - 3, lip1, mouth_y0 - 3, (150, 136, 124), 240)
        a.rect(lip0, mouth_y1 + 3, lip1, mouth_y1 + 3, IRON_L, 220)
        for yy in range(mouth_y0 - 6, mouth_y1 + 7, 2):
            for k3 in range(4):
                xx = (mx - 11 - k3) if face > 0 else (mx + 11 + k3)
                if rng.random() < 0.5 - k3 * 0.1:
                    a.px(xx, yy, (16, 12, 12), 120)
        claw_marks(a, x0 + 6, y0 + 52, 14, 1.2, rng)

    furnace(2, 21, 4, 26, 346, 389, 1)
    furnace(59, 24, 61, 29, 391, 434, -1)

    # ---- the hanging pipes (cols 19-20 rows 2-8, cols 43-44 rows 2-7)
    def hanging_pipe(c0, r0, c1, r1):
        x0, y0, x1, y1 = cell_rect(c0, r0, c1, r1)
        a.rect(x0, y0, x1, y1, (0, 0, 0, 0))
        px0, px1 = x0 + 4, x1 - 4
        for x in range(px0, px1 + 1):
            t = (x - px0) / (px1 - px0) * 2 - 1
            k = 0.5 + 0.55 * math.cos(t * 1.4 + 0.5)
            hc = int(255 * math.sqrt(max(0, 1 - t * t)))
            for y in range(y0, y1 - 8):
                base = (84, 76, 72)
                if 30 <= y - y0 < 46:
                    base = RED if ((y - y0 - 30) // 4) % 2 == 0 else GREEN
                a.px(x, y, shade(base, k), hc)
        for yy in (y0 + 10, y0 + 60):                       # flanges
            a.rect(x0 + 1, yy, x1 - 1, yy + 4, STEEL_D, 200)
            a.rect(x0 + 1, yy, x1 - 1, yy, STEEL_L, 240)
            a.rivet(x0 + 3, yy + 2)
            a.rivet(x1 - 4, yy + 2)
        # the valve body at its end (you can stand on it) and a red wheel
        a.rect(x0, y1 - 9, x1, y1, STEEL_D, 210)
        a.rect(x0, y1 - 9, x1, y1 - 8, STEEL_H, 255)
        a.rect(x0, y1, x1, y1, STEEL_K, 80)
        valve_wheel(a, (x0 + x1) // 2, y1 - 20, 8)
    hanging_pipe(19, 2, 20, 8)
    hanging_pipe(43, 2, 44, 7)

    # ---- the water tank (cols 49-52, rows 19-21)
    tx0, ty0, tx1, ty1 = cell_rect(49, 19, 52, 21)
    for y in range(ty0, ty1 + 1):
        t = (y - ty0) / (ty1 - ty0) * 2 - 1
        k = 0.5 + 0.55 * math.cos(t * 1.4 + 0.6)
        for x in range(tx0, tx1 + 1):
            a.px(x, y, shade((70, 82, 84), k), int(255 * math.sqrt(max(0, 1 - t * t * 0.8))))
    for x in (tx0 + 2, tx1 - 3):
        for y in range(ty0 + 3, ty1 - 2, 5):
            a.rivet(x, y)
    a.rect(tx0, ty0, tx1, ty0 + 1, (160, 170, 170), 255)
    a.rect(tx0 + 24, ty0 + 8, tx0 + 28, ty1 - 6, (20, 40, 46), 120)     # a sight glass
    a.rect(tx0 + 25, ty0 + 24, tx0 + 27, ty1 - 7, (60, 120, 130), 160)
    tiny_text(a, tx0 + 34, ty0 + 10, "H2O", (170, 180, 170), 1) if False else tiny_text(a, tx0 + 34, ty0 + 10, "WATER", (150, 160, 150), 1)

    # ---- the beds: the headboards (cols 9-10 and 53-54, rows 30-33) and the beds over the gaps
    def headboard(c0, c1):
        x0, y0, x1, y1 = cell_rect(c0, 30, c1, 33)
        a.rect(x0, y0, x1, y1, (0, 0, 0, 0))
        a.rect(x0 + 2, y0 + 8, x1 - 2, y1, (44, 30, 26), 120)       # a dark wooden panel
        for x in range(x0 + 5, x1 - 3, 5):                          # iron bars
            a.rect(x, y0 + 4, x + 1, y1, IRON_L, 220)
        for x in (x0, x1 - 3):                                      # the posts
            a.rect(x, y0 - 0, x + 3, y1, IRON, 230)
            a.rect(x, y0, x, y1, IRON_L, 255)
        a.rect(x0, y0, x1, y0 + 3, IRON, 240)                       # the top rail (you can stand on it)
        a.rect(x0, y0, x1, y0, (130, 116, 104), 255)
        for x in (x0 + 1, x1 - 2):
            a.ellipse(x - 2, y0 - 4, x + 2, y0, BRASS, 255)         # the knobs
            a.px(x - 1, y0 - 3, BRASS_L, 255)
        a.rect(x0 + 6, y0 + 14, x1 - 6, y0 + 15, IRON_L, 220)       # a cross bar
    headboard(10, 11)
    headboard(52, 53)

    def bed(gx0, gx1, head_side):
        """The bed over the gap (art px gx0..gx1): its headboard is the block beside the gap,
        a sagging mattress with a sheet, a pillow at the head, a red and green striped
        blanket over the foot, the frame's rail and legs down into the dark pit, and an iron
        footboard on the far side."""
        top = 499
        for x in range(gx0, gx1 + 1):
            u = (x - gx0) / max(1, gx1 - gx0)
            sag = int(round(4 * math.sin(math.pi * u)))
            yt = top + sag
            for y in range(yt, yt + 10):
                c = SHEET if y < yt + 2 else (SHEET_D if y < yt + 6 else SHEET_K)
                if y >= yt + 6 and (x // 3) % 2 == 0:
                    c = shade((150, 156, 170), 0.85)            # the mattress's ticking
                a.px(x, y, c, 210 - (y - yt) * 10)
            a.px(x, yt, (226, 220, 206), 230)
            foot = u > 0.42 if head_side < 0 else u < 0.58
            if foot:                                             # the blanket
                for y in range(yt - 2, yt + 7):
                    base = RED if ((x // 4) % 2 == 0) else GREEN
                    a.px(x, y, shade(base, 1.0 if y < yt + 1 else 0.72), 220)
                a.px(x, yt + 7 + (x % 3 == 0), shade(RED if (x // 4) % 2 == 0 else GREEN, 0.55), 160)
        px0 = gx0 + 2 if head_side < 0 else gx1 - 18             # the pillow
        a.ellipse(px0, top - 6, px0 + 16, top + 3, SHEET_D, 220)
        a.ellipse(px0 + 1, top - 6, px0 + 15, top + 1, (222, 216, 200), 230)
        a.rect(px0 + 4, top - 3, px0 + 12, top - 3, (196, 188, 170), 230)
        a.rect(gx0, top + 10, gx1, top + 12, IRON, 200)          # the frame's side rail
        a.rect(gx0, top + 10, gx1, top + 10, IRON_L, 230)
        for x in (gx0 + 3, gx1 - 4):
            a.rect(x, top + 13, x + 1, H - 1, IRON_D, 150)
        for y in range(top + 13, H):
            k = (y - top - 13) / max(1, H - top - 13)
            for x in range(gx0, gx1 + 1):
                if a.img.getpixel((x, y))[3] == 0:
                    a.px(x, y, (6, 4, 4, int(150 + 100 * k)))
        fx = gx1 + 1 if head_side < 0 else gx0 - 4               # the footboard
        a.rect(fx, top - 14, fx + 3, top + 12, IRON, 230)
        a.rect(fx, top - 14, fx, top + 12, IRON_L, 255)
        a.rect(fx - (6 if head_side > 0 else 0), top - 8, fx + 3 + (6 if head_side < 0 else 0), top - 7, IRON_L, 230)
        a.ellipse(fx - 1, top - 18, fx + 4, top - 13, BRASS, 255)
        a.px(fx, top - 17, BRASS_L, 255)

    bed(180, 239, -1)
    bed(720, 779, 1)

    # ---- the openings in the ceiling over the beds: a bed's underside, springs and torn cloth
    def bed_bottom(gx0, gx1):
        for y in range(0, 30):
            for x in range(gx0, gx1 + 1):
                a.px(x, y, (8, 6, 6, 235))
        a.rect(gx0 - 1, 0, gx0, 29, IRON_L, 200)
        a.rect(gx1, 0, gx1 + 1, 29, IRON_L, 200)
        a.rect(gx0, 3, gx1, 5, (58, 46, 40), 160)            # the bed's slats, from below
        a.rect(gx0, 12, gx1, 13, (58, 46, 40), 160)
        for x in range(gx0 + 4, gx1 - 2, 8):                   # springs
            for y in range(5, 12, 2):
                a.line([(x - 2, y), (x + 2, y + 1)], (110, 102, 92))
        x = gx0 + 2
        while x < gx1 - 3:                                     # a torn sheet hanging in rags
            w = rng.randint(4, 8)
            ln = rng.randint(4, 12)
            pts = [(x, 13), (x + w, 13), (x + w - 1, 13 + ln * 0.6), (x + w // 2 + 1, 13 + ln), (x + 1, 13 + ln * 0.7)]
            a.poly(pts, shade(SHEET_K, 0.8 + 0.3 * rng.random()) + (255,))
            x += w + rng.randint(1, 4)

    bed_bottom(180, 239)
    bed_bottom(720, 779)

    # ---- the lockers' insides (the passages, cols 0-1 and 62-63, rows 14-17): dark metal backs
    def locker_inside(x0, x1):
        y0, y1 = 14 * C, 18 * C - 1
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                a.px(x, y, (14, 18, 17, 225))
        a.rect(x0, y0, x1, y0 + 2, LOCKER_D, 160)
        a.rect(x0 + 2, y0 + 16, x1 - 2, y0 + 17, LOCKER_D, 160)        # a shelf
        a.rect(x0 + 6, y0 + 18, x0 + 7, y0 + 24, IRON_L, 200)           # a coat hook
        for y in range(y0 + 4, y0 + 13, 3):                              # the back's vents
            a.rect(x0 + 8, y, x1 - 8, y, (6, 8, 8, 255), 60)
    locker_inside(0, 29)
    locker_inside(930, 959)

    # ---- the ledges: grating catwalks, or pipes you walk on
    pipe_runs = {(11, 24), (13, 48), (16, 15), (21, 53), (23, 15), (26, 42)}   # (row, first col)
    for r in range(ROWS):
        c = 0
        while c < COLS:
            if not ledge[r][c]:
                c += 1
                continue
            c0 = c
            while c < COLS and ledge[r][c]:
                c += 1
            x0, y0, x1, _ = cell_rect(c0, r, c - 1, r)
            if (r, c0) in pipe_runs:
                walk_pipe(a, x0, x1, y0, rng, big=(r == 11))
            else:
                grating(a, x0, x1, y0, rng, scorched=(r in (26, 29) and (c0 in (5, 52))))

    a.noise(0, 0, W - 1, H - 1, 0.035, nrng)
    a.save("boiler_front.png")
    a.normals("boiler_front_n.png")


def grating(a, x0, x1, y0, rng, scorched=False):
    """A catwalk of steel grating: a bright top rail, a criss-cross mesh you can see
    through, a frame under it with rivets, braces back to the wall."""
    frame = (92, 96, 104) if not scorched else (70, 56, 48)
    wire = (120, 124, 132) if not scorched else (96, 78, 64)
    a.rect(x0, y0, x1, y0 + 1, (176, 180, 186) if not scorched else (150, 116, 92), 255)
    a.rect(x0, y0 + 2, x1, y0 + 2, shade(frame, 0.7), 170)
    for y in range(y0 + 3, y0 + 7):
        for x in range(x0, x1 + 1):
            if (x + y) % 4 == 0 or (x - y) % 4 == 0:
                a.px(x, y, wire, 190)
            elif (x + y) % 4 == 2 and (x - y) % 4 == 2:
                a.px(x, y, shade(frame, 0.5), 150)
    a.rect(x0, y0 + 7, x1, y0 + 8, shade(frame, 0.85), 180)
    a.rect(x0, y0 + 9, x1, y0 + 9, (20, 20, 24), 90)
    for x in range(x0 + 3, x1, 7):
        a.rivet(x, y0 + 7, (170, 174, 180), (30, 30, 34))
    for bx in range(x0 + 12, x1 - 8, 32):
        a.line([(bx, y0 + 10), (bx + 7, y0 + 18)], shade(frame, 0.6), 1, 160)
    if scorched:
        for x in range(x0, x1 + 1):
            if rng.random() < 0.45:
                a.px(x, y0 + rng.randint(3, 8), (26, 18, 16), 120)
    a.rect(x0, y0, x0, y0 + 9, (30, 30, 34), 150)
    a.rect(x1, y0, x1, y0 + 9, (30, 30, 34), 150)


def walk_pipe(a, x0, x1, y0, rng, big=False):
    """A pipe you walk on: round shading, flanges with bolts, warning-stripe bands."""
    r = 5 if big else 4
    cy = y0 + r
    base = (92, 82, 76)
    for x in range(x0, x1 + 1):
        for dy in range(-r, r + 1):
            t = dy / r
            k = 0.5 + 0.55 * math.cos(t * 1.3 + 0.55)
            c = base
            band = ((x - x0) % 60)
            if 24 <= band < 36:
                c = RED if ((x // 4) % 2 == 0) else GREEN
            a.px(x, cy + dy, shade(c, k), int(255 * math.sqrt(max(0.0, 1 - t * t))))
        a.px(x, y0, shade(base, 1.6), 255)
    for x in range(x0 + 8, x1 - 2, 60):
        a.rect(x, y0 - 1, x + 3, cy + r + 1, STEEL_D, 220)
        a.rect(x + 1, y0 - 1, x + 1, cy + r + 1, STEEL_H, 255)
        a.px(x + 2, y0, STEEL_H, 255)
        a.px(x + 2, cy + r, STEEL_H, 255)
    for x in range(x0 + 20, x1 - 10, 45):       # hangers up into the dark
        a.rect(x, y0 - 6, x, y0 - 1, STEEL_D, 120)


# ================================================================ the moving parts
# The atlas: name -> (x, y, w, h). client/boiler_view.gd keeps the same table (PARTS).
PARTS = {
    "hook": (0, 0, 22, 30),
    "link_a": (24, 0, 6, 8),
    "link_b": (32, 0, 2, 8),
    "door": (36, 0, 30, 60),
    "hand_open": (68, 0, 18, 28),
    "hand_shut": (88, 0, 18, 28),
    "shadow": (108, 0, 56, 124),
    "bulb": (166, 0, 12, 16),
    "wheel": (180, 0, 18, 18),
}


def make_parts(rng):
    a = Art(256, 128)
    # the hook: thick steel with a bright edge and a dark outline (it must read against
    # the dark brick), an eye at the top, a sharp point, rust spots
    hx, hy = PARTS["hook"][:2]
    hook_dark = (22, 20, 22)
    hook_mid = (118, 120, 128)
    hook_lit = (196, 198, 204)
    a.ellipse(hx + 6, hy - 1, hx + 16, hy + 9, None, outline=hook_dark)
    a.ellipse(hx + 7, hy, hx + 15, hy + 8, None, outline=hook_lit)
    a.ellipse(hx + 8, hy + 1, hx + 14, hy + 7, None, outline=hook_mid)
    a.rect(hx + 9, hy + 8, hx + 13, hy + 17, hook_dark)
    a.rect(hx + 10, hy + 8, hx + 12, hy + 16, hook_mid)
    a.rect(hx + 10, hy + 8, hx + 10, hy + 16, hook_lit)
    # the bowl curls down from the shank and up the other side into the point (it opens right)
    cx, cy, r = hx + 15, hy + 19, 5
    pts = [(hx + 11, hy + 16)]
    for i in range(13):
        t = math.pi - math.pi * i / 12.0
        pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    pts.append((cx + r, cy - 6))
    a.line(pts, hook_dark, 5)
    a.line(pts, hook_mid, 3)
    a.line([(p[0], p[1] + 1) for p in pts[4:11]], (70, 72, 80), 1)
    a.line([(p[0] - 1, p[1]) for p in pts[11:]], hook_lit, 1)
    a.poly([(cx + r - 4, cy - 5), (cx + r + 1, cy - 12), (cx + r + 2, cy - 4)], hook_dark + (255,))
    a.poly([(cx + r - 2, cy - 5), (cx + r + 1, cy - 10), (cx + r + 1, cy - 5)], (226, 228, 232, 255))
    a.px(hx + 12, hy + 23, RUST_L)
    a.px(hx + 15, hy + 24, RUST)
    a.px(hx + 18, hy + 22, RUST)
    # chain links: an oval ring, and one seen edge-on
    lx, ly = PARTS["link_a"][:2]
    a.ellipse(lx, ly, lx + 5, ly + 7, None, outline=(140, 142, 150))
    a.px(lx + 1, ly + 1, (200, 202, 208))
    bx, by = PARTS["link_b"][:2]
    a.rect(bx, by, bx + 1, by + 7, (96, 98, 106))
    a.rect(bx, by, bx, by + 7, (170, 172, 180))
    # a locker door: louvers at the top, a handle, a number plate, dents
    dx, dy = PARTS["door"][:2]
    a.rect(dx, dy, dx + 29, dy + 59, LOCKER_D)
    a.rect(dx + 1, dy + 1, dx + 28, dy + 58, LOCKER)
    a.rect(dx + 1, dy + 1, dx + 28, dy + 1, LOCKER_L)
    a.rect(dx + 1, dy + 1, dx + 1, dy + 58, LOCKER_L)
    for y in range(dy + 5, dy + 17, 3):
        a.rect(dx + 7, y, dx + 22, y, (16, 22, 20))
        a.rect(dx + 7, y + 1, dx + 22, y + 1, LOCKER_L)
    for y in range(dy + 46, dy + 55, 3):
        a.rect(dx + 7, y, dx + 22, y, (16, 22, 20))
        a.rect(dx + 7, y + 1, dx + 22, y + 1, LOCKER_L)
    a.rect(dx + 23, dy + 26, dx + 25, dy + 34, (150, 150, 140))
    a.rect(dx + 23, dy + 26, dx + 23, dy + 34, (200, 200, 190))
    a.rect(dx + 10, dy + 20, dx + 19, dy + 24, (170, 160, 120))
    tiny_text(a, dx + 11, dy + 20, "13", (40, 30, 20)) if False else None
    a.rect(dx + 13, dy + 21, dx + 13, dy + 23, (40, 30, 20))
    a.rect(dx + 15, dy + 21, dx + 17, dy + 21, (40, 30, 20))
    a.rect(dx + 16, dy + 22, dx + 17, dy + 22, (40, 30, 20))
    a.rect(dx + 15, dy + 23, dx + 17, dy + 23, (40, 30, 20))
    claw_marks(a, dx + 5, dy + 30, 12, 1.2, rng)
    a.rect(dx, dy + 59, dx + 29, dy + 59, (20, 26, 24))
    # hands from under the sheets: pale, thin, long fingers (open, then closing)
    for name, curl in (("hand_open", 0.0), ("hand_shut", 1.0)):
        x0, y0 = PARTS[name][:2]
        a.poly([(x0 + 6, y0 + 27), (x0 + 12, y0 + 27), (x0 + 13, y0 + 14), (x0 + 5, y0 + 14)], FLESH_D + (255,))
        a.ellipse(x0 + 4, y0 + 10, x0 + 14, y0 + 18, FLESH)
        for k in range(4):
            fx = x0 + 4 + k * 3
            ln = 9 - abs(k - 1.5) * 1.5
            tip_x = fx + (k - 1.5) * 1.2 + curl * (2 if k < 2 else -2)
            tip_y = y0 + 12 - ln + curl * 5
            a.line([(fx + 1, y0 + 12), (tip_x, tip_y)], FLESH, 2)
            a.px(int(tip_x), int(tip_y), (220, 224, 232))
        a.line([(x0 + 4, y0 + 15), (x0 + 1, y0 + 10 + curl * 3)], FLESH, 2)
        a.line([(x0 + 6, y0 + 22), (x0 + 12, y0 + 22)], FLESH_D)
    # the tall shadow: a thin figure, a little hunched, a ragged sweater's hem, one hand
    # up with four long knife fingers (no hat)
    sx, sy = PARTS["shadow"][:2]
    k = (0, 0, 0)
    a.ellipse(sx + 22, sy + 8, sx + 36, sy + 24, k)                     # the head
    a.poly([(sx + 23, sy + 12), (sx + 21, sy + 18), (sx + 24, sy + 22)], k + (255,))
    a.poly([(sx + 26, sy + 22), (sx + 34, sy + 22), (sx + 33, sy + 28), (sx + 27, sy + 28)], k + (255,))   # neck
    a.poly([(sx + 16, sy + 30), (sx + 42, sy + 28), (sx + 44, sy + 72), (sx + 40, sy + 76),
            (sx + 36, sy + 73), (sx + 31, sy + 77), (sx + 26, sy + 72), (sx + 21, sy + 76), (sx + 15, sy + 70)], k + (255,))
    a.poly([(sx + 20, sy + 74), (sx + 28, sy + 74), (sx + 27, sy + 122), (sx + 22, sy + 122)], k + (255,))   # legs
    a.poly([(sx + 30, sy + 74), (sx + 38, sy + 74), (sx + 38, sy + 122), (sx + 33, sy + 122)], k + (255,))
    a.poly([(sx + 18, sy + 120), (sx + 28, sy + 120), (sx + 28, sy + 123), (sx + 16, sy + 123)], k + (255,))
    a.poly([(sx + 32, sy + 120), (sx + 42, sy + 120), (sx + 43, sy + 123), (sx + 32, sy + 123)], k + (255,))
    a.poly([(sx + 17, sy + 32), (sx + 21, sy + 34), (sx + 13, sy + 64), (sx + 9, sy + 70), (sx + 8, sy + 64)], k + (255,))  # the low arm
    for f in range(4):                                                   # its long fingers, down
        a.line([(sx + 9 + f, sy + 68), (sx + 4 + f * 3, sy + 92 + f)], k, 1)
    a.poly([(sx + 40, sy + 30), (sx + 44, sy + 32), (sx + 50, sy + 18), (sx + 46, sy + 14)], k + (255,))  # the raised arm
    for f in range(4):                                                   # the knife fingers, up and out
        t = -1.9 + f * 0.28
        a.line([(sx + 47, sy + 15), (sx + 47 + math.cos(t) * 26, sy + 15 + math.sin(t) * 26)], k, 1)
        a.px(int(sx + 47 + math.cos(t) * 26), int(sy + 15 + math.sin(t) * 26), (90, 90, 96))
    # a caged bulb
    ux, uy = PARTS["bulb"][:2]
    a.rect(ux + 4, uy, ux + 7, uy + 3, IRON)
    a.ellipse(ux + 2, uy + 3, ux + 9, uy + 13, (255, 236, 180))
    a.ellipse(ux + 4, uy + 5, ux + 7, uy + 10, (255, 252, 230))
    for x in (ux + 1, ux + 5, ux + 10):
        a.rect(x, uy + 3, x, uy + 14, IRON_L)
    a.rect(ux + 1, uy + 8, ux + 10, uy + 8, IRON_L)
    a.rect(ux + 2, uy + 14, ux + 9, uy + 15, IRON_L)
    # a valve wheel
    wx, wy = PARTS["wheel"][:2]
    valve_wheel(a, wx + 9, wy + 9, 8)
    a.save("boiler_parts.png")


def main():
    rows = read_map()
    rng = random.Random(4242)
    nrng = np.random.default_rng(4242)
    make_back(rows, rng, nrng)
    paint_front(rows, rng, nrng)
    make_parts(rng)
    print("wrote boiler_back.png, boiler_front.png, boiler_front_n.png, boiler_parts.png in %s" % OUT)


if __name__ == "__main__":
    main()
