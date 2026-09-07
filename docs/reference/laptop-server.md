# The server laptop

An old laptop runs the game server so the main PC stays free to play. It has no desktop. It boots straight to a text screen.

## What is on it

- Arch Linux, `linux-lts` kernel, hostname `towerbrawl`. User `nemr` with sudo.
- The SSD holds the system. The 1 TB drive is mounted at `/storage` for backups and media.
- The game lives in `~/tower_brawl` (server script, certs, `build/web`, `tools/`, a venv for the deck).
- `towerbrawl.service` starts the game server at boot and restarts it if it dies.
- The lid can be closed. Sleep is off.
- The screen logs in by itself, prints a help box with the play link and every command, then opens the deck (`tbdash --controls`).
- The deck has a SERVER panel at the top: the play link, buttons for **+ bot**, **- bot**, **clear bots** and **wifi help**. Keys do the same: `b`, `B`, `x`, `w`. Press `q` to leave the deck and get a shell; `tbdash` brings it back, `tbhelp` prints the box again.
- Bots are real headless Godot players with a bot brain (`tools/tbbot.py`, alias `tbbot`). Up to 4. Godot and the game source live on the laptop for this.

## At a new house

1. Plug in power and an ethernet cable to the router.
2. Turn it on. Wait for the TOWER BRAWL SERVER box on the screen. The deck opens a few seconds later.
3. Everyone types the **Play** link from the box into their phone. Accept the "not secure" warning once.

## Push a new build from the main PC

```
./bump_build.sh --title "..."          # as usual
tools/deploy_laptop.sh <laptop ip>     # copies the build, restarts the service
```

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

## Passwords

`nemr` and `root` start with the password `towerbrawl`. Change them with `passwd` and `sudo passwd root`.
