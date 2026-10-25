#!/usr/bin/env python3
"""ComfyUI test set for Tower Brawl assets (2026-10-25, the user: "see what it's capable of").
Sends Z-Image Turbo and FLUX.2 klein graphs (Print Studio's tested settings: 8 / 4 steps, text
encoder on the CPU, tiled decode) to the capped ComfyUI on 127.0.0.1:8188, one at a time, and
copies each picture to OUT with its time; a flat (blank) picture is reported."""
import json, os, shutil, sys, time, urllib.request
from PIL import Image, ImageStat

URL = "http://127.0.0.1:8188"
OUT = os.environ.get("TB_COMFY_OUT", os.path.expanduser("~/.cache/tower-brawl-comfy"))   # pictures go here, not into the repo
COMFY_OUT = os.path.expanduser("~/ComfyUI/output")
os.makedirs(OUT, exist_ok=True)

def zimage(prompt, seed, w, h, prefix):
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "z_image_turbo_bf16.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "lumina2", "device": "cpu"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "z_image_ae.safetensors"}},
        "4": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 3.0}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "6": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["5", 0]}},
        "7": {"class_type": "EmptySD3LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "8": {"class_type": "KSampler", "inputs": {"model": ["4", 0], "positive": ["5", 0], "negative": ["6", 0],
                                                    "latent_image": ["7", 0], "seed": seed, "steps": 8, "cfg": 1.0,
                                                    "sampler_name": "res_multistep", "scheduler": "simple", "denoise": 1.0}},
        "9": {"class_type": "VAEDecodeTiled", "inputs": {"samples": ["8", 0], "vae": ["3", 0], "tile_size": 512,
                                                          "overlap": 64, "temporal_size": 64, "temporal_overlap": 8}},
        "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": prefix}},
    }

def klein(prompt, seed, w, h, prefix):
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux-2-klein-4b.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "flux2", "device": "cpu"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "5": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
        "6": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "7": {"class_type": "Flux2Scheduler", "inputs": {"steps": 4, "width": w, "height": h}},
        "8": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "9": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "10": {"class_type": "CFGGuider", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0], "cfg": 1.0}},
        "11": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["9", 0], "guider": ["10", 0], "sampler": ["8", 0],
                                                                  "sigmas": ["7", 0], "latent_image": ["6", 0]}},
        "12": {"class_type": "VAEDecodeTiled", "inputs": {"samples": ["11", 0], "vae": ["3", 0], "tile_size": 512,
                                                           "overlap": 64, "temporal_size": 64, "temporal_overlap": 8}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def post(graph):
    req = urllib.request.Request(URL + "/prompt", data=json.dumps({"prompt": graph}).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())["prompt_id"]

def wait(pid, limit=600):
    t0 = time.time()
    while time.time() - t0 < limit:
        with urllib.request.urlopen(f"{URL}/history/{pid}", timeout=10) as r:
            h = json.loads(r.read())
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                return None, st
            outs = h[pid].get("outputs", {})
            for node in outs.values():
                for im in node.get("images", []):
                    return im, st
        time.sleep(1.0)
    return None, {"timeout": True}


def run(jobs, seed_base=None, out=OUT):
    """jobs: [(name, model, w, h, prompt)]; returns {name: path} for the pictures that came out."""
    seed = seed_base if seed_base is not None else int(time.time()) % 100000
    done = {}
    for i, (name, model, w, h, prompt) in enumerate(jobs):
        t0 = time.time()
        prefix = f"tb_test/{name}"
        graph = zimage(prompt, seed + i, w, h, prefix) if model == "z" else klein(prompt, seed + i, w, h, prefix)
        im, st = wait(post(graph))
        if im is None:
            print(f"FAIL {name}: {json.dumps(st)[:300]}", flush=True)
            continue
        dst = os.path.join(out, name + ".png")
        shutil.copy(os.path.join(COMFY_OUT, im.get("subfolder", ""), im["filename"]), dst)
        sd = ImageStat.Stat(Image.open(dst).convert("L")).stddev[0]
        print(f"{'BLANK?' if sd < 4 else 'ok   '} {name}: {time.time() - t0:5.1f} s, {w}x{h}, contrast {sd:.0f}", flush=True)
        done[name] = dst
    return done
