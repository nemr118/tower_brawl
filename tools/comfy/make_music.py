#!/usr/bin/env python3
"""p4.20 music: the game's three songs from the picked ACE-Step takes (tools/comfy/run_music.py).
No card: ffmpeg only.

    python3 tools/comfy/make_music.py                  every song, from the picks below
    python3 tools/comfy/make_music.py --pick match=2   another take of one song (seed 2), then cut all
    python3 tools/comfy/make_music.py --check          numbers for every take and every cut file

What it does to a take:
- the lobby's and the match's song are cut to a whole number of bars (the game starts a song again
  when it ends, so the cut should fall on a bar line), with a short fade at the end;
- the winner's song keeps its length, with a fade at the end;
- every song gets the same loudness (quieter than the sound effects), no peak near full scale;
- one channel, 32 kHz, 16 bit .wav in bench/assets/music/ (Godot packs it as QOA, like the sound
  effects; a minute of song is about 0.8 MB in the pack and 8 MB in the page while it plays).

Nobody but a person can say if a take is good. Listen to the takes:
    mpv ~/.cache/tower-brawl-comfy/music/lobby_s1.flac     (and _s2; match_s1, match_s2; winner_s1, winner_s2)
After a change: godot --headless --path bench --import, then a build."""
import json
import os
import re
import subprocess
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.."))
TAKES = os.path.join(os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy")), "music")
OUT = os.path.join(REPO, "bench/assets/music")
PICKS_FILE = os.path.join(REPO, "tools/comfy/music_picks.json")
# a song: its speed (run_music.py's), how many bars to keep (0: all of it), its loudness (LUFS)
SONGS = {
    "lobby": dict(bpm=104, bars=28, lufs=-20.0, fade=1.2),
    "match": dict(bpm=152, bars=40, lufs=-20.0, fade=1.2),
    "winner": dict(bpm=126, bars=0, lufs=-18.0, fade=0.8),
    # p4.22 the Christmas season's (run_music.py lobby_xmas match_xmas winner_xmas); left out while their takes are not there
    "lobby_xmas": dict(bpm=100, bars=28, lufs=-20.0, fade=1.2),
    "match_xmas": dict(bpm=150, bars=40, lufs=-20.0, fade=1.2),
    "winner_xmas": dict(bpm=126, bars=0, lufs=-18.0, fade=0.8),
}


def picks():
    p = {k: 1 for k in SONGS}
    if os.path.exists(PICKS_FILE):
        p.update(json.load(open(PICKS_FILE)))
    return p


def numbers(path):
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                               capture_output=True, text=True).stdout.strip() or 0)
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    summary = err.split("Summary:")[-1]
    lufs = re.search(r"I:\s*(-?[\d.]+) LUFS", summary)
    peak = re.search(r"Peak:\s*(-?[\d.]+) dBFS", summary)
    return dur, float(lufs.group(1)) if lufs else None, float(peak.group(1)) if peak else None


def cut(name, seed):
    s = SONGS[name]
    src = os.path.join(TAKES, f"{name}_s{seed}.flac")
    if not os.path.exists(src):
        sys.exit(f"no take {src}: run tools/comfy/run_music.py (a card job) first")
    dur = numbers(src)[0]
    length = s["bars"] * 240.0 / s["bpm"] if s["bars"] > 0 else dur - 0.4
    length = min(length, dur - 0.1)
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name + ".wav")
    tmp = dst + ".tmp.wav"
    shape = f"atrim=0:{length:.3f},afade=t=in:d=0.03,afade=t=out:st={length - s['fade']:.3f}:d={s['fade']}"
    # first the cut alone, to measure it; then the same cut with the gain that brings it to its
    # loudness (never so much that a peak comes within 1.5 dB of full scale)
    for af, to in ((shape, tmp), (None, dst)):
        if af is None:
            _, l0, p0 = numbers(tmp)
            gain = min(s["lufs"] - l0, -1.5 - p0)
            af = f"{shape},volume={gain:.2f}dB"
        r = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-af", af, "-ac", "1", "-ar", "32000",
                            "-c:a", "pcm_s16le", to], capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"ffmpeg failed on {name}: {r.stderr[-400:]}")
    os.remove(tmp)
    d, l, p = numbers(dst)
    print(f"ok    {name}: take {seed}, {d:.1f} s, {l} LUFS, peak {p} dB, {os.path.getsize(dst) // 1024} KB as .wav")


def main():
    args = sys.argv[1:]
    if "--check" in args:
        for f in sorted(os.listdir(TAKES)) if os.path.isdir(TAKES) else []:
            if f.endswith(".flac"):
                d, l, p = numbers(os.path.join(TAKES, f))
                print(f"take  {f[:-5]:12} {d:6.1f} s  {l} LUFS  peak {p} dB")
        for name in SONGS:
            f = os.path.join(OUT, name + ".wav")
            if os.path.exists(f):
                d, l, p = numbers(f)
                print(f"game  {name:12} {d:6.1f} s  {l} LUFS  peak {p} dB  (take {picks()[name]})")
        return
    p = picks()
    for i, a in enumerate(args):
        if a == "--pick" and i + 1 < len(args):
            k, v = args[i + 1].split("=")
            if k not in SONGS:
                sys.exit(f"unknown song {k}: {list(SONGS)}")
            p[k] = int(v)
    json.dump(p, open(PICKS_FILE, "w"), indent=1, sort_keys=True)
    for name in SONGS:
        if name.endswith("_xmas") and not os.path.exists(os.path.join(TAKES, f"{name}_s{p[name]}.flac")):
            print(f"skip  {name}: no take yet (a card job: run_music.py {name})")
            continue
        cut(name, p[name])


if __name__ == "__main__":
    main()
