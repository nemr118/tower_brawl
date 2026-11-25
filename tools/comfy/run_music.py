#!/usr/bin/env python3
"""p4.20 music (the user, 2026-11-24: "ACE-Step songs on the GPU"): a lobby tune, a match tune and a
winner's song, made by ACE-Step 1.5 XL in ComfyUI on the desktop card. The graph is the one the
violin songs proved (~/Work/violin_edm/tools/make_song.py acexl); only the words are new.

A card job: run it through batch.sh, never by hand, and with the 44G memory limit ACE-Step needs
(with 30G its text model is built on the card and runs out of memory at load):

    systemd-run --user --unit=tb-comfy --collect --setenv=TB_MEM_MAX=44G bash tools/comfy/batch.sh run_music.py
    python3 tools/comfy/run_music.py --dry         print the jobs, send nothing
    python3 tools/comfy/run_music.py lobby         one track (inside a batch)

Out: $TB_COMFY_OUT/music/<track>_s<seed>.flac (two seeds a track; a take that is there is skipped).
Then tools/comfy/make_music.py cuts the picked takes into the game's files. Nobody but a person
can say if a take is good: listen with  mpv ~/.cache/tower-brawl-comfy/music/NAME.flac"""
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request

COMFY = "http://127.0.0.1:8188"
OUT = os.path.join(os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy")), "music")
COMFY_OUT = os.path.expanduser("~/ComfyUI/output")
SEEDS = (1, 2)

# A track: how long, how fast, its key, what it is (ACE-Step's "tags"), and its words.
# "[Instrumental]" alone means nobody sings.
TRACKS = {
    "lobby": dict(
        seconds=76.0, bpm=104, key="G major",
        tags="Playful harvest festival hoedown and medieval tavern folk, instrumental, no vocals. A cheerful fiddle "
             "plays a catchy, bouncy melody over plucked banjo and lute, pizzicato strings, hand claps, tambourine, a "
             "light bouncy upright bass and a jaw harp boing now and then. 104 BPM, G major. Warm, cozy, silly and "
             "welcoming, like a cartoon barn dance or a family game night. Background music for a party game's lobby: "
             "steady, even energy from the first bar to the last, no long intro, no big build, no drop, no singing.",
        lyrics="[Instrumental]"),
    "match": dict(
        seconds=76.0, bpm=152, key="D major",
        tags="Fast, silly cartoon chase music, instrumental, no vocals. A frantic hoedown fiddle, fast banjo rolls, "
             "slap bass, spoons and washboard percussion, a punchy drum kit, kazoo and slide whistle stabs, short "
             "brass hits. 152 BPM, D major. Wild, funny and full of energy, like a cartoon chase or a pie fight. "
             "Battle music for a family party game: constant drive from the first beat, no long intro, no breakdown, "
             "no singing.",
        lyrics="[Instrumental]"),
    "winner": dict(
        seconds=24.0, bpm=126, key="C major",
        tags="A short, silly, triumphant victory jingle for a kids' Thanksgiving party game. A happy children's choir "
             "shouts and sings together with a goofy cartoon lead voice. Kazoos, fiddle, banjo, tuba oom-pah bass, "
             "hand claps, a big brass and drum finish. 126 BPM, C major. Joyful, funny, proud, very catchy. The "
             "singing starts right away.",
        lyrics="[Chorus - a happy kids' choir shouts and sings, starts at once]\n"
               "Winner, winner, turkey dinner!\n"
               "Gobble, gobble, hey!\n"
               "Pass the gravy, pass the pie,\n"
               "You won the brawl today!\n\n"
               "[Outro - kazoo fanfare, big finish]\n"
               "Gobble gobble!\n"),
    # p4.22 the Christmas season's three (bench/client/music.gd plays <name>_xmas in that season). Tunes of
    # their own: no carol is named, so none is copied.
    "lobby_xmas": dict(
        seconds=76.0, bpm=100, key="F major",
        tags="Cozy, playful Christmas toy workshop music, instrumental, no vocals. Sleigh bells jingle on every beat "
             "while a glockenspiel and a celesta play a catchy, bouncy melody over pizzicato strings, a plucked "
             "acoustic guitar, a warm clarinet, a light bouncy upright bass and soft brushed drums. 100 BPM, F major. "
             "Warm, silly and welcoming, like a cartoon on Christmas Eve or a family game night by the tree. "
             "Background music for a party game's lobby: steady, even energy from the first bar to the last, no long "
             "intro, no big build, no drop, no singing.",
        lyrics="[Instrumental]"),
    "match_xmas": dict(
        seconds=76.0, bpm=150, key="D major",
        tags="Fast, silly Christmas chase music, instrumental, no vocals. Galloping sleigh bells, quick xylophone and "
             "glockenspiel runs, pizzicato strings, punchy brass stabs, a tuba oom-pah bass, a snare drum and timpani "
             "rolls, a slide whistle now and then. 150 BPM, D major. Wild, funny and full of energy, like a cartoon "
             "snowball fight or a runaway sleigh ride. Battle music for a family party game: constant drive from the "
             "first beat, no long intro, no breakdown, no singing.",
        lyrics="[Instrumental]"),
    "winner_xmas": dict(
        seconds=24.0, bpm=126, key="C major",
        tags="A short, silly, triumphant victory jingle for a kids' Christmas party game. A happy children's choir "
             "shouts and sings together with a jolly, goofy cartoon lead voice. Sleigh bells, glockenspiel, kazoos, "
             "tuba oom-pah bass, hand claps, a big brass and drum finish. 126 BPM, C major. Joyful, funny, proud, "
             "very catchy. The singing starts right away.",
        lyrics="[Chorus - a happy kids' choir shouts and sings, starts at once]\n"
               "Ho ho ho, you won the brawl!\n"
               "Jingle, jingle, hey!\n"
               "Snowballs flying, presents too,\n"
               "You're on the nice list today!\n\n"
               "[Outro - sleigh bells, big brass finish]\n"
               "Ho ho ho!\n"),
}


def acexl(track, seed, prefix):
    """ACE-Step 1.5 XL sft, ComfyUI's template: 50 steps, cfg 7, euler, simple, AuraFlow shift 3."""
    t = TRACKS[track]
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "acestep_v1.5_xl_sft_bf16.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "DualCLIPLoader", "inputs": {"clip_name1": "qwen_0.6b_ace15.safetensors", "clip_name2": "qwen_4b_ace15.safetensors",
                                                        "type": "ace", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ace_1.5_vae.safetensors"}},
        "4": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 3.0}},
        "5": {"class_type": "TextEncodeAceStepAudio1.5", "inputs": {"clip": ["2", 0], "tags": t["tags"], "lyrics": t["lyrics"], "seed": seed,
                                                                  "bpm": t["bpm"], "duration": t["seconds"], "timesignature": "4",
                                                                  "language": "en", "keyscale": t["key"], "generate_audio_codes": True,
                                                                  "cfg_scale": 2.0, "temperature": 0.85, "top_p": 0.9, "top_k": 0, "min_p": 0.0}},
        "6": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["5", 0]}},
        "7": {"class_type": "EmptyAceStep1.5LatentAudio", "inputs": {"seconds": t["seconds"], "batch_size": 1}},
        "8": {"class_type": "KSampler", "inputs": {"model": ["4", 0], "seed": seed, "steps": 50, "cfg": 7.0, "sampler_name": "euler",
                                                   "scheduler": "simple", "positive": ["5", 0], "negative": ["6", 0],
                                                   "latent_image": ["7", 0], "denoise": 1.0}},
        "9": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveAudio", "inputs": {"audio": ["9", 0], "filename_prefix": prefix}},
    }


def call(path, data=None):
    req = urllib.request.Request(COMFY + path, data=json.dumps(data).encode() if data else None,
                                 headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=60))


def free():
    """Drop the loaded models (an out-of-memory retry starts clean). /free answers with an empty body."""
    try:
        req = urllib.request.Request(COMFY + "/free", data=json.dumps({"unload_models": True, "free_memory": True}).encode(),
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=60).read()
    except Exception as e:
        print("free failed:", e, flush=True)


def run(name, graph, limit=1800, again=2):
    """One take -> OUT/name.flac. Returns False only when ComfyUI itself is gone."""
    t0 = time.time()
    try:
        pid = call("/prompt", {"prompt": graph})["prompt_id"]
    except urllib.error.HTTPError as e:      # ComfyUI said no to the graph: report it, go on
        print(f"FAIL  {name}: {e} {e.read().decode(errors='replace')[:400]}", flush=True)
        return True
    except Exception as e:
        print(f"FAIL  {name}: {e}", flush=True)
        return False
    while time.time() - t0 < limit:
        try:
            h = call(f"/history/{pid}")
        except Exception as e:               # ComfyUI died (the watchdog?): stop, do not wait
            print(f"FAIL  {name}: ComfyUI stopped answering ({e})", flush=True)
            return False
        if pid in h and h[pid].get("status", {}).get("completed") is not None:
            break
        time.sleep(2)
    else:
        print(f"FAIL  {name}: took over {limit} s", flush=True)
        return True
    st = h[pid]["status"]
    if st.get("status_str") != "success":
        if again and "out of memory" in json.dumps(st):
            print(f"retry {name}: out of memory while loading, once more", flush=True)
            free()
            time.sleep(5)
            return run(name, graph, limit, again - 1)
        print(f"FAIL  {name}: {json.dumps(st)[:600]}", flush=True)
        return True
    for node in h[pid]["outputs"].values():
        for a in node.get("audio", []):
            shutil.copy(os.path.join(COMFY_OUT, a.get("subfolder", ""), a["filename"]), os.path.join(OUT, name + ".flac"))
            print(f"ok    {name}: {time.time() - t0:5.1f} s", flush=True)
            return True
    print(f"FAIL  {name}: no audio came out", flush=True)
    return True


def main():
    args = [a for a in sys.argv[1:] if a != "--dry"]
    dry = "--dry" in sys.argv
    bad = [a for a in args if a not in TRACKS]
    if bad:
        sys.exit(f"unknown: {bad}. Tracks: {list(TRACKS)}.")
    os.makedirs(OUT, exist_ok=True)
    if not dry:
        free()
    for track in args or list(TRACKS):
        for seed in SEEDS:
            name = f"{track}_s{seed}"
            if os.path.exists(os.path.join(OUT, name + ".flac")):
                print(f"have  {name}", flush=True)
                continue
            graph = acexl(track, seed, f"tower_brawl_music/{name}")
            if dry:
                t = TRACKS[track]
                print(f"job   {name}: {t['seconds']:.0f} s, {t['bpm']} BPM, {len(t['tags'].split())} prompt words, {len(t['lyrics'].splitlines())} lyric lines")
                continue
            if not run(name, graph):
                sys.exit(1)


if __name__ == "__main__":
    main()
