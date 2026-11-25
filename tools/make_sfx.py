#!/usr/bin/env python3
"""Tower Brawl's sounds, made here from nothing, never by hand (p4.19).

Every sound is a little recipe of plain maths: sine waves, hiss, and volume curves.
No recordings and no copied sounds. Run it again and the same files come out, so a
sound is tuned by changing a number here (a pitch in Hz, a length in seconds).

    python3 tools/make_sfx.py                 every sound, then the check
    python3 tools/make_sfx.py --only ko,boom  just these (the check still reads them all)
    python3 tools/make_sfx.py --list          the names and what they are for
    python3 tools/make_sfx.py --no-pictures   the table only (no matplotlib needed)
    (needs numpy; the pictures need matplotlib)

writes bench/assets/sfx/<name>.wav   mono, 16 bit, SR samples a second
       tools/sfx_check/table.md      each sound's length, peak, loudness, size
       tools/sfx_check/<name>.png    its wave and its spectrogram (which pitches, when)
       tools/sfx_check/sheet_N.png   all of them on a few pages

The page plays them with bench/client/sfx.gd. A new sound: write a make_ function,
add a line to SOUNDS, run this, then `godot --headless --path bench --import` (Godot
writes the .wav.import file beside it: set compress/mode=2 there, as the others have).

How loud: every sound is set to its own target (the third number in SOUNDS), measured
the way TV loudness is (K weighting, the loudest 0.2 s; the bass under 150 Hz is not
counted, a small speaker does not play it), and never peaks over PEAK_DB.
So nothing jumps out. A sound that should sit back gets a lower target.
"""
import argparse
import math
import os
import sys
import wave
import zlib

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "bench", "assets", "sfx")
CHECK = os.path.join(ROOT, "tools", "sfx_check")
SR = 32000            # samples a second (pitches up to 16 kHz: plenty for a phone or a TV)
TOP = 14500.0         # no pitched part above this (it would fold back as a false tone)
PEAK_DB = -6.0        # no sound's biggest sample goes over this (0 = the most a file can hold): half way, so several at once still fit
BASS_HZ = 150.0       # the loudness measure does not count what is under this (small speakers do not play it)
TAU = 2.0 * math.pi


# ------------------------------------------------------------------ small tools
def N(seconds):
    """How many samples last this long."""
    return int(round(seconds * SR))


def T(n):
    """The time of each of n samples, in seconds."""
    return np.arange(n) / SR


def glide(a, b, n):
    """A pitch that slides from a to b Hz over n samples (even steps to the ear)."""
    return a * (b / a) ** np.linspace(0.0, 1.0, n)


def bend(t, start, end, tau):
    """A pitch that starts at `start` Hz and settles on `end` within about 3 tau."""
    return end + (start - end) * np.exp(-t / tau)


def pluck(t, attack, tau):
    """A volume curve: up in `attack` seconds, then it dies away (tau: how fast)."""
    return np.minimum(t / attack, 1.0) * np.exp(-t / tau)


def hold(n, attack, release):
    """A volume curve: a soft start, flat, a soft end."""
    e = np.ones(n)
    a = max(1, min(N(attack), n // 2))
    r = max(1, min(N(release), n // 2))
    e[:a] = 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    e[n - r:] = 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    return e


def tone(freq, phase0=0.0):
    """A pure tone. freq: Hz, one number or one for every sample."""
    return np.sin(TAU * np.cumsum(freq) / SR + phase0)


def voice(freq, spec=None, harmonics=64):
    """A rich tone: the pitch `freq` plus its overtones (2x, 3x, ... the pitch).
    spec(fk, k) says how loud overtone k is (fk: its pitch in Hz, for every sample), so
    the colour of the sound can change while it plays. Overtones over TOP are left out."""
    freq = np.asarray(freq, dtype=float)
    ph = TAU * np.cumsum(freq) / SR
    out = np.zeros(len(freq))
    for k in range(1, harmonics + 1):
        fk = freq * k
        if fk.min() >= TOP:
            break
        a = (1.0 / k) if spec is None else spec(fk, k)
        out += a * np.clip((TOP - fk) / 1500.0, 0.0, 1.0) * np.sin(k * ph)
    return out


def peak_at(fk, centre, width):
    """Louder near `centre` Hz (a 'formant': what makes an 'ee' differ from an 'oo')."""
    x = (fk - centre) / (width * 0.5)
    return 1.0 / np.sqrt(1.0 + x * x)


def wah(fk, cutoff, q):
    """A filter with a bump at `cutoff` Hz and less above it. Slide the cutoff: 'wah'."""
    r = fk / cutoff
    return 1.0 / np.sqrt((1.0 - r * r) ** 2 + (r / q) ** 2)


def hiss(n, rng):
    """White noise: every pitch at once (the raw stuff of a whoosh or a splat)."""
    return rng.standard_normal(n) * 0.33


def drift(n, rng, hz):
    """A slow random wander around 0, about 1 big (hz: how fast it moves). It makes a
    voice a little unsteady, as a real one is."""
    d = svf(hiss(n, rng), hz)
    return d / (np.std(d) or 1.0)


def svf(x, cutoff, q=0.707, mode="lp"):
    """A filter whose cutoff may move while it runs. mode: lp (keep the low part),
    hp (keep the high part), bp (keep a band around the cutoff). q: how sharp."""
    n = len(x)
    fc = np.clip(np.broadcast_to(np.asarray(cutoff, dtype=float), (n,)), 20.0, SR * 0.45)
    g = np.tan(np.pi * fc / SR).tolist()
    k = 1.0 / q
    xs = x.tolist()
    out = [0.0] * n
    ic1 = ic2 = 0.0
    want = {"lp": 0, "bp": 1, "hp": 2}[mode]
    for i in range(n):
        gi = g[i]
        a1 = 1.0 / (1.0 + gi * (gi + k))
        a2 = gi * a1
        v3 = xs[i] - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + gi * a2 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        out[i] = v2 if want == 0 else (v1 * k if want == 1 else xs[i] - k * v1 - v2)
    return np.array(out)


def mix(dst, src, at=0.0, gain=1.0):
    """Add `src` into `dst`, starting `at` seconds in. Returns dst (longer if needed).
    The part's last few ms fade out, so a part that is cut short never ends in a click."""
    i = N(at)
    r = min(N(0.005), len(src) // 4)
    if r > 1:
        src = src.copy()
        src[-r:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    if i + len(src) > len(dst):
        dst = np.concatenate([dst, np.zeros(i + len(src) - len(dst))])
    dst[i:i + len(src)] += src * gain
    return dst


def tame(x, hz=5500.0):
    """Take the sharp edge off: less of everything above `hz`."""
    return svf(x, hz, 0.707, "lp")


def squash(x, drive):
    """Push a wave into a soft ceiling: it gets fatter and buzzier (drive: how hard)."""
    m = np.max(np.abs(x)) or 1.0
    return np.tanh(x / m * drive) / math.tanh(drive)


# ------------------------------------------------------------------ instruments
def kazoo(freq, rng):
    """A kazoo: a buzzy voice through the nose. freq: Hz for every sample."""
    n = len(freq)
    t = T(n)
    wobble = 1.0 + 0.012 * np.sin(TAU * 5.6 * t) + 0.004 * drift(n, rng, 30.0)
    v = voice(freq * wobble, lambda fk, k: (1.0 / k ** 0.6) * (0.3 + peak_at(fk, 1000.0, 700.0) + 0.9 * peak_at(fk, 2700.0, 1300.0)), 48)
    return tame(squash(v, 2.6), 6000.0)


def horn(freq, bright):
    """A toy trumpet. bright: Hz, how open it sounds (one number or one per sample)."""
    return voice(freq, lambda fk, k: (1.0 / k) * wah(fk, bright, 1.3) * (0.6 + 0.6 * peak_at(fk, 1250.0, 900.0)), 40)


def bell(hz, n, tau=0.12):
    """A toy glockenspiel bar: a clear ping with two off-key overtones."""
    t = T(n)
    out = np.sin(TAU * hz * t) * np.exp(-t / tau)
    for mult, gain, fast in ((2.76, 0.32, 0.45), (5.4, 0.14, 0.25)):
        if hz * mult < TOP:
            out += gain * np.sin(TAU * hz * mult * t) * np.exp(-t / (tau * fast))
    return out * np.minimum(t / 0.001, 1.0)


def whistle(freq, rng):
    """A slide whistle: an almost pure tone, a little breath."""
    n = len(freq)
    breath = svf(hiss(n, rng), freq, 6.0, "bp") * 0.5 + svf(hiss(n, rng), 5000.0, 0.7, "hp") * 0.04
    v = voice(freq, lambda fk, k: (1.0, 0.07, 0.03, 0.01)[k - 1], 4)
    return v + breath * 0.22


def bonk(rng, pitch=1.0):
    """A hollow knock, like a coconut."""
    n = N(0.16)
    t = T(n)
    out = tone(bend(t, 560.0, 450.0, 0.012) * pitch) * np.exp(-t / 0.042)
    out += 0.36 * np.sin(TAU * 1180.0 * pitch * t) * np.exp(-t / 0.018)
    out += 0.2 * np.sin(TAU * 1930.0 * pitch * t) * np.exp(-t / 0.009)
    out += 0.5 * svf(hiss(n, rng), 3000.0, 0.9, "bp") * np.exp(-t / 0.003)
    return out


def squeak(up=1.0, seconds=0.16):
    """A rubber toy's squeak: up fast, then it runs out of air."""
    n = N(seconds)
    t = T(n)
    u = t / seconds
    f = (1500.0 + 1250.0 * np.minimum(u / 0.22, 1.0) - 650.0 * np.clip((u - 0.35) / 0.65, 0.0, 1.0) ** 1.5) * up
    f = f * (1.0 + 0.02 * np.sin(TAU * 31.0 * t))
    v = voice(f, lambda fk, k: (1.0, 0.36, 0.15, 0.05)[k - 1], 4)
    return v * hold(n, 0.008, 0.05)


def gobble(rng, pulses, rate0, rate1, f_a, f_b, squawk=False, buzz=1.6):
    """A turkey: quick 'gl-gl-gl' pulses, each one falling in pitch, the whole call
    falling from f_a to f_b Hz. rate0 to rate1: pulses a second. squawk: a startled
    yelp first."""
    starts = []
    at = 0.13 if squawk else 0.0
    for i in range(pulses):
        starts.append(at)
        at += 1.0 / (rate0 + (rate1 - rate0) * i / max(1, pulses - 1))
    n = N(at + 0.03)
    t = T(n)
    f0 = np.full(n, float(f_b))
    amp = np.zeros(n)
    for i, t0 in enumerate(starts):
        per = (starts[i + 1] - t0) if i + 1 < pulses else 1.0 / rate1
        seg = (t >= t0) & (t < t0 + per)
        u = (t[seg] - t0) / per
        base = f_a * (f_b / f_a) ** (i / max(1, pulses - 1))
        f0[seg] = base * (1.3 - 0.45 * u)
        loud = 0.55 + 0.45 * math.sin(math.pi * min(1.0, (i + 1.2) / (pulses * 0.75)) * 0.5) if i < 3 else 1.0 - 0.5 * (i - 2) / max(1, pulses - 2)
        amp[seg] = np.sin(np.pi * np.minimum(u / 0.8, 1.0)) ** 1.3 * loud
    if squawk:      # "BWAK!": one quick rising yelp
        m = N(0.1)
        f0[:m] = glide(560.0, 1180.0, m)
        amp[:m] = hold(m, 0.006, 0.03) * 1.1
    v = voice(f0, lambda fk, k: (1.0 / k ** 0.5) * (0.15 + peak_at(fk, 1050.0, 520.0) + 0.9 * peak_at(fk, 2500.0, 950.0)), 40)
    rough = 1.0 + 0.25 * drift(n, rng, 140.0)
    out = tame(squash(v * amp * rough, buzz))
    return out + svf(hiss(n, rng), 2600.0, 1.0, "bp") * amp * 0.25


def notes(make, tune, tail=0.05):
    """Play a tune. make(hz, n, i) gives one note of n samples; tune: (start s, length s,
    Hz, loudness) for each note."""
    out = np.zeros(1)
    for i, (at, dur, hz, gain) in enumerate(tune):
        out = mix(out, make(hz, N(dur), i), at, gain)
    return np.concatenate([out, np.zeros(N(tail))])


def horn_note(hz, n, _i=0, bright=2600.0, vib=0.0):
    t = T(n)
    f = hz * (1.0 + vib * np.sin(TAU * 6.0 * t) * np.minimum(t / 0.15, 1.0))
    e = hold(n, 0.012, 0.035) * (0.85 + 0.15 * np.exp(-t / 0.05))
    return horn(f, 700.0 + (bright - 700.0) * e) * e


def kazoo_note(rng):
    def make(hz, n, _i=0):
        t = T(n)
        f = hz * (1.0 - 0.06 * np.exp(-t / 0.02))     # a little scoop up into each note
        return kazoo(f, rng) * hold(n, 0.012, 0.03)
    return make


# ------------------------------------------------------------------ the fight
def make_shoot(rng):
    """A bow let go: a low string that starts sharp and settles, and the arrow's 'thwip'."""
    n = N(0.3)
    t = T(n)
    string = voice(bend(t, 215.0, 185.0, 0.025), lambda fk, k: (1.0 / k ** 0.45) * np.exp(-t * (6.0 + 1.6 * k)), 30)
    thwip = svf(hiss(n, rng), glide(1500.0, 5200.0, n), 1.4, "bp") * pluck(t, 0.004, 0.035)
    return string * np.minimum(t / 0.0015, 1.0) + thwip * 3.0


def make_thunk(rng):
    """An arrow hits a wall: a low thud, a woody knock, and the shaft shivers."""
    n = N(0.2)
    t = T(n)
    thud = tone(bend(t, 300.0, 190.0, 0.02)) * np.exp(-t / 0.035)
    knock = 0.9 * np.sin(TAU * 540.0 * t) * np.exp(-t / 0.018) + 0.45 * np.sin(TAU * 1380.0 * t) * np.exp(-t / 0.009)
    click = svf(hiss(n, rng), 2200.0, 0.8, "bp") * np.exp(-t / 0.004)
    shiver = 0.2 * np.sin(TAU * 620.0 * t) * (0.5 + 0.5 * np.sin(TAU * 38.0 * t)) * np.exp(-t / 0.05)
    return thud * 0.8 + knock + click * 1.2 + shiver


def make_ko(rng):
    """A knockout: a bonk on the head, then a squeak."""
    out = mix(np.zeros(N(0.24)), bonk(rng), 0.0, 2.2)
    return mix(out, squeak(0.85), 0.06, 0.38)


def make_stomp(rng):
    """A stomp: 'boing'. A springy buzz whose mouth opens ('oi') and closes ('ng')."""
    n = N(0.42)
    t = T(n)
    u = t / 0.42
    f0 = glide(105.0, 160.0, n) * (1.0 + 0.03 * np.sin(TAU * 21.0 * t) * np.exp(-t / 0.2))
    mouth = 620.0 + 1700.0 * np.sin(np.pi * np.minimum(u / 0.75, 1.0)) ** 2 * (1.0 - 0.3 * u)
    spring = voice(f0, lambda fk, k: (1.0 / k ** 0.4) * (0.06 + peak_at(fk, mouth, 300.0)), 80)
    thump = tone(bend(t, 190.0, 85.0, 0.02)) * np.exp(-t / 0.03)
    return tame(spring, 5000.0) * pluck(t, 0.004, 0.17) + thump * 0.8


def make_dodge(rng):
    """A dodge: a quick whoosh, up and back."""
    n = N(0.24)
    u = np.linspace(0.0, 1.0, n)
    centre = np.where(u < 0.45, 450.0 * (2400.0 / 450.0) ** (u / 0.45), 2400.0 * (800.0 / 2400.0) ** ((u - 0.45) / 0.55))
    return svf(hiss(n, rng), centre, 1.8, "bp") * np.sin(np.pi * u ** 0.6) ** 2


def make_catch(rng):
    """An arrow caught: a snap of the fingers, and a tiny 'got it' blip."""
    n = N(0.13)
    t = T(n)
    snap = svf(hiss(n, rng), 2500.0, 1.2, "bp") * np.exp(-t / 0.011) + 0.5 * np.sin(TAU * 2300.0 * t) * np.exp(-t / 0.009)
    m = N(0.07)
    blip = tone(glide(1200.0, 1750.0, m)) * pluck(T(m), 0.003, 0.03)
    return mix(snap, blip, 0.022, 0.4)


def make_grab(rng):
    """Picking an arrow up from the floor: a soft little tick up."""
    n = N(0.07)
    t = T(n)
    return tone(glide(900.0, 1350.0, n)) * pluck(t, 0.003, 0.022)


def make_dry(rng):
    """Let go with an empty quiver: a dull 'thup'."""
    n = N(0.09)
    t = T(n)
    return tone(bend(t, 420.0, 260.0, 0.012)) * pluck(t, 0.002, 0.022) + 0.5 * svf(hiss(n, rng), 900.0, 0.8) * np.exp(-t / 0.008)


def make_tink(rng):
    """Two arrows meet in the air: a tiny metal 'ting'."""
    n = N(0.13)
    t = T(n)
    out = np.zeros(n)
    for hz, gain, tau in ((3300.0, 1.0, 0.045), (5270.0, 0.6, 0.03), (7100.0, 0.35, 0.018)):
        out += gain * np.sin(TAU * hz * t) * np.exp(-t / tau)
    return out * np.minimum(t / 0.0006, 1.0)


def make_powerup(rng):
    """A power-up taken: a sparkle. Five quick bells going up, then glitter."""
    out = np.zeros(N(0.55))
    for i, hz in enumerate((784.0, 1046.5, 1318.5, 1568.0, 2093.0)):
        out = mix(out, bell(hz, N(0.3), 0.11), 0.048 * i, 0.6 + 0.1 * i)
    for _ in range(14):
        m = N(0.09)
        ping = np.sin(TAU * rng.uniform(2800.0, 6000.0) * T(m)) * np.exp(-T(m) / 0.022)
        out = mix(out, ping, rng.uniform(0.16, 0.44), rng.uniform(0.06, 0.15))
    return out


def make_shield_pop(rng):
    """A shield breaks: a pop, then bits of glass."""
    n = N(0.26)
    t = T(n)
    out = 1.6 * tone(bend(t, 1000.0, 300.0, 0.014)) * np.exp(-t / 0.03) + svf(hiss(n, rng), 1800.0, 0.7, "hp") * np.exp(-t / 0.003) * 0.8
    for _ in range(6):
        m = N(0.1)
        out = mix(out, np.sin(TAU * rng.uniform(2200.0, 4800.0) * T(m)) * np.exp(-T(m) / 0.03), rng.uniform(0.02, 0.12), rng.uniform(0.08, 0.16))
    return out[:n]


def make_pop(rng):
    """A small pop: a kernel of popcorn, a pumpkin seed, a ghost."""
    n = N(0.07)
    t = T(n)
    return tone(glide(520.0, 1500.0, n)) * pluck(t, 0.001, 0.016) + 0.4 * svf(hiss(n, rng), 2500.0, 0.8, "bp") * np.exp(-t / 0.003)


def make_boom(rng):
    """A blast: a cartoon boom. A drum that drops in pitch, a crack, a rumble."""
    n = N(0.7)
    t = T(n)
    # (a small speaker plays nothing under about 150 Hz: the boom's body sits above that)
    drum = squash(tone(bend(t, 420.0, 150.0, 0.08)) * np.exp(-t / 0.2), 2.0)
    body = tone(bend(t, 700.0, 260.0, 0.06)) * np.exp(-t / 0.12)
    roar = svf(hiss(n, rng), bend(t, 3500.0, 400.0, 0.1), 0.8) * np.exp(-t / 0.16) * 6.0
    crack = hiss(n, rng) * np.exp(-t / 0.006) * 3.0
    rumble = svf(hiss(n, rng), 420.0, 1.5, "bp") * pluck(t, 0.03, 0.28) * 3.0
    return squash(0.5 * drum + 0.5 * body + roar + crack + rumble, 2.2)


def make_zap(rng):
    """Lightning strikes: a crack, an electric buzz that falls, a little thunder."""
    n = N(0.45)
    t = T(n)
    crack = hiss(n, rng) * np.exp(-t / 0.02) * 2.2
    buzz = voice(glide(1700.0, 140.0, n), None, 30) * np.sign(np.sin(TAU * 93.0 * t)) * np.exp(-t / 0.09) * 0.7
    thunder = svf(hiss(n, rng), 420.0, 0.7) * pluck(t, 0.02, 0.16) * 2.0
    return squash(crack + buzz + thunder, 1.8)


def make_poof(rng):
    """A puff: smoke, a poison cloud, a ghost cat going away."""
    n = N(0.26)
    t = T(n)
    return svf(hiss(n, rng), bend(t, 2000.0, 320.0, 0.07), 0.9) * pluck(t, 0.014, 0.075)


def make_freeze(rng):
    """Everyone freezes: icy bells running down, and ice crackling."""
    out = np.zeros(N(0.5))
    for i, hz in enumerate((4186.0, 3136.0, 2637.0, 2093.0, 1568.0)):
        out = mix(out, bell(hz, N(0.26), 0.09), 0.045 * i, 0.7)
    for _ in range(16):
        m = N(0.012)
        out = mix(out, svf(hiss(m, rng), 4000.0, 0.7, "hp") * np.exp(-T(m) / 0.002), rng.uniform(0.05, 0.4), rng.uniform(0.2, 0.5))
    return out


# ------------------------------------------------------------------ the match around it
def make_count(rng):
    """The countdown's 3, 2, 1: one round 'boop' (the page plays it three times)."""
    n = N(0.17)
    t = T(n)
    return (np.sin(TAU * 587.3 * t) + 0.25 * np.sin(TAU * 1174.7 * t) + 0.08 * np.sin(TAU * 2349.3 * t)) * pluck(t, 0.003, 0.06)


def make_fight(rng):
    """FIGHT: a toy trumpet's 'ta-DAA', up a fourth, with a bell on top."""
    out = notes(lambda hz, n, i: horn_note(hz, n, i, 3000.0, 0.006), ((0.0, 0.09, 392.0, 0.8), (0.1, 0.34, 523.3, 1.0)))
    out = mix(out, bell(1046.5, N(0.3), 0.1), 0.1, 0.35)
    return out


def make_round_win(rng):
    """A round is won: a short sting, three quick notes up and a bright one held."""
    tune = ((0.0, 0.075, 523.3, 0.8), (0.08, 0.075, 659.3, 0.85), (0.16, 0.075, 784.0, 0.9), (0.24, 0.42, 1046.5, 1.0))
    out = notes(lambda hz, n, i: horn_note(hz, n, i, 3200.0, 0.008), tune)
    for i, (at, _dur, hz, _g) in enumerate(tune):
        out = mix(out, bell(hz * 2.0, N(0.3), 0.1), at, 0.22 + 0.06 * i)
    return mix(out, horn_note(784.0, N(0.42), 0, 2600.0, 0.008), 0.24, 0.5)      # a fifth under the last note


def make_draw(rng):
    """A draw: the sad trombone. Four notes going down, 'wah wah wah waaah'."""
    out = np.zeros(1)
    for i, (at, dur, hz) in enumerate(((0.0, 0.3, 311.1), (0.32, 0.3, 293.7), (0.64, 0.3, 277.2), (0.96, 0.8, 261.6))):
        n = N(dur)
        t = T(n)
        u = t / dur
        f = hz * (1.0 - 0.02 * np.exp(-t / 0.03))
        if i == 3:          # the last note sags and shakes
            f = f * 2.0 ** (-0.16 * np.clip((u - 0.45) / 0.55, 0.0, 1.0) ** 2) * (1.0 + 0.012 * np.sin(TAU * 5.5 * t) * np.minimum(u / 0.3, 1.0))
        mouth = 450.0 + 1300.0 * np.sin(np.pi * np.minimum(u / (0.7 if i < 3 else 0.5), 1.0)) ** 2 * (1.0 if i < 3 else np.maximum(0.25, 1.0 - u * 0.6))
        v = voice(f, lambda fk, k: (1.0 / k) * wah(fk, mouth, 2.6), 40)
        out = mix(out, v * hold(n, 0.025, 0.07 if i < 3 else 0.3), at)
    return out


def make_fanfare(rng):
    """The match winner: a silly fanfare. A kazoo plays the old 'Charge!' bugle call, a
    toy trumpet and a tuba help, then a slide whistle, a bonk and a crash."""
    G4, C5, E5, G5 = 392.0, 523.3, 659.3, 784.0
    lead = ((0.0, 0.13, G4, 0.85), (0.15, 0.13, C5, 0.9), (0.3, 0.13, E5, 0.95), (0.45, 0.3, G5, 1.0),
            (0.8, 0.13, E5, 0.95), (0.95, 0.95, G5, 1.0))
    out = notes(kazoo_note(rng), lead)
    under = ((0.45, 0.3, E5, 0.5), (0.95, 0.95, E5, 0.5), (0.95, 0.95, C5, 0.4))
    out = mix(out, notes(lambda hz, n, i: horn_note(hz, n, i, 2400.0, 0.006), under), 0.0, 0.8)
    tuba = ((0.0, 0.14, 130.8, 1.0), (0.45, 0.28, 130.8, 1.0), (0.8, 0.13, 98.0, 1.0), (0.95, 0.5, 130.8, 1.0), (1.45, 0.4, 98.0, 0.9))
    out = mix(out, notes(lambda hz, n, i: horn_note(hz, n, i, 900.0), tuba), 0.0, 0.9)
    m = N(0.42)
    up = whistle(glide(520.0, 2100.0, m) * (1.0 + 0.02 * np.sin(TAU * 7.0 * T(m))), rng) * hold(m, 0.03, 0.04)
    out = mix(out, up, 1.92, 2.4)
    out = mix(out, bonk(rng, 0.9), 2.36, 1.3)
    stab = notes(lambda hz, n, i: horn_note(hz, n, i, 3200.0, 0.01), ((0.0, 0.38, 261.6, 0.8), (0.0, 0.38, C5, 0.9), (0.0, 0.38, E5, 0.8), (0.0, 0.38, G5, 0.9)))
    out = mix(out, stab, 2.38, 0.8)
    out = mix(out, kazoo_note(rng)(1046.5, N(0.38)), 2.38, 0.7)
    c = N(0.5)
    crash = svf(hiss(c, rng), 5500.0, 0.6, "hp") * pluck(T(c), 0.002, 0.13) * 1.6
    return mix(out, crash, 2.38, 1.0)


def make_phew(rng):
    """PHEW: a slide whistle going up (the round's winner got away with it)."""
    n = N(0.6)
    t = T(n)
    u = t / 0.6
    f = 480.0 * (1750.0 / 480.0) ** np.clip(u / 0.72, 0.0, 1.0) ** 1.5
    f = f * (1.0 + 0.022 * np.sin(TAU * 7.0 * t) * np.clip((u - 0.6) / 0.2, 0.0, 1.0))
    return whistle(f, rng) * hold(n, 0.035, 0.09)


def make_taunt(rng):
    """A player's taunt: a short buzzy 'gobble!' (the page plays it at 8 pitches, one a seat)."""
    return gobble(rng, 4, 12.5, 10.0, 470.0, 350.0, False, 2.4)


# ------------------------------------------------------------------ the Harvest season
def make_gobble(rng):
    """The turkey comes: 'gobble-obble-obble', eleven quick pulses running down."""
    return gobble(rng, 11, 17.0, 12.0, 560.0, 300.0)


def make_gobble_startled(rng):
    """The turkey is caught: a startled 'BWAK!' and a fast, higher gobble."""
    return gobble(rng, 6, 21.0, 16.0, 760.0, 480.0, True)


def make_splat(rng):
    """A pie lands: a wet splat, a plop, and drops."""
    n = N(0.4)
    t = T(n)
    wet = svf(hiss(n, rng), bend(t, 5200.0, 420.0, 0.05), 1.1) * pluck(t, 0.002, 0.07) * 3.2
    plop = 0.6 * tone(bend(t, 420.0, 160.0, 0.03)) * np.exp(-t / 0.05)
    squelch = svf(hiss(n, rng), 950.0, 4.0, "bp") * (0.5 + 0.5 * np.sin(TAU * 34.0 * t)) * pluck(t, 0.01, 0.06) * 1.2
    out = wet + plop + squelch
    for _ in range(7):
        m = N(0.04)
        hz = rng.uniform(700.0, 1900.0)
        out = mix(out, tone(glide(hz, hz * 1.7, m)) * pluck(T(m), 0.002, 0.011), rng.uniform(0.07, 0.3), rng.uniform(0.1, 0.24))
    return out[:n]


def make_wahwah(rng):
    """Covered in cream (or a dish's trick): a muted trumpet's 'wah-waaah', two notes down."""
    out = np.zeros(1)
    for i, (at, dur, hz) in enumerate(((0.0, 0.26, 466.2), (0.3, 0.5, 415.3))):
        n = N(dur)
        t = T(n)
        u = t / dur
        f = np.full(n, hz)
        if i == 1:          # the second note sags and shakes
            f = f * 2.0 ** (-0.12 * np.clip((u - 0.5) / 0.5, 0.0, 1.0) ** 2) * (1.0 + 0.012 * np.sin(TAU * 6.0 * t))
        mouth = 800.0 + 1500.0 * np.sin(np.pi * np.minimum(u / (0.75 if i == 0 else 0.55), 1.0)) ** 2 * (1.0 if i == 0 else np.maximum(0.3, 1.0 - 0.6 * u))
        v = voice(f, lambda fk, k: (1.0 / k ** 0.8) * wah(fk, mouth, 4.5) * (0.3 + peak_at(fk, 1500.0, 1400.0)), 30)
        out = mix(out, v * hold(n, 0.02, 0.06 if i == 0 else 0.2), at)
    return out


def make_lid(rng):
    """A dish's lid comes off: a clang of metal, then 'ta-da!'."""
    n = N(0.5)
    t = T(n)
    clang = np.zeros(n)
    for hz, gain, tau in ((640.0, 1.0, 0.2), (652.0, 0.6, 0.18), (1483.0, 0.8, 0.16), (2262.0, 0.6, 0.12), (2291.0, 0.4, 0.1),
                          (3310.0, 0.5, 0.09), (4571.0, 0.35, 0.06), (5830.0, 0.25, 0.045)):
        clang += gain * np.sin(TAU * hz * t + rng.uniform(0.0, TAU)) * np.exp(-t / tau)
    clang = clang * np.minimum(t / 0.0008, 1.0) + hiss(n, rng) * np.exp(-t / 0.003) * 1.5
    ta = notes(lambda hz, m, i: horn_note(hz, m, i, 3000.0, 0.008),
               ((0.0, 0.08, 392.0, 0.7), (0.0, 0.08, 493.9, 0.7), (0.0, 0.08, 587.3, 0.7),
                (0.11, 0.4, 523.3, 0.8), (0.11, 0.4, 659.3, 0.8), (0.11, 0.4, 784.0, 0.9)))
    out = mix(clang, ta, 0.24, 0.32)
    return mix(out, bell(1046.5, N(0.35), 0.12), 0.35, 0.5)


def make_crows(rng):
    """Crows: 'caw, caw, caw'. A harsh voice through the nose, each caw falling."""
    out = np.zeros(1)
    for at, dur, hz in ((0.0, 0.17, 540.0), (0.24, 0.17, 520.0), (0.48, 0.23, 500.0)):
        n = N(dur)
        t = T(n)
        u = t / dur
        f = hz * (1.06 - 0.2 * u ** 1.5) * (1.0 + 0.015 * drift(n, rng, 60.0))
        v = voice(f, lambda fk, k: (1.0 / k ** 0.4) * (0.1 + peak_at(fk, 1500.0, 650.0) + 0.8 * peak_at(fk, 3000.0, 1000.0)), 30)
        rasp = 0.55 + 0.45 * np.sign(np.sin(TAU * np.cumsum(f * 0.5) / SR))      # every other wave louder: a rasp
        caw = tame(squash(v * rasp, 2.2), 6000.0) + svf(hiss(n, rng), 2800.0, 0.9, "bp") * 0.5
        out = mix(out, caw * hold(n, 0.014, 0.06), at)
    return out


def make_gust(rng):
    """The gust of leaves: wind that swells and goes, and dry leaves ticking."""
    n = N(1.0)
    u = np.linspace(0.0, 1.0, n)
    swell = np.sin(np.pi * u ** 0.8) ** 2
    wind = svf(hiss(n, rng), 380.0 + 950.0 * swell, 1.3, "bp") * swell * 1.6 + svf(hiss(n, rng), 3000.0, 0.7, "hp") * swell * 0.12
    out = wind
    for _ in range(46):
        m = N(0.01)
        at = rng.uniform(0.1, 0.9)
        k = math.sin(math.pi * at) ** 2
        out = mix(out, svf(hiss(m, rng), 3500.0, 0.8, "hp") * np.exp(-T(m) / 0.0018), at, rng.uniform(0.15, 0.6) * k)
    return out[:n]


def make_peck(rng):
    """THE BIG TURKEY pecks: a quick hard 'tok'."""
    n = N(0.09)
    t = T(n)
    return tone(bend(t, 1350.0, 1050.0, 0.01)) * np.exp(-t / 0.016) + 0.4 * np.sin(TAU * 2900.0 * t) * np.exp(-t / 0.006) \
        + 0.6 * svf(hiss(n, rng), 3500.0, 0.8, "bp") * np.exp(-t / 0.002)


# ------------------------------------------------------------------ Halloween and the boiler room
def make_meow(rng):
    """The black cat: 'me-ow'. The pitch goes up then down, the mouth opens then closes."""
    n = N(0.5)
    t = T(n)
    u = t / 0.5
    f = 470.0 + 250.0 * np.sin(np.pi * np.minimum(u / 0.7, 1.0)) ** 1.5 - 60.0 * u
    f = f * (1.0 + 0.01 * np.sin(TAU * 6.5 * t))
    f1 = 650.0 + 500.0 * np.sin(np.pi * np.minimum(u / 0.8, 1.0))
    f2 = 2500.0 - 1500.0 * np.clip((u - 0.35) / 0.5, 0.0, 1.0)
    v = voice(f, lambda fk, k: (1.0 / k ** 0.7) * (0.08 + peak_at(fk, f1, 300.0) + 0.7 * peak_at(fk, f2, 450.0)), 30)
    return v * hold(n, 0.05, 0.14)


def make_bats(rng):
    """Bats: thin squeaks falling in pitch, and wings flapping."""
    n = N(0.6)
    t = T(n)
    out = svf(hiss(n, rng), 650.0, 1.0, "bp") * np.abs(np.sin(TAU * 6.5 * t)) ** 3 * hold(n, 0.05, 0.15) * 1.2
    at = 0.02
    while at < 0.52:
        m = N(0.03)
        out = mix(out, tone(glide(rng.uniform(4600.0, 5800.0), rng.uniform(2900.0, 3600.0), m)) * pluck(T(m), 0.002, 0.01), at, rng.uniform(0.4, 0.9))
        at += rng.uniform(0.035, 0.075)
    return out[:n]


def make_furnace(rng):
    """A furnace blasts: a roar of fire that flutters."""
    n = N(0.8)
    t = T(n)
    u = t / 0.8
    e = hold(n, 0.06, 0.3)
    flutter = 1.0 + 0.3 * np.sin(TAU * 23.0 * t + 2.0 * drift(n, rng, 8.0))
    roar = svf(hiss(n, rng), 400.0 + 1200.0 * np.sin(np.pi * u) ** 2, 0.9) * flutter * 2.4
    return (roar + 0.2 * voice(np.full(n, 110.0), None, 12)) * e


def make_steam(rng):
    """A pipe vents steam: a sharp hiss that fades."""
    n = N(0.6)
    t = T(n)
    h = tame(svf(hiss(n, rng), 1800.0, 0.7, "hp"), 7000.0) + svf(hiss(n, rng), 3800.0, 2.0, "bp") * 0.8
    return h * pluck(t, 0.008, 0.2) + 0.06 * tone(glide(3200.0, 2700.0, n)) * pluck(t, 0.02, 0.15)


# ------------------------------------------------------------------ the lobby
def make_click(rng):
    """A button: a soft click."""
    n = N(0.045)
    t = T(n)
    return 0.6 * np.sin(TAU * 1500.0 * t) * np.exp(-t / 0.005) + np.sin(TAU * 760.0 * t) * np.exp(-t / 0.009) \
        + 0.3 * svf(hiss(n, rng), 3000.0, 0.8, "bp") * np.exp(-t / 0.002)


def make_join(rng):
    """A player joins: a friendly two-note blip, going up."""
    out = np.zeros(N(0.22))
    for at, hz, tau in ((0.0, 659.3, 0.035), (0.075, 987.8, 0.05)):
        m = N(0.14)
        t = T(m)
        out = mix(out, (np.sin(TAU * hz * t) + 0.18 * np.sin(TAU * 3.0 * hz * t)) * pluck(t, 0.004, tau), at)
    return out


# name, maker, loudness target (K weighted, the loudest 0.2 s), what it is for
SOUNDS = [
    ("shoot", make_shoot, -22.0, "a bow let go (a twang)"),
    ("thunk", make_thunk, -22.0, "an arrow hits a wall"),
    ("ko", make_ko, -18.0, "a knockout (a bonk and a squeak)"),
    ("stomp", make_stomp, -19.0, "a stomp (a boing)"),
    ("dodge", make_dodge, -24.0, "a dodge (a whoosh)"),
    ("catch", make_catch, -20.0, "an arrow caught (a snap)"),
    ("grab", make_grab, -27.0, "your own arrow picked up from the floor"),
    ("dry", make_dry, -26.0, "let go with an empty quiver"),
    ("tink", make_tink, -27.0, "two arrows meet in the air"),
    ("powerup", make_powerup, -20.0, "a power-up taken (a sparkle)"),
    ("shield_pop", make_shield_pop, -19.0, "a shield breaks (a pop)"),
    ("pop", make_pop, -23.0, "a small pop (popcorn, a seed, a ghost)"),
    ("boom", make_boom, -17.0, "a blast (a cartoon boom)"),
    ("zap", make_zap, -20.0, "lightning strikes"),
    ("poof", make_poof, -25.0, "a puff of smoke or poison"),
    ("freeze", make_freeze, -21.0, "FREEZE"),
    ("count", make_count, -20.0, "the countdown's 3, 2, 1"),
    ("fight", make_fight, -19.0, "FIGHT"),
    ("round_win", make_round_win, -19.0, "a round is won (a short sting)"),
    ("draw", make_draw, -20.0, "a draw (the sad trombone)"),
    ("fanfare", make_fanfare, -19.0, "the match winner (a silly fanfare)"),
    ("phew", make_phew, -18.0, "PHEW (a slide whistle up)"),
    ("taunt", make_taunt, -20.0, "a player's taunt (8 pitches)"),
    ("gobble", make_gobble, -20.0, "the turkey comes"),
    ("gobble_startled", make_gobble_startled, -19.0, "the turkey is caught, THE BIG TURKEY is knocked down"),
    ("splat", make_splat, -19.0, "a pie lands"),
    ("wahwah", make_wahwah, -20.0, "covered in cream, a dish's trick"),
    ("lid", make_lid, -20.0, "a dish's lid (a clang and a ta-da)"),
    ("crows", make_crows, -20.0, "CROWS"),
    ("gust", make_gust, -22.0, "the gust of leaves"),
    ("peck", make_peck, -22.0, "THE BIG TURKEY pecks"),
    ("meow", make_meow, -21.0, "the black cat"),
    ("bats", make_bats, -22.0, "bats"),
    ("furnace", make_furnace, -19.0, "a furnace blasts"),
    ("steam", make_steam, -23.0, "a pipe vents steam"),
    ("click", make_click, -28.0, "a lobby button (a soft click)"),
    ("join", make_join, -23.0, "a player joins (a blip)"),
]


# ------------------------------------------------------------------ loudness, and the file
def _k_weight(x):
    """The 'K' filter of TV loudness (ITU BS.1770): a little more treble. One change: the
    bass under BASS_HZ is left out, as a phone's or a TV's small speaker leaves it out, so a
    sound is not called loud for a thud nobody will hear."""
    n = len(x) + SR // 2
    f = np.fft.rfftfreq(n, 1.0 / SR)
    z = np.exp(-1j * TAU * f / SR)
    w0 = TAU * 1500.0 / SR
    A = 10.0 ** (4.0 / 40.0)
    al = math.sin(w0) / (2.0 * math.sqrt(0.5))
    c = math.cos(w0)
    b = (A * ((A + 1) + (A - 1) * c + 2 * math.sqrt(A) * al), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - 2 * math.sqrt(A) * al))
    a = ((A + 1) - (A - 1) * c + 2 * math.sqrt(A) * al, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - 2 * math.sqrt(A) * al)
    h1 = (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
    w0 = TAU * BASS_HZ / SR
    al = math.sin(w0) / (2.0 * 0.7071)
    c = math.cos(w0)
    h2 = ((1 + c) / 2 - (1 + c) * z + (1 + c) / 2 * z * z) / ((1 + al) - 2 * c * z + (1 - al) * z * z)
    return np.fft.irfft(np.fft.rfft(x, n) * h1 * h2, n)


def loudness(x):
    """How loud a sound is to the ear, in dB: K weighted, the loudest 0.2 s of it.
    (A very short sound scores low, as it sounds: the ear needs time to hear loud.)"""
    y = _k_weight(x)
    win = N(0.2)
    sq = np.concatenate([[0.0], np.cumsum(y * y)])
    if len(y) <= win:
        best = sq[-1] / win
    else:
        best = np.max(sq[win:] - sq[:-win]) / win
    return -0.691 + 10.0 * math.log10(max(best, 1e-12))


def db(v):
    return 20.0 * math.log10(max(v, 1e-9))


def finish(x, target):
    """Make a raw sound ready: no offset, no silence after it, no click at either end,
    the loudness set to `target`, the peak under PEAK_DB."""
    x = np.asarray(x, dtype=float)
    x = x - svf(x, 25.0, 0.707, "lp")                     # no slow drift (a DC offset is a thump)
    quiet = np.max(np.abs(x)) * 10.0 ** (-55.0 / 20.0)
    last = np.nonzero(np.abs(x) > quiet)[0]
    x = x[:min(len(x), last[-1] + N(0.012))]              # cut the silence after it
    a, r = N(0.0006), N(0.008)
    x[:a] *= np.linspace(0.0, 1.0, a)                     # the first and last samples are zero: no click
    x[-r:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    bump = np.hanning(len(x))                             # what offset is left goes as one slow, silent hump
    x -= bump * (np.mean(x) / np.mean(bump))
    cap = 10.0 ** (PEAK_DB / 20.0)
    for _ in range(6):                                    # louder, into a soft ceiling, until it measures right
        x = x * 10.0 ** ((target - loudness(x)) / 20.0)
        p = np.max(np.abs(x))
        if p <= cap:
            break
        knee = cap * 0.6
        over = np.abs(x) > knee
        x[over] = np.sign(x[over]) * (knee + (cap - knee) * np.tanh((np.abs(x[over]) - knee) / (cap - knee)))
    x[-1] = 0.0
    return x


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2, path
        rate = w.getframerate()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")
    return pcm, rate


# ------------------------------------------------------------------ the check
def check(pictures):
    """Read every file back and measure it: the table, and a picture each."""
    os.makedirs(CHECK, exist_ok=True)
    rows = []
    bad = []
    waves = {}
    for name, _make, target, what in SOUNDS:
        path = os.path.join(OUT, name + ".wav")
        if not os.path.exists(path):
            bad.append("%s: no file" % name)
            continue
        pcm, rate = read_wav(path)
        x = pcm / 32768.0
        waves[name] = x
        peak = np.max(np.abs(x))
        clipped = int(np.sum(np.abs(pcm.astype(int)) >= 32767))
        dc = float(np.mean(x))
        row = {"name": name, "what": what, "secs": len(x) / rate, "peak": db(peak), "rms": db(math.sqrt(float(np.mean(x * x)))),
               "loud": loudness(x), "target": target, "dc": dc, "clipped": clipped, "first": int(pcm[0]), "last": int(pcm[-1]),
               "bytes": os.path.getsize(path), "rate": rate}
        rows.append(row)
        if clipped:
            bad.append("%s: %d samples at full scale (clipping)" % (name, clipped))
        if abs(dc) > 0.002:
            bad.append("%s: a DC offset of %.4f" % (name, dc))
        if abs(int(pcm[0])) > 40 or abs(int(pcm[-1])) > 40:
            bad.append("%s: does not start or end at zero (%d, %d): a click" % (name, pcm[0], pcm[-1]))
        if peak > 10.0 ** (PEAK_DB / 20.0) + 0.002:
            bad.append("%s: peak %.1f dB is over %.1f" % (name, db(peak), PEAK_DB))
        if rate != SR:
            bad.append("%s: %d Hz, not %d" % (name, rate, SR))
    total_s = sum(r["secs"] for r in rows)
    total_b = sum(r["bytes"] for r in rows)
    lines = ["# The sounds (tools/make_sfx.py writes this; do not edit)", "",
             "Mono, 16 bit, %d Hz. peak: the biggest sample (0 dB is the most a file holds; none may pass %.0f). "
             "rms: the average level. loud: K weighted with no bass under %d Hz, the loudest 0.2 s (what the ear hears from a small speaker; the target is beside it). "
             "DC: the wave's average (0 is right). first/last: the first and last sample of 32767 (0 = no click)." % (SR, PEAK_DB, int(BASS_HZ)), "",
             "| sound | for | s | peak dB | rms dB | loud | target | DC | clipped | first/last | bytes |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append("| %s | %s | %.2f | %.1f | %.1f | %.1f | %.0f | %.4f | %d | %d/%d | %d |" % (
            r["name"], r["what"], r["secs"], r["peak"], r["rms"], r["loud"], r["target"], r["dc"], r["clipped"], r["first"], r["last"], r["bytes"]))
    lines += ["", "%d sounds, %.1f s and %d bytes in all (%.2f MB as .wav files; the game's pack holds them smaller, see the patch page)." % (
        len(rows), total_s, total_b, total_b / 1048576.0), "",
        "Problems: " + ("none" if not bad else "; ".join(bad)), ""]
    with open(os.path.join(CHECK, "table.md"), "w") as f:
        f.write("\n".join(lines))
    print("\n".join(lines[4:]))
    if pictures:
        _pictures(waves, rows)
    return not bad


def _pictures(waves, rows):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    def draw(ax_w, ax_s, r, small):
        x = waves[r["name"]]
        t = np.arange(len(x)) / SR
        ax_w.plot(t, x, lw=0.5, color="#1f5fa8")
        ax_w.set_ylim(-1.0, 1.0)
        ax_w.set_xlim(0.0, max(t[-1], 0.02))
        ax_w.set_title("%s  %.2f s  peak %.1f dB  loud %.1f" % (r["name"], r["secs"], r["peak"], r["loud"]), fontsize=7 if small else 9, pad=2)
        ax_w.tick_params(labelsize=5, length=2)
        ax_w.set_xticklabels([])
        nfft = 256 if len(x) < 4000 else 512
        hush = np.random.default_rng(1).standard_normal(len(x)) * 1e-6      # so that pure silence draws black, not blank
        ax_s.specgram(x + hush, NFFT=nfft, Fs=SR, noverlap=nfft - nfft // 8, cmap="magma", vmin=-110, vmax=-30)
        ax_s.set_ylim(0, 12000)
        ax_s.set_xlim(0.0, max(t[-1], 0.02))
        ax_s.tick_params(labelsize=5, length=2)

    for r in rows:
        fig, (a1, a2) = plt.subplots(2, 1, figsize=(4.8, 3.0), dpi=90, gridspec_kw={"height_ratios": [1, 1.6]})
        draw(a1, a2, r, False)
        fig.tight_layout(pad=0.4)
        fig.savefig(os.path.join(CHECK, r["name"] + ".png"))
        plt.close(fig)
    per = 20
    for page in range((len(rows) + per - 1) // per):
        part = rows[page * per:(page + 1) * per]
        fig = plt.figure(figsize=(16, 10), dpi=90)
        for i, r in enumerate(part):
            col, row = i % 5, i // 5
            a1 = fig.add_axes([0.03 + col * 0.195, 0.955 - row * 0.245 - 0.065, 0.175, 0.055])
            a2 = fig.add_axes([0.03 + col * 0.195, 0.955 - row * 0.245 - 0.2, 0.175, 0.125])
            draw(a1, a2, r, True)
        fig.savefig(os.path.join(CHECK, "sheet_%d.png" % (page + 1)))
        plt.close(fig)
    print("pictures: %s/<name>.png and sheet_N.png" % CHECK)


def main():
    ap = argparse.ArgumentParser(description="Make Tower Brawl's sounds and check them.")
    ap.add_argument("--only", default="", help="names, comma separated: make just these")
    ap.add_argument("--list", action="store_true", help="print the names and stop")
    ap.add_argument("--no-pictures", action="store_true", help="the table only")
    ap.add_argument("--check-only", action="store_true", help="make nothing, measure the files that are there")
    a = ap.parse_args()
    if a.list:
        for name, _make, target, what in SOUNDS:
            print("%-16s %5.0f  %s" % (name, target, what))
        return 0
    only = [s for s in a.only.split(",") if s]
    unknown = [s for s in only if s not in [r[0] for r in SOUNDS]]
    if unknown:
        print("no such sound:", ", ".join(unknown), file=sys.stderr)
        return 2
    os.makedirs(OUT, exist_ok=True)
    if not a.check_only:
        for i, (name, make, target, _what) in enumerate(SOUNDS):
            if only and name not in only:
                continue
            rng = np.random.default_rng(zlib.crc32(name.encode()))     # the same hiss every run: the same file
            x = finish(make(rng), target)
            if i % 2 == 1:
                x = -x      # every second sound upside down: it sounds the same, and two that start together do not pile up
            write_wav(os.path.join(OUT, name + ".wav"), x)
            print("made", name, flush=True)
    return 0 if check(not a.no_pictures) else 1


if __name__ == "__main__":
    sys.exit(main())
