# The server laptop

An old laptop runs the game server so the main PC stays free to play. It has no desktop. It boots straight to a text screen.

## What is on it

- Arch Linux, `linux-lts` kernel, hostname `towerbrawl`. User `nemr` with sudo.
- The SSD holds the system. The 1 TB drive is mounted at `/storage` for backups and media.
- The game lives in `~/tower_brawl` (server script, certs, `build/web`, `tools/`, a venv for the deck).
- `towerbrawl.service` starts the game server at boot and restarts it if it dies.
- The lid can be closed. Sleep is off.
- The screen logs in by itself and opens a one-window graphical terminal (`cage` + `foot`, JetBrainsMono Nerd Font, the Omarchy colours, so it looks like the PC's deck). It prints a help box with the play link and every command, then opens the deck (`tbdash --controls`). If the graphics fail, it falls back to the plain text console.
- The deck has a SERVER panel at the top: the play link, buttons for **+ bot**, **- bot**, **clear bots** and **wifi help**. Keys do the same: `a`, `r`, `x`, `w`. Press `q` to leave the deck and get a shell; `tbdash` brings it back, `tbhelp` prints the box again.
- Bots are real headless Godot players with a bot brain (`tools/tbbot.py`, alias `tbbot`). Up to 4. Godot and the game source live on the laptop for this.

## At a new house

1. Plug in power and an ethernet cable to the router.
2. Turn it on. Wait for the TOWER BRAWL SERVER box on the screen. The deck opens a few seconds later.
3. Everyone types the **Play** link from the box into their phone. Accept the "not secure" warning once.

## Push a new build from the main PC

```
./bump_build.sh --title "..."          # as usual
tools/deploy_laptop.sh <laptop ip>     # copies the build + source, restarts the service (asks the laptop's sudo password)
TB_SUDO_PASS=... tools/deploy_laptop.sh <laptop ip>   # the same with no prompt (a script or an agent)
```

Finding the laptop's address from the PC when the screen is not in view: `ip neigh | grep -i 08:60:6e` after a ping sweep of the subnet (its MAC is `08:60:6e:09:b4:a7`). On 2026-09-07 at home it was `192.168.4.29`.

Check: the deck header on the laptop screen shows the new version, and `https://<ip>:8443/play` lands on `index_v<version>.html`.

## Useful commands on the laptop (or over ssh nemr@<ip>)

- `tbdash` — the deck.
- `tblog` — follow the server log.
- `sudo systemctl restart towerbrawl` — restart the game server.
- Wifi works (`broadcom-wl-dkms`). A cable is still better. To join a wifi:

```
nmcli device wifi list
sudo nmcli device wifi connect "NAME" password "PASS"
```

The laptop remembers the network. The play link changes with the address, so read it off the screen again.
- `tbbot add [persona]`, `tbbot remove`, `tbbot clear`, `tbbot list` — bots from a shell. Personas: wanderer, chaser, sniper, turtle, rusher, griefer.

## What the laptop records during a game night (v0.0.37 to v0.0.40)

Nothing to do during the night; it all lands in `~/tower_brawl/client_stats.jsonl` on the laptop, one JSON object per line:

- **A card from every device every 5 s** (phone, tablet, PC, spectator, bot): frame rate, slowest frame, script ms, ping, packets in, puppet jitter, keys and focus, plus the device (model, OS, screen rate, browser). No console or cable on any device.
- **Every match and round** start and end, with the players and the winner.
- **Every join, name, class pick, kill (killer, victim, weapon, lives left, round) and leave** (v0.0.40).
- `server.log` next to it has the same story as tagged text lines. `status.json` is the deck's live picture.

The next day, from the main PC:

```
tools/pull_laptop_logs.sh <laptop ip>      # copies everything into playtest_logs/<date>_<ip>/ and lists the matches
./venv/bin/python tools/stats_table.py --file playtest_logs/<folder>/client_stats.jsonl --summary   # every match: seats, classes, kills, K/D, weapons, devices
./venv/bin/python tools/stats_table.py --file playtest_logs/<folder>/client_stats.jsonl --match 3   # one row per device: fps, proc, ping, jitter
./venv/bin/python tools/stats_table.py --file playtest_logs/<folder>/client_stats.jsonl --devices   # who played on what
./venv/bin/python tools/stats_table.py --file playtest_logs/<folder>/client_stats.jsonl --events --match 3   # the whole match, marker by marker
```

The file rotates to `.1` at 10 MB (about five hours of a full game with seven devices), so a night fits.

## Passwords

`nemr` and `root` start with the password `towerbrawl`. Change them with `passwd` and `sudo passwd root`.
