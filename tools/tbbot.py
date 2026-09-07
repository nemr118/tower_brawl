#!/usr/bin/env python3
"""
Bot manager: start and stop headless bot players on this machine.

    tools/tbbot.py add [persona]   start one bot (wanderer, chaser, sniper, turtle, rusher, griefer)
    tools/tbbot.py remove          stop the newest bot
    tools/tbbot.py clear           stop every bot
    tools/tbbot.py list            show the running bots
    tbbot add chaser               the shell alias for the same thing

Each bot is a real headless Godot client with a bot brain (scripts/bot_brain.gd).
It joins the local server like a phone would. Godot must be installed and the
project source must sit next to this tools/ folder. Logs and pid files live in
.bots/ in the project folder. The deck (tools/watch_server.py --controls) calls
these same commands from its buttons.
"""
import glob
import os
import signal
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOT_DIR = os.path.join(ROOT, ".bots")
PERSONAS = ["wanderer", "chaser", "sniper", "turtle", "rusher", "griefer"]
SERVER = "ws://127.0.0.1:8081"
MAX_BOTS = 4


def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def running():
    """[(n, pid, persona)] for every bot whose process is still alive, oldest first."""
    bots = []
    for path in sorted(glob.glob(os.path.join(BOT_DIR, "bot*.pid"))):
        try:
            with open(path) as f:
                pid_s, persona = f.read().split()
            pid = int(pid_s)
        except (OSError, ValueError):
            os.unlink(path)
            continue
        if _alive(pid):
            n = int(os.path.basename(path)[3:-4])
            bots.append((n, pid, persona))
        else:
            os.unlink(path)
    return sorted(bots)


def add(persona=None):
    bots = running()
    if len(bots) >= MAX_BOTS:
        print(f"already {MAX_BOTS} bots, remove one first")
        return 1
    used = {n for n, _, _ in bots}
    n = next(i for i in range(1, MAX_BOTS + 1) if i not in used)
    if persona is None:
        persona = PERSONAS[(n - 1) % len(PERSONAS)]
    persona = persona.lower()
    if persona not in PERSONAS:
        print(f"unknown persona {persona!r}; pick one of {', '.join(PERSONAS)}")
        return 1
    os.makedirs(BOT_DIR, exist_ok=True)
    log = open(os.path.join(BOT_DIR, f"bot{n}.log"), "w")
    argv = ["godot", "--headless", "--path", ROOT, "--", "--autojoin", f"--name=Bot{n}",
            f"--server={SERVER}", f"--ai={persona}", f"--ai-seed={int(time.time()) % 10000 + n}",
            "--no-netstats"]
    try:
        proc = subprocess.Popen(argv, stdout=log, stderr=subprocess.STDOUT,
                                start_new_session=True, cwd=ROOT)
    except FileNotFoundError:
        print("godot is not installed on this machine")
        return 1
    with open(os.path.join(BOT_DIR, f"bot{n}.pid"), "w") as f:
        f.write(f"{proc.pid} {persona}\n")
    print(f"Bot{n} ({persona}) is joining")
    return 0


def _stop(n, pid):
    try:
        os.killpg(pid, signal.SIGTERM)
    except OSError:
        pass
    for _ in range(20):
        if not _alive(pid):
            break
        time.sleep(0.1)
    else:
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
    try:
        os.unlink(os.path.join(BOT_DIR, f"bot{n}.pid"))
    except OSError:
        pass


def remove():
    bots = running()
    if not bots:
        print("no bots running")
        return 0
    n, pid, persona = bots[-1]
    _stop(n, pid)
    print(f"Bot{n} ({persona}) left")
    return 0


def clear():
    bots = running()
    for n, pid, persona in reversed(bots):
        _stop(n, pid)
    print(f"stopped {len(bots)} bot(s)")
    return 0


def list_bots():
    bots = running()
    if not bots:
        print("no bots running")
    for n, pid, persona in bots:
        print(f"Bot{n}  {persona:<9} pid {pid}")
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    if cmd == "add":
        return add(argv[2] if len(argv) > 2 else None)
    if cmd in ("remove", "rm", "kick"):
        return remove()
    if cmd == "clear":
        return clear()
    if cmd in ("list", "ls"):
        return list_bots()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
