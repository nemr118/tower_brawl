# ComfyUI pictures for the game (2026-10-25)

These scripts made the game's ComfyUI pictures: the 17 power-up pictures (`bench/assets/pu_icons.png`), the 46 award pictures (`bench/assets/award_art.png`) and the loading picture (`bench/assets/splash.png`, from FLUX.2 klein).

**The GPU on this PC can freeze the whole machine. Ask the user before any run.** Start ComfyUI the safe way (a memory cap, a watchdog, a RAM limit), from `~/Work/vam_restyle`:

    systemd-run --user --scope -q -p MemoryMax=30G env VR_COMFY_ROOT=$HOME/ComfyUI \
      VR_COMFY_PY=$HOME/ComfyUI/venv-py312/bin/python VR_VRAM_FRACTION=0.50 VR_FP8=1 VR_COMFY_EXTRA="" tools/comfy.sh start

That ran at a 10.9 GB peak, 12 to 40 s a picture (the text encoder runs on the CPU). Stop it after: `tools/comfy.sh stop`.

- `comfy_lib.py`: the Z-Image Turbo and FLUX.2 klein graphs (Print Studio's tested settings) and `run(jobs)`.
- `run_icons.py [kinds]`, then `cut_icons.py`: the power-up pictures (cut off their background by a fill from the edges), then a 64 px sheet with a white edge.
- `run_awards.py [slugs]`, then `cut_awards.py`: the award pictures, 80 px, 8 a row, in `client/award_art.gd`'s ORDER.

Pictures go to `~/.cache/tower-brawl-comfy` (or `$TB_COMFY_OUT`), never into the repo. Look at every picture at the game's size before it goes in, and show the user BEFORE/AFTER first.

**2026-10-26 batch** (the user picked all four jobs): `batch.sh` waits for the card (other projects' units in `TB_WAIT_UNITS` gone, under 3.2 GB in use), takes the PC's shared card lock (`/tmp/sr6_pc_gpu.lock`), starts ComfyUI the safe way, runs the jobs and stops it; start it as a user service (`systemd-run --user --unit=tb-comfy --collect env TB_WAIT_UNITS=... bash tools/comfy/batch.sh run_cards.py ...`). The jobs: `run_cards.py` (the lobby's arena cards, 4 tries an arena, FLUX.2 klein), `run_splash.py` (the year-round loading picture, 6 tries), `run_tricks.py` (the candy tricks' badges, Z-Image Turbo), `run_backdrops.py` (a pixel-style castle far backdrop). `pick_sheets.py` makes the sheets to pick from (the logo goes on the loading pictures; the badges are cut out; the backdrops brought to 480 x 270). 44 pictures took 4 minutes once the card was free.
