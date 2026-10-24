#!/usr/bin/env python3
"""The new game's server panel: a terminal page for the server laptop's screen.

It shows the play links, whether the two servers run, whether the firewall lets
the phones in, the game right now (the server's report every 5 s in
bench_results/<date>/v2_server.jsonl) and the last join, lobby, match and round
lines from the journal. With the server's host port (p4.2, --admin-port 8092) it
also lists the seats, and keys work: + and - set the bots (in a match from the
next round), K and a seat number kicks that person back to watching.
Keys: + - K, R restarts the new game (it asks first), Q quits.
The servers can be user units (the ROG, 2026-10-24) or system units (the home laptop).

Use:  python3 tools/v2_dash.py           the live panel
      python3 tools/v2_dash.py --once    one picture, plain text, then exit
Standard library only, so it runs without the venv.
"""
import argparse
import glob
import ipaddress
import json
import os
import re
import select
import shutil
import subprocess
import sys
import termios
import time
import tty
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORTS = (8443, 8444, 8091)   # the pages, the old game's relay, the new game
PHASES = ["LOBBY", "COUNTDOWN", "ROUND START", "PLAYING", "ROUND END", "MATCH END"]
ARENAS = ["THE BENCH", "THE KEEP", "THE BRIDGES"]
EVENTS = re.compile(r"\[(JOIN|LEAVE|LOBBY|MATCH|ROUND)\]")
FIGHT = re.compile(r"\[ROUND\] \d+ FIGHT")   # one a round, right after the start line: noise here
ANSI = re.compile(r"\033\[[0-9;]*m")
COLOUR = True
HOST = "http://127.0.0.1:8092"   # the server's host port (p4.2)


def paint(code, text):
    return f"\033[{code}m{text}\033[0m" if COLOUR else text


def green(t): return paint("32", t)
def red(t): return paint("1;31", t)
def yellow(t): return paint("33", t)
def bold(t): return paint("1", t)
def dim(t): return paint("2", t)


def run(cmd, timeout=3):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def scope_of(unit):
    """["--user"] when the unit is a user unit (the ROG), [] for a system unit."""
    if run(["systemctl", "--user", "show", "-p", "LoadState", "--value", unit]) == "loaded":
        return ["--user"]
    return []


def unit_state(unit):
    sc = scope_of(unit)
    state = run(["systemctl", *sc, "is-active", unit]) or "unknown"
    since = run(["systemctl", *sc, "show", "-p", "ActiveEnterTimestamp", "--value", unit])
    m = re.search(r"(\d\d:\d\d):\d\d", since)
    return state, (m.group(1) if m else ""), sc


def lan():
    """The address phones use (the one the default route leaves from), its network, the Wi-Fi name."""
    out = run(["ip", "-4", "-o", "route", "get", "1.1.1.1"])
    dev = re.search(r"\bdev (\S+)", out)
    ip, net = "", ""
    for line in run(["ip", "-4", "-o", "addr", "show"]).splitlines():
        m = re.search(r"^\d+:\s+(\S+)\s+inet (\S+)", line)
        if not m or m.group(1) == "lo" or m.group(1).startswith(("tailscale", "docker", "br-", "veth")):
            continue
        if dev and m.group(1) != dev.group(1) and ip:
            continue
        iface = ipaddress.ip_interface(m.group(2))
        ip, net = str(iface.ip), str(iface.network)
        if dev and m.group(1) == dev.group(1):
            break
    wifi = ""
    for line in run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]).splitlines():
        name, _, kind = line.rpartition(":")
        if "wireless" in kind:
            wifi = name.replace("\\:", ":")
            break
    return ip, net, wifi


def firewall(net):
    """("off" | "on" | "unknown", the game ports a phone on `net` cannot reach)."""
    if run(["systemctl", "is-active", "ufw"]) != "active":
        return "off", []
    try:
        with open("/etc/ufw/user.rules") as fh:
            rules = fh.read().splitlines()
    except OSError:
        return "unknown", []
    lan_net = ipaddress.ip_network(net) if net else None
    let_in = set()
    for r in rules:
        if not r.startswith("-A ufw-user-input") or "-j ACCEPT" not in r or " -i " in r or "-p udp" in r:
            continue
        src = re.search(r" -s (\S+)", r)
        if src and lan_net and not lan_net.subnet_of(ipaddress.ip_network(src.group(1), strict=False)):
            continue
        ports = re.search(r"--dports? (\S+)", r)
        if not ports:
            let_in.update(PORTS)
            continue
        for part in ports.group(1).split(","):
            if ":" in part:
                a, b = (int(x) for x in part.split(":"))
                let_in.update(p for p in PORTS if a <= p <= b)
            elif part.isdigit():
                let_in.add(int(part))
    return "on", [p for p in PORTS if p not in let_in]


def blocked_lately():
    """Phones the firewall turned away from the game ports in the last minute."""
    out = run(["journalctl", "-k", "--since", "-60s", "-o", "cat", "--no-pager"])
    hits, who = 0, set()
    for line in out.splitlines():
        if "UFW BLOCK" in line:
            port = re.search(r"DPT=(\d+)", line)
            if port and int(port.group(1)) in PORTS:
                hits += 1
                src = re.search(r"SRC=(\S+)", line)
                if src:
                    who.add(src.group(1))
    return hits, sorted(who)


def host_call(path, body=None):
    """The host port: GET /state (body None) or a POST command; None when it does not answer."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(HOST + path, data=data, method="GET" if body is None else "POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=1.0) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())
        except ValueError:
            return None
    except (OSError, ValueError):
        return None


def last_report():
    files = sorted(glob.glob(os.path.join(ROOT, "bench_results", "*", "v2_server.jsonl")))
    if not files:
        return None
    with open(files[-1], "rb") as fh:
        fh.seek(0, 2)
        fh.seek(max(0, fh.tell() - 20000))
        lines = fh.read().decode(errors="replace").splitlines()
    for line in reversed(lines):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("kind") == "report":
            return d
    return None


def events(scope, n):
    out = run(["journalctl", *scope, "-u", "towerbrawl-v2", "-n", "500", "-o", "short-iso", "--no-pager"])
    keep = []
    for line in out.splitlines():
        if not EVENTS.search(line) or FIGHT.search(line):
            continue
        m = re.match(r"\S+T(\d\d:\d\d):\d\d\S*\s+\S+\s+[^:]+:\s+(.*)", line)
        if m:
            keep.append((m.group(1), m.group(2).replace("🏰 ", "").strip()))
    return keep[-n:]


def version():
    try:
        with open(os.path.join(ROOT, "bench", "sim", "proto.gd")) as fh:
            m = re.search(r'const VERSION := "([^"]+)"', fh.read())
            return m.group(1) if m else "?"
    except OSError:
        return "?"


def cpu_line():
    parts = []
    try:
        with open("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq") as fh:
            parts.append(f"top speed {int(fh.read()) / 1e6:.1f} GHz")
    except (OSError, ValueError):
        pass
    for name_file in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            with open(name_file) as fh:
                if fh.read().strip() != "coretemp":
                    continue
            with open(os.path.join(os.path.dirname(name_file), "temp1_input")) as fh:
                parts.append(f"{int(fh.read()) / 1000:.0f} °C")
        except (OSError, ValueError):
            pass
        break
    return " · ".join(parts)


def fit(line, width):
    """A line wider than the window loses its colour and its end, so nothing wraps."""
    plain = ANSI.sub("", line)
    return line if len(plain) <= width else plain[:width - 1] + "…"


class Panel:
    def __init__(self):
        self.slow_at = 0.0
        self.net = ("", "", "")
        self.blocks = (0, [])
        self.ask = False
        self.kick = False
        self.note = ("", 0.0)
        self.state = None

    def lines(self):
        now = time.time()
        if now >= self.slow_at:   # the Wi-Fi and the kernel log every 5 s
            self.net = lan()
            self.blocks = blocked_lately()
            self.slow_at = now + 5
        ip, net, wifi = self.net
        host = ip or "<this laptop's address>"
        web, web_since, _ = unit_state("towerbrawl")
        game, game_since, game_scope = unit_state("towerbrawl-v2")
        fw, closed = firewall(net)
        width = shutil.get_terminal_size((100, 40)).columns
        out = [bold(" TOWER BRAWL SERVER") + dim(f"   the new game {version()} · {time.strftime('%H:%M:%S')}"), ""]

        out.append(bold(" PLAY ON A PHONE") + (f"  (Wi-Fi \"{wifi}\")" if wifi else ""))
        out.append(f"   New game   {bold(f'https://{host}:8443/v2/')}")
        out.append(f"   Old game   https://{host}:8443/play")
        out.append(dim("   Accept the certificate warning once."))
        out.append(dim(f"   Stuck on \"Still connecting\"? Open https://{host}:8091 once, accept, go back."))
        out.append("")

        def dot(ok, text):
            return f"   {green('●') if ok else red('✗')} {text}"

        out.append(bold(" CHECKS"))
        out.append(dot(web == "active", f"web pages + old game   {web}" + (f" since {web_since}" if web == "active" else "")))
        out.append(dot(game == "active", f"new game server        {game}" + (f" since {game_since}" if game == "active" else "")))
        if fw == "off":
            out.append(dot(True, "phones let in          (no firewall)"))
        elif fw == "unknown":
            out.append(f"   {yellow('?')} phones let in          cannot read the firewall rules")
        elif not closed:
            out.append(dot(True, f"phones let in          ports {' '.join(map(str, PORTS))} open to {net}"))
        else:
            out.append(dot(False, red(f"phones BLOCKED (ports {' '.join(map(str, closed))})") + ". In a terminal on this laptop:"))
            out.append(f"       sudo ufw allow from {net or '<wifi network>'} to any port {','.join(map(str, PORTS))} proto tcp")
        hits, who = self.blocks
        if hits:
            out.append(f"     {yellow('!')} the firewall turned away {hits} tries in the last minute from {', '.join(who)}")
        cpu = cpu_line()
        if cpu:
            out.append(f"   {dim('·')} CPU {cpu}")
        out.append("")

        st = self.state = host_call("/state")
        if st:
            out.append(bold(" SEATS") + dim(f"   bots {st['bots_wanted']}" + (f" (now {st['bots_now']})" if st["bots_now"] != st["bots_wanted"] else "")
                                            + f" · {st['bot_level_name']} · arena {st['arena_pick_name']}"))
            for seat in st["seats"]:
                if seat["who"] == "empty":
                    out.append(dim(f"   {seat['i']}  -"))
                    continue
                ping = f"{seat['ping_ms']} ms" if seat["ping_ms"] >= 0 else ""
                away = f" away {seat['held_s']} s" if seat["held_s"] else ""
                who = bold(seat["name"]) if seat["who"] == "person" else seat["name"]
                out.append(f"   {seat['i']}  {who}  {dim(seat['who'])}  {seat['points']} pts  {ping}{yellow(away) if away else ''}")
            if st["watching"]:
                out.append(dim("   watching: " + ", ".join(w["name"] for w in st["watching"])))
            out.append("")
        out.append(bold(" THE NEW GAME NOW"))
        rep = last_report()
        if not rep:
            out.append(dim("   no report yet (the server writes one every 5 s)"))
        else:
            age = now - rep.get("t", 0)
            phase = rep.get("phase", 0)
            ph = PHASES[phase] if 0 <= phase < len(PHASES) else str(phase)
            arena = rep.get("arena", -1)
            ar = ARENAS[arena] if 0 <= arena < len(ARENAS) else "?"
            rnd = f" round {rep['round']}" if rep.get("round") and phase != 0 else ""
            out.append(f"   {bold(ph)}{rnd} · {rep.get('people', 0)} people, {rep.get('bots', 0)} bots · arena {ar}")
            pings = [f"{c.get('rtt', 0)} ms" for c in rep.get("per_client", [])]
            n_in = sum(v[1] for v in rep.get("inputs", []))
            n_late = sum(v[2] for v in rep.get("inputs", []))
            late = f" · late inputs {n_late} of {n_in}" if n_in else ""
            out.append(f"   ping {', '.join(pings) if pings else '-'}{late}")
            stale = red(f" · report {age:.0f} s old: is the server stuck?") if age > 15 else dim(f" · report {age:.0f} s old")
            out.append(f"   tick {rep.get('tick_mean_ms', 0):.2f} ms (worst {rep.get('tick_max_ms', 0):.2f}) · "
                       f"server CPU {rep.get('cpu_pct', 0):.0f}% · memory {rep.get('rss_mb', 0):.0f} MB{stale}")
        out.append("")

        out.append(bold(" LATELY"))
        rows = shutil.get_terminal_size((100, 40)).lines
        room = max(3, rows - len(out) - 4)
        evs = events(game_scope, room)
        if not evs:
            out.append(dim("   nothing yet"))
        for hhmm, text in evs:
            out.append(f"   {dim(hhmm)}  {text[:max(20, width - 11)]}")
        out.append("")

        msg, until = self.note
        if self.ask:
            out.append(yellow(" Restart the new game? Everyone in it drops and the lobby starts fresh. Y = yes, any other key = no"))
        elif self.kick:
            out.append(yellow(" Kick which seat? Press its number (0-7). Any other key: no kick."))
        elif msg and now < until:
            out.append(yellow(f" {msg}"))
        elif self.state:
            out.append(dim(" + / - bots   K kick a seat   R restart the new game   Q close this panel"))
        else:
            out.append(dim(" R restart the new game (fresh lobby)   Q close this panel"))
        return [fit(line, width) for line in out]

    def key(self, ch):
        if self.kick:
            self.kick = False
            if ch.isdigit() and int(ch) < 8:
                r = host_call("/kick", {"seat": int(ch)})
                self.note = ((r or {}).get("text", "The host port did not answer."), time.time() + 5)
            else:
                self.note = ("No kick.", time.time() + 3)
            return True
        if ch in "+=-_" and self.state:
            n = self.state["bots_wanted"] + (1 if ch in "+=" else -1)
            r = host_call("/bots", {"n": max(0, min(self.state["max_bots"], n))})
            self.note = ((r or {}).get("text", "The host port did not answer."), time.time() + 4)
            return True
        if ch in "kK" and self.state:
            self.kick = True
            return True
        if self.ask:
            self.ask = False
            if ch in "yY":
                _, _, sc = unit_state("towerbrawl-v2")
                if sc:
                    run(["systemctl", "--user", "restart", "towerbrawl-v2"], timeout=20)
                    self.note = ("The new game restarted: a fresh lobby.", time.time() + 6)
                else:
                    self.note = ("A system service: run  sudo systemctl restart towerbrawl-v2", time.time() + 10)
            else:
                self.note = ("Not restarted.", time.time() + 3)
            return True
        if ch in "rR":
            self.ask = True
        return ch not in "qQ"


def main():
    global COLOUR
    ap = argparse.ArgumentParser(description="The new game's server panel (play links, checks, the game now, the last events).")
    ap.add_argument("--once", action="store_true", help="print one picture, plain, and exit")
    ap.add_argument("--interval", type=float, default=1.0, help="seconds between redraws (default 1)")
    args = ap.parse_args()
    panel = Panel()
    if args.once or not sys.stdin.isatty():
        COLOUR = False
        print("\n".join(panel.lines()))
        return
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    sys.stdout.write("\033[?1049h\033[?25l")
    try:
        tty.setcbreak(fd)
        while True:
            sys.stdout.write("\033[H\033[J" + "\n".join(panel.lines()))
            sys.stdout.flush()
            ready, _, _ = select.select([sys.stdin], [], [], args.interval)
            if ready and not panel.key(os.read(fd, 1).decode(errors="ignore") or "q"):
                break
    except KeyboardInterrupt:
        pass
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        sys.stdout.write("\033[?25h\033[?1049l")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
