#!/usr/bin/env python3
"""
Tower Brawl live server dashboard (Phase 3c step 0, v0.0.21).

    ./venv/bin/python tools/watch_server.py             # live view, redraws every second
    ./venv/bin/python tools/watch_server.py --plain     # no colours, one text block per second
    ./venv/bin/python tools/watch_server.py --once      # print one picture and exit
    ./venv/bin/python tools/watch_server.py --events 25 # show more event lines

The story: to watch a match from the terminal you had to read raw log lines.
Now serve_game.py writes a small file, status.json, once a second. This tool
reads that file and draws it as a live dashboard: a header line with the match
state, a table with one row per seat, a traffic line and a feed of the last
events. The server never needs this tool, and this tool never talks to the
server. If the file is missing or old, the dashboard says so in red.

Colours come from the `rich` library (installed in the venv). Without it, or
with --plain, the same picture is printed as plain text.
"""
import argparse
import json
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATUS_FILE = os.path.join(ROOT, "status.json")
STALE_AFTER = 3.0   # seconds without a fresh write = the server is probably down

# One colour per tag. The same names the server puts at the start of its lines.
TAG_STYLE = {
    "JOIN": "green", "LEAVE": "yellow", "CONN": "dim", "NAME": "magenta", "LOCK": "blue",
    "MATCH": "bold cyan", "ROUND": "cyan", "KILL": "red", "NET": "yellow",
}


def read_status(path):
    """The status file as a dict, or None when it is missing or half-written."""
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def fmt_uptime(seconds):
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h {m:02d}m"
    if m:
        return f"{m}m {s:02d}s"
    return f"{s}s"


def seat_state(seat, match_state):
    """One short word for what a seat is doing right now, plus its colour."""
    if not seat["connected"]:
        if seat["held_s"] is not None:
            return f"held {seat['held_s']:.0f}s", "yellow"
        return "empty", "dim"
    if match_state == "PLAYING":
        if seat["waiting"]:
            return "waiting", "yellow"
        if seat["playing"] and seat["alive"]:
            return "alive", "green"
        if seat["playing"]:
            return "out", "red"
        return "watching", "dim"
    if seat["locked"]:
        return "locked in", "green"
    return "picking", "dim"


def seat_rows(status):
    """The seat table as plain values: one list per seat."""
    rows = []
    for seat in status["seats"]:
        state, colour = seat_state(seat, status["match"]["state"])
        playing = status["match"]["state"] == "PLAYING" and seat["playing"]
        lives = "♥" * seat["stocks"] if playing else "-"
        crowns = str(seat["crowns"]) if seat["crowns"] else "-"
        link = f"{seat['transport']} {seat['ip']}" if seat["connected"] else "-"
        pps = f"{seat['in_pps']:.0f}" if seat["connected"] else "-"
        queue = f"{seat['queue']}/{seat['dropped']}" if seat["connected"] else "-"
        seen = f"{seat['seen_s']:.0f}s" if seat["seen_s"] is not None else "-"
        rows.append({
            "seat": f"P{seat['id']}", "name": seat["name"] or "-",
            "cls": seat["class_name"] or "-", "state": state, "colour": colour,
            "lives": lives, "crowns": crowns, "link": link, "pps": pps, "queue": queue, "seen": seen,
        })
    return rows


def header_text(status, age):
    m = status["match"]
    players = sum(1 for s in status["seats"] if s["connected"])
    parts = [f"TOWER BRAWL {status['version']}", m["state"]]
    if m["state"] == "PLAYING":
        parts.append(f"round {m['round']}")
        parts.append(f"flips {m['flips']}")
    parts.append(f"{players} player{'s' if players != 1 else ''}")
    parts.append(f"{status['spectators']} spectator{'s' if status['spectators'] != 1 else ''}")
    parts.append(f"up {fmt_uptime(status['uptime_s'])}")
    parts.append(f"updated {age:.1f}s ago")
    return "  |  ".join(parts)


def traffic_text(status):
    t = status["traffic"]
    top = ", ".join(f"{k}={v:g}" for k, v in sorted(t["in_types_s"].items(), key=lambda kv: -kv[1])[:5])
    return (f"IN {t['in_pps']:6.1f} pkt/s {t['in_kbps']:6.2f} KB/s   "
            f"OUT {t['out_pps']:6.1f} pkt/s {t['out_kbps']:6.2f} KB/s   "
            f"fail {t['fail_s']:g}/s  drop {t['drop_s']:g}/s   |  in: {top or '-'}   |  threads {status['threads']}")


def stale_text(status, age):
    if status is None:
        return f"no {os.path.basename(STATUS_FILE)} yet. Is the server running?  systemctl --user status towerbrawl"
    return f"no fresh status for {age:.0f} s. Is the server running?  systemctl --user status towerbrawl"


# ── Plain text picture ────────────────────────────────────────────────────────
def render_plain(status, age, n_events):
    lines = []
    if status is None or age > STALE_AFTER:
        lines.append("!! " + stale_text(status, age))
        if status is None:
            return "\n".join(lines)
    lines.append(header_text(status, age))
    lines.append("-" * 100)
    lines.append(f"{'Seat':<5}{'Name':<14}{'Class':<8}{'State':<11}{'Lives':<7}{'Crowns':<7}{'Link':<32}{'In/s':>5} {'Q/drop':>7} {'Seen':>5}")
    for r in seat_rows(status):
        lines.append(f"{r['seat']:<5}{r['name']:<14}{r['cls']:<8}{r['state']:<11}{r['lives']:<7}{r['crowns']:<7}"
                     f"{r['link']:<32}{r['pps']:>5} {r['queue']:>7} {r['seen']:>5}")
    lines.append("-" * 100)
    lines.append(traffic_text(status))
    lines.append("-" * 100)
    for ev in status["events"][-n_events:]:
        lines.append(f"{ev['t']} {ev['msg']}")
    return "\n".join(lines)


# ── Colour picture (rich) ─────────────────────────────────────────────────────
def render_rich(status, age, n_events):
    from rich.console import Group
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text

    parts = []
    if status is None or age > STALE_AFTER:
        parts.append(Panel(Text(stale_text(status, age), style="bold white on red"), border_style="red"))
        if status is None:
            return Group(*parts)

    m = status["match"]
    head_style = "bold green" if m["state"] == "PLAYING" else "bold cyan"
    parts.append(Panel(Text(header_text(status, age), style=head_style), border_style="cyan"))

    table = Table(expand=True, border_style="dim", header_style="bold")
    for col, just in (("Seat", "left"), ("Name", "left"), ("Class", "left"), ("State", "left"),
                      ("Lives", "left"), ("Crowns", "right"), ("Link", "left"),
                      ("In/s", "right"), ("Q/drop", "right"), ("Seen", "right")):
        table.add_column(col, justify=just, no_wrap=True)
    for r in seat_rows(status):
        table.add_row(r["seat"], r["name"], r["cls"], Text(r["state"], style=r["colour"]),
                      Text(r["lives"], style="red"), r["crowns"], r["link"], r["pps"], r["queue"], r["seen"])
    parts.append(table)

    parts.append(Panel(Text(traffic_text(status), style="white"), title="traffic (last second)",
                       title_align="left", border_style="dim"))

    feed = Text()
    events = status["events"][-n_events:]
    for i, ev in enumerate(events):
        style = TAG_STYLE.get(ev["tag"], "white")
        if ev["level"] in ("WARNING", "ERROR"):
            style = "bold yellow" if ev["level"] == "WARNING" else "bold red"
        feed.append(f"{ev['t']} ", style="dim")
        feed.append(ev["msg"], style=style)
        if i < len(events) - 1:
            feed.append("\n")
    parts.append(Panel(feed if events else Text("no events yet", style="dim"),
                       title="events", title_align="left", border_style="dim"))
    return Group(*parts)


def main():
    ap = argparse.ArgumentParser(description="Live dashboard for the Tower Brawl server (reads status.json).")
    ap.add_argument("--file", default=STATUS_FILE, help="status file to read (default: status.json in the repo)")
    ap.add_argument("--interval", type=float, default=1.0, help="seconds between redraws (default 1)")
    ap.add_argument("--events", type=int, default=15, help="event lines to show (default 15)")
    ap.add_argument("--plain", action="store_true", help="plain text, no colours")
    ap.add_argument("--once", action="store_true", help="print one picture and exit")
    args = ap.parse_args()

    use_rich = not args.plain
    if use_rich:
        try:
            import rich  # noqa: F401
        except ImportError:
            print("rich is not installed in this Python; falling back to plain text "
                  "(./venv/bin/pip install rich)", file=sys.stderr)
            use_rich = False

    def picture():
        status = read_status(args.file)
        age = (time.time() - status["written_at"]) if status else 0.0
        return status, age

    if args.once or not use_rich:
        while True:
            status, age = picture()
            print(render_plain(status, age, args.events))
            if args.once:
                return 0 if status is not None and age <= STALE_AFTER else 1
            print()
            time.sleep(args.interval)

    from rich.console import Console
    from rich.live import Live
    console = Console()
    with Live(console=console, refresh_per_second=4, screen=True) as live:
        while True:
            status, age = picture()
            live.update(render_rich(status, age, args.events))
            time.sleep(args.interval)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
