# The server laptop

An old laptop runs the game server so the main PC stays free to play. It has no desktop. It boots straight to a text screen.

## What is on it

- Arch Linux, `linux-lts` kernel, hostname `towerbrawl`. User `nemr` with sudo.
- The SSD holds the system. The 1 TB drive is mounted at `/storage` for backups and media.
- The game lives in `~/tower_brawl` (server script, certs, `build/web`, `tools/`, a venv for the deck).
- `towerbrawl.service` starts the game server at boot and restarts it if it dies.
- The lid can be closed. Sleep is off.
- The screen logs in by itself and opens a one-window graphical terminal (`cage` + `foot`, JetBrainsMono Nerd Font, the Omarchy colours under `[colors-dark]` in `~/.config/foot/foot.ini`, the section name foot 1.28 wants, so it looks like the PC's deck). It prints a help box with the play link and every command, then opens the deck (`tbdash --controls`). If the graphics fail, it falls back to the plain text console.
- The deck has a SERVER panel at the top: the play link, buttons for **+ bot**, **- bot**, **clear bots** and **wifi help**. Keys do the same: `a`, `r`, `x`, `w`. `a` (or **+ bot**) opens the bot menu (v0.0.41): press `1` to `6` or click a chip to add that persona (wanderer, chaser, sniper, turtle, rusher, griefer), `a` again adds the next one in the list, Esc closes it. `i` (or **info**) shows the about panel with the public GitHub link, for anyone who asks about the code. Press `q` to leave the deck and get a shell; `tbdash` brings it back, `tbhelp` prints the box again.
- Bots are real headless Godot players with a bot brain (`tools/tbbot.py`, alias `tbbot`). Up to 4. Godot and the game source live on the laptop for this.

## The hardware (read over ssh on 2026-09-07)

| Part | What it is | State |
|---|---|---|
| Machine | ASUS G75VX gaming laptop, BIOS G75VX.204 (2012) | |
| CPU | Intel Core i7-3630QM, 4 cores / 8 threads, 2.4 to 3.4 GHz, 6 MB L3, AES | `schedutil` governor; idle 40 to 49 °C |
| Memory | 2 x 4 GB Samsung DDR3-1600 (8 GB, two channels), 4 GB zram swap (zstd) | 7.1 GB free with the server up; the server uses about 20 MB |
| GPU | NVIDIA GeForce GTX 670MX on `nouveau` (no Intel iGPU exposed; the screen runs on it) | |
| System disk | SanDisk Ultra II 480 GB SSD, ext4 root + 1 GB EFI | SMART PASSED, 34 868 h, 26 TB written, 0 reallocated, 100 % reserve |
| Storage disk | HGST 1 TB 2.5" HDD at `/storage`, ext4 | SMART PASSED, 47 821 h, 1.18 M load cycles (old, nothing on it yet) |
| Ethernet | Atheros AR8151 gigabit, `enp4s0` | 1000 Mb/s full duplex |
| Wifi | Broadcom BCM4352 (`wl` driver), `wlp3s0` | works; no network saved yet |
| Battery | 30 % of its design capacity left | irrelevant on mains; sleep masked, lid ignored |
| Boot | 16 s to the deck | no failed units |
| Software | Arch, `linux-lts` 6.18, Python 3.14, Godot 4.7.2, rich 15, websocket-client 1.9 | 0 updates pending |

Kernel log noise that is harmless: `b43` probes the wifi chip and fails before `wl` takes it (the blacklist in `/usr/lib/modprobe.d/broadcom-wl-dkms.conf` is in place); the Bluetooth chip has no firmware file and is unused.

## Server tuning (2026-09-07)

- **`towerbrawl.service`** drop-in `/etc/systemd/system/towerbrawl.service.d/10-standalone.conf`: `StartLimitIntervalSec=0` (it keeps restarting after a crash for ever; the default gave up after 5 tries in 10 s), `Nice=-5` (the relay gets CPU before the deck and the bots), `OOMScoreAdjust=-500` (a bot is killed before the server if memory ever runs out), `TimeoutStopSec=10`.
- **Journal** capped at 200 MB (`/etc/systemd/journald.conf.d/10-cap.conf`).
- **The game's own logs rotate:** `logrotate` with `/etc/logrotate.d/towerbrawl`: `server.log` and `debug.log` at 50 MB, 5 kept, compressed, `copytruncate` because the server keeps the files open. `debug.log` grows about 1 MB an hour with bots in the game. (Backlog 4 is solved on the laptop this way; the PC still has no rotation.)
- **Wifi power saving off** (`/etc/NetworkManager/conf.d/wifi-powersave.conf`, `wifi.powersave = 2`), for the night the cable is not an option.
- **Diagnostics installed:** `smartmontools`, `ethtool`, `dmidecode`. `sudo smartctl -H /dev/sdb` for the SSD, `sudo ethtool enp4s0` for the link.
- **Old builds are removed** from `build/web` after a deploy; only the current `index_v*` pair stays.
- **Left alone on purpose:** the CPU governor (the relay is idle most of the time; the 50 ms bundle window dwarfs any ramp-up), `vm.swappiness` (memory is never tight), the HDD (nothing uses it yet), the firewall (none; a home LAN), and `PasswordAuthentication yes` in sshd, which is why the temporary password must change before the laptop sits on someone else's network.

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

`nemr` and `root` start with the password `towerbrawl`. Change them with `passwd` and `sudo passwd root`. Do this before the laptop joins a network that is not yours: sshd accepts passwords, and the word is written in this notebook.
