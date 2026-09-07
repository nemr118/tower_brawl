#!/usr/bin/env python3
"""
Tower Brawl live operations deck (v0.0.21 dashboard, deck since v0.0.22,
interactive since v0.0.24).

    ./venv/bin/python tools/watch_server.py             # live view, keys and mouse work
    ./venv/bin/python tools/watch_server.py --plain     # plain text, one block per second
    ./venv/bin/python tools/watch_server.py --once      # one picture and exit (colour, or --plain)
    ./venv/bin/python tools/watch_server.py --no-mouse  # keyboard only
    tbdash                                              # the shell alias for the first line
    ./venv/bin/python tools/watch_server.py --no-controls  # without the SERVER panel (play link, bot menu, wifi, info); it is on by default since v0.0.41

The story: to watch a match from the terminal you had to read raw log lines.
Now serve_game.py writes a small file, status.json, once a second, and the test
harness (tools/chaos_bots.py) writes harness_state.json while it runs. This
tool only reads those two files and draws them. It never talks to the server.

The picture is a stack of panels. A panel that has nothing to show is not drawn:
  ALERT      a red line for 10 s after an ERROR, a stalled drop or a gate demotion
  HEADER     match state, players, bots, spectators, uptime
  HARNESS    only while a harness run is alive: scenario, progress bar, ETA, checklist
  SEATS      one row per seat: lives, crowns, kills/deaths, ping + trend, health, link
  FIGHT      from the first second of a match: a kill strip with a time axis
  BOT ARENA  when bots are seated: kind, persona, state, actions, learning
  TRAFFIC    packets and bytes per second, in and out, with a 60 s curve
  EVENTS     the tagged server log lines, filtered with the number keys

Keys:  ← →  pan the strip     + -  zoom (0.5 s .. 30 s per column)
       Home  match start      End or f  back to live and follow
       click a column  what happened that second      Esc  clear it
       1-9  hide / show a log tag    p  pause    s  save a text snapshot    q  quit
       with --controls:  a  the bot menu (1-6 add that persona, a the next one, Esc closes)
                         r  remove a bot    x  clear bots    w  wifi help    i  about the game (the GitHub link)
                         (or click the buttons and the persona chips in the SERVER panel; tools/tbbot.py does the work)
Mouse: wheel pans, Ctrl+wheel or Shift+wheel zooms around the pointer, wheel
over the events panel scrolls it. --no-mouse turns the mouse off.

Colours come from the `rich` library (installed in the venv). Without it, or
with --plain, the same picture is printed as plain text (no keys in plain mode).
"""
import argparse
import glob
import json
import os
import shutil
import sys
import time
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from deck_input import InputReader  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATUS_FILE = os.path.join(ROOT, "status.json")
HARNESS_FILE = os.path.join(ROOT, "harness_state.json")
REPORT_GLOB = os.path.join(ROOT, "docs", "harness_report_*.json")
STALE_AFTER = 3.0      # seconds without a fresh status write = the server is probably down
HARNESS_STALE = 5.0    # seconds without a harness heartbeat = the run stopped answering
HARNESS_KEEP = 600.0   # a finished run stays as one summary line this long
ALERT_KEEP = 10.0      # an alert line stays this long
MESSAGE_KEEP = 4.0     # "saved deck_snapshot_..." stays this long
HISTORY = 60           # ping and traffic samples kept for the sparklines
ZOOM_LADDER = (0.5, 1.0, 2.0, 5.0, 10.0, 30.0)   # seconds per strip column
DEFAULT_ZOOM = 1                                   # index into ZOOM_LADDER: 1.0 s
LABEL_W = 18           # the lane label: "P1 Tav ♛2 5/3"
SPARK = " ▁▂▃▄▅▆▇█"    # counts per column, low to high
SEAT_STYLE = {1: "bright_blue", 2: "bright_red", 3: "bright_green", 4: "bright_yellow"}
BAND_BG = "grey11"     # every second round gets this background on the strip
# The weapon names a kill carries (take_hit in player.gd and the projectiles).
# ⬇ would be the natural stomp glyph, but emoji-aware terminals draw it two
# cells wide and that breaks the columns, so the stomp is ▼.
WEAPON_GLYPH = {"Arrow": "➶", "Firebolt": "✦", "Kunai": "✧", "Thorns": "❋", "Melee": "⚔", "Goomba Stomp": "▼"}
LEGEND = "➶ arrow ✦ firebolt ✧ kunai ❋ thorns ⚔ melee ▼ stomp ✕ death ◈ both 2-9 stacked ┃ round ┫ end ♛ winner ║ match end"
FILTER_TAGS = ("KILL", "ROUND", "MATCH", "JOIN", "LEAVE", "NAME", "LOCK", "CONN", "NET", "TAPE")   # keys 1..9, then 0
FILTER_KEYS = "1234567890"   # the key that hides or shows each tag above

# One colour per tag. The same names the server puts at the start of its lines.
TAG_STYLE = {
    "JOIN": "green", "LEAVE": "yellow", "CONN": "dim", "NAME": "magenta", "LOCK": "blue",
    "MATCH": "bold cyan", "ROUND": "cyan", "KILL": "red", "NET": "yellow", "GATE": "bold yellow",
    "TAPE": "bright_magenta",   # v0.0.25: a screen froze its tape
}
RESULT_MARK = {"PASS": ("✔", "green"), "FAIL": ("✖", "bold red"), "MINOR": ("▲", "yellow")}
HEALTH_STYLE = {"good": "green", "laggy": "yellow", "slow": "yellow", "quiet": "yellow",
                "stalled": "bold red", "held": "yellow", "empty": "dim"}


# ── Reading the files ─────────────────────────────────────────────────────────
def read_json(path):
    """The file as a dict, or None when it is missing or half-written."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def load_expected():
    """Scenario name -> seconds it took in the newest harness report, for the ETA."""
    paths = glob.glob(REPORT_GLOB)
    if not paths:
        return {}
    newest = max(paths, key=os.path.getmtime)
    report = read_json(newest) or {}
    out = {}
    for r in report.get("results") or []:
        if isinstance(r, dict) and r.get("scenario") and r.get("elapsed_s") is not None:
            out[r["scenario"]] = float(r["elapsed_s"])
    return out


def fmt_uptime(seconds):
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h {m:02d}m"
    if m:
        return f"{m}m {s:02d}s"
    return f"{s}s"


def fmt_clock(t):
    """Match time as m:ss."""
    t = max(0, int(t))
    return f"{t // 60}:{t % 60:02d}"


def dash(value, fmt="{}"):
    """A value as text, or '-' when it is missing."""
    if value is None or value == "":
        return "-"
    try:
        return fmt.format(value)
    except (ValueError, TypeError):
        return str(value)


def spark_line(values, width, relative=False):
    """A tiny bar chart of the newest values, `width` characters wide. Older
    samples are squeezed by taking the biggest of each group. The bars run from
    zero to the peak; with relative=True from the lowest to the highest value
    (a flat line for a steady ping, instead of a solid block)."""
    vals = [v for v in values if v is not None]
    if not vals or width <= 0:
        return ""
    if len(vals) > width:
        per = -(-len(vals) // width)
        vals = [max(vals[i:i + per]) for i in range(0, len(vals), per)]
    if relative:
        lo, hi = min(vals), max(vals)
        if hi - lo < 1e-9:
            return ("▄" * len(vals)).rjust(width)
        return "".join(SPARK[1 + round((v - lo) / (hi - lo) * 7)] for v in vals).rjust(width)
    peak = max(vals) or 1.0
    return "".join(SPARK[max(1, min(8, round(v / peak * 8)))] if v > 0 else SPARK[0] for v in vals).rjust(width)


# ── Seats ─────────────────────────────────────────────────────────────────────
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


def seat_health(seat):
    """One word for how well the seat's link is doing."""
    if not seat["connected"]:
        return "held" if seat["held_s"] is not None else "empty"
    seen = seat.get("seen_s")
    if seen is not None and seen >= 5:
        return "stalled"
    if seen is not None and seen >= 3:
        return "quiet"
    if seat.get("queue", 0) >= 20:
        return "slow"
    rtt = seat.get("rtt_ms")
    if rtt is not None and rtt > 150:
        return "laggy"
    return "good"


def kd_text(seat):
    k, d = seat.get("kills", 0), seat.get("deaths", 0)
    if not k and not d:
        return "-"
    ratio = k / d if d else float(k)
    return f"{k}/{d} {ratio:.1f}"


def screen_text(seat):
    """v0.0.37: the screen's own numbers from its client_stats card: '60fps 1.2ms' (draw a second, proc ms)."""
    card = seat.get("stats") or {}
    fps = card.get("fps") or {}
    if not fps or not seat.get("connected"):
        return "-"
    return f"{fps.get('draw', 0):.0f}fps {fps.get('proc', 0):.1f}ms"


def tape_text(seat):
    """The Tape column (v0.0.25): what this screen's tape holds.
    ● 5.0s ·2 = recording, 5 s on the tape, 2 kills stamped this round.
    ■ R3 ✓ = frozen for round 3 with the closing kill stamped (■ R3 without it).
    v0.0.26: ▶ R3 = the screen is playing the round 3 replay, ■ R3 ✓ ▶5.1s = it
    played it (5.1 s), ■ R3 ✓ ✗ = it skipped it (the [TAPE] log line says why)."""
    card = seat.get("tape")
    if not card or not seat["connected"]:
        return "-"
    if card.get("frozen"):
        last = card.get("last") or {}
        rp = card.get("replay") or {}
        if rp.get("playing"):
            return f"▶ R{card.get('round', '?')}"
        text = f"■ R{card.get('round', '?')}" + (" ✓" if last.get("closing") else "")
        if rp.get("played"):
            text += f" ▶{(rp.get('dur_ms') or 0) / 1000.0:.1f}s"
        elif rp.get("skipped"):
            text += " ✗"
        return text
    span = (card.get("span_ms") or 0) / 1000.0
    return f"● {span:.1f}s ·{card.get('stamps', 0)}"


def seat_rows(status, ping_hist=None):
    """The seat table as plain values: one dict per seat."""
    rows = []
    for seat in status["seats"]:
        state, colour = seat_state(seat, status["match"]["state"])
        playing = status["match"]["state"] == "PLAYING" and seat["playing"]
        bot = seat.get("bot")
        name = seat["name"] or "-"
        if bot:
            name += " 🤖"
        hist = (ping_hist or {}).get(seat["id"]) or []
        rows.append({
            "seat": f"P{seat['id']}", "name": name,
            "cls": seat["class_name"] or "-", "state": state, "colour": colour,
            "lives": "♥" * seat["stocks"] if playing else "-",
            "crowns": str(seat["crowns"]) if seat["crowns"] else "-",
            "kd": kd_text(seat),
            "ping": dash(seat.get("rtt_ms"), "{} ms") if seat["connected"] else "-",
            "trend": spark_line(hist, 8, relative=True) if seat["connected"] and sum(v is not None for v in hist) >= 3 else "",
            "health": seat_health(seat),
            "tape": tape_text(seat),
            "screen": screen_text(seat),
            "link": f"{seat['transport']} {seat['ip']}" if seat["connected"] else "-",
            "pps": f"{seat['in_pps']:.0f}" if seat["connected"] else "-",
            "queue": f"{seat['queue']}/{seat['dropped']}" if seat["connected"] else "-",
            "seen": f"{seat['seen_s']:.0f}s" if seat["seen_s"] is not None else "-",
        })
    return rows


SEAT_COLS = (("Seat", "left", "seat"), ("Name", "left", "name"), ("Class", "left", "cls"),
             ("State", "left", "state"), ("Lives", "left", "lives"), ("Crowns", "right", "crowns"),
             ("K/D", "right", "kd"), ("Ping", "right", "ping"), ("Trend", "left", "trend"),
             ("Health", "left", "health"), ("Tape", "left", "tape"), ("Screen", "left", "screen"), ("Link", "left", "link"), ("In/s", "right", "pps"),
             ("Q/drop", "right", "queue"), ("Seen", "right", "seen"))


# ── Header and traffic ────────────────────────────────────────────────────────
def header_text(status, age, deck=None):
    m = status["match"]
    players = sum(1 for s in status["seats"] if s["connected"])
    bots = status.get("bots", 0)
    parts = [f"TOWER BRAWL {status['version']}", m["state"]]
    if m["state"] == "PLAYING":
        parts.append(f"round {m['round']}")
        parts.append(f"flips {m['flips']}")
    ptxt = f"{players} player{'s' if players != 1 else ''}"
    if bots:
        ptxt += f" ({bots} bot{'s' if bots != 1 else ''})"
    parts.append(ptxt)
    parts.append(f"{status['spectators']} spectator{'s' if status['spectators'] != 1 else ''}")
    if (status.get("harness") or {}).get("active"):
        parts.append("SEATS LOCKED (harness)")   # v0.0.23: the server keeps the seats for bots
    parts.append(f"up {fmt_uptime(status['uptime_s'])}")
    parts.append(f"{age:.1f}s ago")
    if deck is not None and deck.paused:
        parts.append("PAUSED (p)")
    if deck is not None and deck.message_text():
        parts.append(deck.message_text())
    return " | ".join(parts)


def traffic_lines(status, hist=None):
    """Two tidy lines: what comes in, what goes out. With a history, two more
    lines with the 60 s curve of each."""
    t = status["traffic"]
    top = "   ".join(f"{k} {v:g}/s" for k, v in sorted(t["in_types_s"].items(), key=lambda kv: -kv[1])[:5])
    queued = sum(s.get("queue", 0) for s in status["seats"])
    lines = [f"IN  {t['in_pps']:7.1f} pkt/s {t['in_kbps']:7.2f} KB/s     {top or '-'}",
             f"OUT {t['out_pps']:7.1f} pkt/s {t['out_kbps']:7.2f} KB/s     "
             f"fail {t['fail_s']:g}/s   drop {t['drop_s']:g}/s   queued {queued}   threads {status['threads']}"]
    if hist and (hist.get("in") or hist.get("out")):
        for key, label in (("in", "in "), ("out", "out")):
            vals = list(hist.get(key) or [])
            if vals:
                lines.append(f"{label} KB/s {spark_line(vals, HISTORY)}  peak {max(vals):.2f}  ({len(vals)} s)")
    return lines


def stale_text(status, age):
    if status is None:
        return f"no {os.path.basename(STATUS_FILE)} yet. Is the server running?  systemctl --user status towerbrawl"
    return f"no fresh status for {age:.0f} s. Is the server running?  systemctl --user status towerbrawl"


# ── Fight strip ───────────────────────────────────────────────────────────────
def timeline_now(status):
    """(now_t, timeline) for the current or last match, or (None, tl) with no match.
    now_t is the newest match second the strip should reach."""
    tl = status["match"].get("timeline") or {}
    started = tl.get("started_at")
    if not started:
        return None, tl
    kills = tl.get("kills") or []
    rounds = tl.get("rounds") or []
    last = [0.0] + [k[0] for k in kills] + [r[1] for r in rounds]
    last += [r[3] for r in rounds if len(r) > 3 and r[3] is not None]
    if tl.get("ended_at") is not None:
        last.append(tl["ended_at"])
    if status["match"]["state"] == "PLAYING":
        last.append(status["written_at"] - started)
    return max(last), tl


def axis_interval(bin_s):
    """Seconds between axis labels: at least 8 columns apart."""
    for cand in (1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800):
        if cand / bin_s >= 8:
            return cand
    return 3600


def tape_inspect(status, rnd):
    """v0.0.25: which screens froze a tape for round `rnd`, from seats[].tape."""
    frozen = []
    for seat in status["seats"]:
        card = seat.get("tape") or {}
        if card.get("frozen") and card.get("round") == rnd:
            frozen.append((seat["id"], card.get("last") or {}))
    if not frozen:
        return f"no screen has a frozen tape for round {rnd}"
    who = " ".join(f"P{pid}" for pid, _ in frozen)
    lasts = [last for _, last in frozen if last.get("closing")]
    text = f"tape frozen on {len(frozen)} screen{'s' if len(frozen) != 1 else ''} ({who})"
    if lasts:
        before = min(int(l.get("before") or 0) for l in lasts)
        after = min(int(l.get("after") or 0) for l in lasts)
        text += f", {before} frames before the kill / {after} after"
    else:
        text += ", no closing kill stamped"
    # v0.0.26: the replay cards of those screens
    played, playing, skipped = [], [], []
    for seat in status["seats"]:
        card = seat.get("tape") or {}
        rp = card.get("replay") or {}
        if not rp or card.get("round") != rnd:
            continue
        if rp.get("playing"):
            playing.append(seat["id"])
        elif rp.get("played"):
            played.append((seat["id"], rp))
        elif rp.get("skipped"):
            skipped.append((seat["id"], rp.get("skipped")))
    if played:
        who = " ".join(f"P{pid}" for pid, _ in played)
        dur = max(int(rp.get("dur_ms") or 0) for _, rp in played) / 1000.0
        late = max(int(rp.get("late_ms") or 0) for _, rp in played) / 1000.0
        text += f" · replay played on {len(played)} screen{'s' if len(played) != 1 else ''} ({who}), {dur:.1f} s, started {late:.1f} s after the kill"
        if any(rp.get("cut") for _, rp in played):
            text += ", cut by the next round"
    if playing:
        text += " · replay playing on " + " ".join(f"P{pid}" for pid in playing)
    if skipped:
        text += " · replay skipped on " + ", ".join(f"P{pid} ({why})" for pid, why in skipped)
    return text


def build_strip(status, view):
    """The fight strip as rows of cells, from the timeline and the deck's view.
    view = {"cells": n, "bin_s": s, "follow": bool, "end_t": s or None, "selected_t": s or None}.
    Returns None when there is no match to draw, else a dict with:
      rows      [(label, label_style, [(ch, fg_style, band, selected), ...]), ...]
      start_t, now_t, bin_s, cells, title, subtitle, inspect (text or None)."""
    now_t, tl = timeline_now(status)
    if now_t is None:
        return None
    kills = tl.get("kills") or []
    rounds = tl.get("rounds") or []
    n = view["cells"]
    bin_s = view["bin_s"]
    span = n * bin_s
    end_t = now_t if view["follow"] or view["end_t"] is None else min(view["end_t"], now_t)
    end_t = max(end_t, min(span, now_t))
    start_t = max(0.0, end_t - span)
    names = {s["id"]: (s["name"] or f"P{s['id']}") for s in status["seats"]}
    # v0.0.24: the server stamps the names behind the seats on the timeline, so a
    # seat that changed hands after the match keeps its fighter's name here.
    for pid_txt, name in (tl.get("names") or {}).items():
        try:
            names[int(pid_txt)] = name
        except (TypeError, ValueError):
            pass
    live = status["match"]["state"] == "PLAYING"

    def col(t):
        i = int((t - start_t) // bin_s)
        return i if 0 <= i < n else None

    cells = [{"t0": start_t + i * bin_s, "kills": {}, "deaths": {}, "total": 0, "events": [],
              "round_start": None, "round_end": None, "match_end": None, "crown": None,
              "future": start_t + i * bin_s > now_t}
             for i in range(n)]
    for k in kills:
        t, killer, victim, weapon = k[0], k[1], k[2], k[3] if len(k) > 3 else ""
        i = col(t)
        if i is None:
            continue
        c = cells[i]
        c["total"] += 1
        c["deaths"].setdefault(victim, []).append(killer)
        if killer and killer != victim:
            c["kills"].setdefault(killer, []).append((victim, weapon))
            c["events"].append(f"{names.get(killer, '?')} (P{killer}) killed {names.get(victim, '?')} (P{victim}) with {weapon or '?'}")
        else:
            c["events"].append(f"{names.get(victim, '?')} (P{victim}) died ({weapon or 'fall'})")
    for r in rounds:
        rnd, t0, winner = r[0], r[1], r[2]
        t_end = r[3] if len(r) > 3 else None
        i = col(t0)
        if i is not None and rnd > 1:
            cells[i]["round_start"] = rnd
            cells[i]["events"].append(f"round {rnd} started")
        if t_end is not None:
            j = col(t_end)
            if j is not None:
                cells[j]["round_end"] = (rnd, winner)
                who = f"P{winner} {names.get(winner, '')} won" if winner else "no winner"
                cells[j]["events"].append(f"round {rnd} ended, {who}")
            # The round's last kill is the winner's own kill, so the crown sits one
            # column later (inside the gap before the next round: 2.6 s, or 6.5 s after a kill since v0.0.26), on the winner's lane.
            jc = col(t_end + bin_s)
            if jc is not None and winner:
                cells[jc]["crown"] = winner
    if tl.get("ended_at") is not None:
        i = col(tl["ended_at"])
        if i is not None:
            cells[i]["match_end"] = tl.get("winner") or 0
            cells[i]["events"].append(f"match over, P{tl.get('winner')} {names.get(tl.get('winner'), '')} won the match")
    # which round a column belongs to, for the background bands
    starts = sorted((r[1], r[0]) for r in rounds)
    for c in cells:
        rnd = 1
        for t0, r_no in starts:
            if t0 <= c["t0"] + bin_s * 0.999:
                rnd = r_no
        c["band"] = (rnd % 2 == 0) and not c["future"]

    sel_i = None
    if view.get("selected_t") is not None:
        sel_i = col(view["selected_t"])

    # lanes: everyone playing plus everyone on the timeline
    lanes = set()
    if live:
        lanes |= {s["id"] for s in status["seats"] if s.get("playing")}
    lanes |= {pid for k in kills for pid in (k[1], k[2]) if 1 <= pid <= 4}
    lanes |= {r[2] for r in rounds if r[2]}
    lanes = sorted(p for p in lanes if 1 <= p <= 4)
    by_id = {s["id"]: s for s in status["seats"]}

    def marker(c, pid=None):
        """The mark of a column with no kill on this lane, or None."""
        if c["match_end"] is not None:
            return "║", "bold cyan"
        if pid is not None and c["crown"] == pid:
            return "♛", "bold yellow"
        if c["round_end"] is not None:
            return "┫", "bold white"
        if c["round_start"] is not None:
            return "┃", "bold white"
        return None

    rows = []
    label_bin = f"{bin_s:g}s"
    spark = []
    for i, c in enumerate(cells):
        sel = i == sel_i
        if c["total"]:
            spark.append((SPARK[min(c["total"], 8)], "red", c["band"], sel))
        else:
            mk = marker(c)
            if mk:
                spark.append((mk[0], mk[1], c["band"], sel))
            else:
                spark.append((" ", "dim", c["band"], sel))
    rows.append((f"kills/{label_bin}", "bold", spark))
    for pid in lanes:
        lane = []
        for i, c in enumerate(cells):
            sel = i == sel_i
            ks, ds = c["kills"].get(pid, []), c["deaths"].get(pid, [])
            k, d = len(ks), len(ds)
            if k + d >= 2 and not (k == 1 and d == 1):
                ch = str(min(k + d, 9))
                style = "bold green" if not d else ("bold red" if not k else "bold magenta")
            elif k and d:
                ch, style = "◈", "bold magenta"
            elif k:
                victim, weapon = ks[0]
                ch, style = WEAPON_GLYPH.get(weapon, "◆"), "bold " + SEAT_STYLE.get(victim, "white")
            elif d:
                killer = ds[0]
                ch = "✕"
                style = ("bold " + SEAT_STYLE[killer]) if killer in SEAT_STYLE and killer != pid else "bold white"
            else:
                mk = marker(c, pid)
                if mk:
                    ch, style = mk
                elif c["future"]:
                    ch, style = " ", "dim"
                else:
                    ch, style = "·", "dim"
            lane.append((ch, style, c["band"], sel))
        seat = by_id.get(pid, {})
        label = f"P{pid} {names.get(pid, '')[:8]}".rstrip()
        if seat.get("crowns"):
            label += f" ♛{seat['crowns']}"
        label += f" {seat.get('kills', 0)}/{seat.get('deaths', 0)}"
        rows.append((label[:LABEL_W], "bold " + SEAT_STYLE.get(pid, "white"), lane))
    # round row: "R2 19s ♛P1" written from the round's first column, cut at the next round
    round_cells = [("─" if not c["future"] else " ", "dim", c["band"], i == sel_i) for i, c in enumerate(cells)]
    ordered = sorted(rounds, key=lambda r: r[1])
    for idx, r in enumerate(ordered):
        rnd, t0, winner = r[0], r[1], r[2]
        t_end = r[3] if len(r) > 3 else None
        i = col(t0) if t0 >= start_t else (0 if t0 < start_t <= (ordered[idx + 1][1] if idx + 1 < len(ordered) else now_t + 1) else None)
        if i is None:
            continue
        limit = n
        if idx + 1 < len(ordered):
            j = col(ordered[idx + 1][1])
            if j is not None:
                limit = j
        text = f"R{rnd}"
        if t_end is not None:
            text += f" {t_end - t0:.0f}s"
            text += f" ♛ P{winner}" if winner else " no winner"
        if len(text) > limit - i:
            text = f"R{rnd}" + (f" {t_end - t0:.0f}s" if t_end is not None and len(f"R{rnd} {t_end - t0:.0f}s") <= limit - i else "")
        for k, ch in enumerate(text[:max(0, limit - i)]):
            if i + k < n:
                round_cells[i + k] = (ch, "cyan", cells[i + k]["band"], (i + k) == sel_i)
    rows.append(("round", "dim", round_cells))
    # time axis
    axis = [("─", "dim", False, i == sel_i) for i in range(n)]
    step = axis_interval(bin_s)
    i = 0
    while i < n:
        t0 = cells[i]["t0"]
        tick = None
        for m in range(int(t0 // step), int((t0 + bin_s) // step) + 1):
            if t0 <= m * step < t0 + bin_s:
                tick = m * step
                break
        if tick is None:
            i += 1
            continue
        axis[i] = ("┴", "white", False, i == sel_i)
        label = fmt_clock(tick)
        for k, ch in enumerate(label):
            if i + 1 + k < n:
                axis[i + 1 + k] = (ch, "white", False, (i + 1 + k) == sel_i)
        i += 1 + len(label) + 1
    if sel_i is not None:
        axis[sel_i] = ("▲", "bold yellow", False, False)
    rows.append(("time", "dim", axis))

    inspect = None
    if view.get("selected_t") is not None:
        if sel_i is None:
            inspect = f"selected {fmt_clock(view['selected_t'])} is off screen (End = live, or pan)"
        else:
            c = cells[sel_i]
            inspect = f"{fmt_clock(c['t0'])}  " + (" · ".join(c["events"]) if c["events"] else f"nothing happened in this {label_bin}")
            if c["round_end"] is not None:
                inspect += " · " + tape_inspect(status, c["round_end"][0])
    n_kills = len(kills)
    title = f"FIGHT  {n_kills} kill{'s' if n_kills != 1 else ''}"
    if rounds:
        title += f"  round {rounds[-1][0]}"
    title += f"  clock {fmt_clock(now_t)}"
    if now_t >= 30 and n_kills:
        title += f"  {n_kills / (now_t / 60):.1f} kills/min"
    if not live:
        title += f"  (last match, P{tl.get('winner')} won)" if tl.get("winner") else "  (last match)"
    if not (view["follow"] or end_t >= now_t):
        title += f"  view {fmt_clock(start_t)}-{fmt_clock(end_t)} (End = live)"
    return {"rows": rows, "start_t": start_t, "now_t": now_t, "bin_s": bin_s, "cells": n, "end_t": end_t,
            "following": view["follow"] or end_t >= now_t, "live": live, "title": title, "subtitle": LEGEND,
            "inspect": inspect}


# ── Bot arena ─────────────────────────────────────────────────────────────────
def merge_cards(server_card, harness_card):
    """One bot card from the server's copy and the harness's copy. The server's
    card (sent by the bot itself) wins; empty fields are filled from the harness."""
    if server_card is None:
        return dict(harness_card) if harness_card else None
    card = dict(server_card)
    if harness_card:
        for k, v in harness_card.items():
            if card.get(k) is None and v is not None:
                card[k] = v
    return card


def bot_cards(status, harness):
    """All bot cards by seat: brains, plain headless clients and protocol bots
    (v0.0.24: every kind, before only brains). The seat's kill and death counts
    fill the card's combat slots when the bot did not send them."""
    by_seat = {}
    for seat in status["seats"]:
        card = seat.get("bot")
        if card:
            by_seat[seat["id"]] = merge_cards(card, None)
    if harness:
        for card in harness.get("bots") or []:
            pid = card.get("seat")
            if pid is None:
                continue
            merged = merge_cards(by_seat.get(pid), card)
            if merged.get("updated_at") is None:
                merged["updated_at"] = harness.get("written_at")
            by_seat[pid] = merged
    seats = {s["id"]: s for s in status["seats"]}
    for pid, card in by_seat.items():
        seat = seats.get(pid) or {}
        card["name"] = seat.get("name")
        combat = dict(card.get("combat") or {})
        if combat.get("kills") is None:
            combat["kills"] = seat.get("kills", 0)
        if combat.get("deaths") is None:
            combat["deaths"] = seat.get("deaths", 0)
        card["combat"] = combat
    return [by_seat[k] for k in sorted(by_seat)]


def learn_text(card):
    """The learning slots as short chips: 'ep 3  r +0.40  w_speed +0.12'. '-' while empty."""
    learn = card.get("learning") or {}
    bits = []
    if learn.get("episode") is not None:
        bits.append(f"ep {learn['episode']}")
    if learn.get("reward") is not None:
        bits.append(f"r {learn['reward']:+.2f}")
    deltas = learn.get("deltas") or {}
    for k, v in list(deltas.items())[:4]:
        try:
            bits.append(f"{k} {float(v):+.2f}")
        except (TypeError, ValueError):
            bits.append(f"{k} {v}")
    return "  ".join(bits) if bits else "-"


def pct(value):
    if value is None:
        return "-"
    try:
        return f"{float(value):.0f}%"
    except (TypeError, ValueError):
        return str(value)


def bot_rows(cards, now):
    rows = []
    for c in cards:
        actions = c.get("actions") or {}
        nav = c.get("nav") or {}
        aim = c.get("aim") or {}
        combat = c.get("combat") or {}
        kind = c.get("kind") or "?"
        state = c.get("state")
        if state is None and kind == "brain" and not actions:
            state = "no card yet"          # the join card is here, the first bot_status (5 s) is not
        age = None
        if c.get("updated_at"):
            age = max(0, int(now - c["updated_at"]))
        k, d = combat.get("kills"), combat.get("deaths")
        kd = f"{k}/{d}" if (k or d) else "-"
        rows.append({
            "seat": f"P{c.get('seat', '?')}",
            "name": dash(c.get("name")),
            "kind": kind,
            "persona": dash(c.get("persona")) if kind == "brain" else "-",
            "diff": dash(c.get("difficulty"), "{:.2f}"),
            "state": dash(state),
            "target": dash(c.get("target"), "P{}"),
            "kd": kd,
            "acc": pct(combat.get("accuracy")),
            "air": pct(combat.get("air_time_pct")),
            "decisions": dash(actions.get("decisions")),
            "attacks": dash(actions.get("attacks")),
            "specials": dash(actions.get("specials")),
            "evades": dash(actions.get("evades")),
            "wraps": dash(nav.get("wraps")),
            "loop": dash(nav.get("max_loop")),
            "aim": dash(aim.get("err_mean_deg"), "{:.1f}°"),
            "age": dash(age, "{}s"),
            "up": dash(c.get("uptime_s"), "{}s"),
            "learn": learn_text(c),
        })
    return rows


BOT_COLS_BASE = (("Seat", "left", "seat"), ("Name", "left", "name"), ("Kind", "left", "kind"),
                 ("Persona", "left", "persona"), ("Diff", "right", "diff"), ("State", "left", "state"),
                 ("Target", "left", "target"), ("K/D", "right", "kd"))
BOT_COLS_COMBAT = (("Acc", "right", "acc"), ("Air", "right", "air"))
BOT_COLS_TAIL = (("Dec", "right", "decisions"), ("Atk", "right", "attacks"), ("Spc", "right", "specials"),
                 ("Evd", "right", "evades"), ("Wrap", "right", "wraps"), ("Loop", "right", "loop"),
                 ("Aim", "right", "aim"), ("Age", "right", "age"), ("Up", "right", "up"))
BOT_COLS_LEARN = (("Learn Δ", "left", "learn"),)


BOT_COLS_ALWAYS = ("seat", "name", "kind", "persona", "state", "kd", "age")


def bot_columns(rows):
    """The columns to draw. A column that is '-' on every row is left out (the
    combat and learning slots, the target, the brain numbers for headless-only
    runs), so the table stays narrow until a brain fills them."""
    cols = list(BOT_COLS_BASE) + list(BOT_COLS_COMBAT) + list(BOT_COLS_TAIL) + list(BOT_COLS_LEARN)
    return [c for c in cols if c[2] in BOT_COLS_ALWAYS or any(r[c[2]] != "-" for r in rows)]


def bot_title(cards):
    counts = {}
    for c in cards:
        counts[c.get("kind") or "?"] = counts.get(c.get("kind") or "?", 0) + 1
    words = {"brain": "brain", "headless": "headless client", "protocol": "protocol bot"}
    bits = [f"{n} {words.get(k, k)}{'s' if n != 1 else ''}" for k, n in sorted(counts.items())]
    return "BOT ARENA  " + ", ".join(bits)


# ── Harness deck ──────────────────────────────────────────────────────────────
def harness_view(harness, now, expected=None):
    """What to draw for the harness, or None. Returns a dict:
    {"mode": "live" | "summary", ...} with the pieces the renderers need."""
    if harness is None:
        return None
    expected = expected or {}
    age = now - harness.get("written_at", 0)
    state = harness.get("state", "idle")
    suite = harness.get("suite") or {}
    results = harness.get("results") or []
    if state in ("done", "aborted"):
        if age > HARNESS_KEEP:
            return None
        when = time.strftime("%H:%M:%S", time.localtime(harness.get("written_at", now)))
        total = suite.get("total", len(results))
        ok = suite.get("passed", 0) + suite.get("minor", 0)
        word = "aborted" if state == "aborted" else "finished"
        txt = (f"last harness run {word} {when}: {ok}/{total} passed"
               + (f", {suite.get('minor', 0)} minor" if suite.get("minor") else "")
               + (f", {suite.get('failed', 0)} FAILED" if suite.get("failed") else "")
               + f"  ({harness.get('version', '')}, seed {harness.get('seed', '')})")
        style = "bold red" if suite.get("failed") else ("yellow" if suite.get("minor") or state == "aborted" else "green")
        return {"mode": "summary", "text": txt, "style": style}
    if age > HARNESS_STALE:
        return {"mode": "summary", "style": "bold red",
                "text": f"harness run stopped answering {age:.0f} s ago (state {state}, pid {harness.get('pid')})"}
    sc = harness.get("scenario") or {}
    names = suite.get("names") or []
    done = {r["scenario"]: r for r in results}
    index = suite.get("index", len(results))
    total = suite.get("total", len(names)) or 1
    inner = 0.0
    if sc.get("duration_s"):
        inner = min(max(sc.get("elapsed_s", 0.0) / sc["duration_s"], 0.0), 1.0)
    progress = min((index + (inner if sc else 0.0)) / total, 1.0)
    elapsed = now - harness.get("started_at", now)
    if state == "restarting":
        title = f"HARNESS  ↻ restarting the server for {sc.get('name', '?')}  {index}/{total}"
    elif sc:
        title = f"HARNESS  ▶ {sc.get('name', '?')}  {index + 1}/{total}"
    else:
        title = f"HARNESS  {index}/{total}"
    checklist = []
    eta = 0.0
    known = 0
    slow = False
    running_elapsed = sc.get("elapsed_s", 0.0) if sc else 0.0
    for name in names:
        exp = expected.get(name)
        if name in done:
            checklist.append((name, done[name]["result"], done[name].get("elapsed_s"), False))
        elif sc and name == sc.get("name"):
            is_slow = bool(exp and running_elapsed > 2 * exp and running_elapsed > exp + 10)
            slow = slow or is_slow
            checklist.append((name, "RUNNING", running_elapsed, is_slow))
            if exp:
                eta += max(exp - running_elapsed, 0.0)
                known += 1
        else:
            checklist.append((name, "WAITING", None, False))
            if exp:
                eta += exp
                known += 1
    eta_txt = ""
    if known and state == "running":
        eta_txt = f"ETA {fmt_uptime(eta)}"
    soak = harness.get("soak")
    soak_txt = ""
    if soak:
        left = max(soak.get("deadline_at", now) - now, 0)
        soak_txt = f"soak pass {soak.get('pass_no', 0) + 1}, {fmt_uptime(left)} left"
    return {"mode": "live", "title": title, "progress": progress, "elapsed": elapsed, "eta": eta_txt, "slow": slow,
            "desc": sc.get("desc", ""), "step": sc.get("step", ""), "checklist": checklist,
            "findings": sc.get("findings") or {}, "warnings": sc.get("warnings") or {},
            "suite": suite, "soak": soak_txt, "state": state, "command": harness.get("command", "")}


def progress_bar(fraction, width):
    filled = int(round(fraction * width))
    return "█" * filled + "░" * (width - filled)


def harness_lines_plain(view):
    if view["mode"] == "summary":
        return [view["text"]]
    lines = [f"{view['title']}  [{progress_bar(view['progress'], 24)}] {view['progress'] * 100:3.0f}%  {fmt_uptime(view['elapsed'])}"
             + (f"   {view['eta']}" if view["eta"] else "")
             + (f"   {view['soak']}" if view["soak"] else "")]
    if view["desc"]:
        lines.append(f"tests: {view['desc']}")
    if view["step"]:
        lines.append(f"step:  {view['step']}")
    marks = {"PASS": "✔", "FAIL": "✖", "MINOR": "▲", "RUNNING": "●", "WAITING": "○"}
    items = []
    for name, result, elapsed, slow in view["checklist"]:
        item = f"{marks[result]} {name}"
        if result == "RUNNING" and elapsed is not None:
            item += f" {elapsed:.0f}s" + (" SLOW" if slow else "")
        items.append(item)
    lines.append("  ".join(items))
    s = view["suite"]
    tally = f"passed {s.get('passed', 0)}  minor {s.get('minor', 0)}  failed {s.get('failed', 0)}"
    if view["findings"]:
        tally += "   ✖ " + "  ".join(f"{k} ×{v['count']}" for k, v in view["findings"].items())
    if view["warnings"]:
        tally += "   ▲ " + "  ".join(f"{k} ×{v['count']}" for k, v in view["warnings"].items())
    lines.append(tally)
    return lines


# ── The deck: what the viewer is looking at, and what it remembers ────────────
class Deck:
    """Everything that is not in the two files: the zoom and the pan, the
    selection, pause, filters, the alert list, and 60 s of ping and traffic."""

    def __init__(self, status_file=STATUS_FILE, harness_file=HARNESS_FILE, zoom=DEFAULT_ZOOM):
        self.status_file = status_file
        self.harness_file = harness_file
        self.zoom = zoom
        self.follow = True
        self.end_t = None
        self.selected_t = None
        self.paused = False
        self.quit = False
        self.hidden_tags = set()
        self.events_scroll = 0
        self.alerts = []               # (arrived_at, text)
        self.message = None            # (expires_at, text)
        self.ping_hist = {pid: deque(maxlen=HISTORY) for pid in range(1, 5)}
        self.traffic_hist = {"in": deque(maxlen=HISTORY), "out": deque(maxlen=HISTORY)}
        self.event_ring = deque(maxlen=500)
        self.seen = set()
        self.seeded = False
        self.expected = load_expected()
        self.status = None
        self.age = 0.0
        self.harness = None
        self.now = time.time()
        self.strip_geom = None         # (y0, y1, x0, cells, start_t, bin_s) of the last drawn strip
        self.controls = False          # --controls: the SERVER panel with the play link and bot buttons
        self.show_wifi = False         # w: the wifi help panel
        self.show_bots = False         # a: the bot menu (v0.0.41): pick a persona by key or click
        self.show_info = False         # i: the about panel with the GitHub link (v0.0.41)
        self.button_geom = []          # [(y, x0, x1, action)] of the last drawn buttons, 1-based cells
        self._ip = ("", 0.0)           # (address, time it was read)
        self.events_geom = None        # (y0, y1) of the last drawn events panel
        self.last_view = None          # the strip dict of the last draw

    # -- reading --------------------------------------------------------------
    def tick(self, now=None):
        self.now = now if now is not None else time.time()
        if self.paused:
            return
        status = read_json(self.status_file)
        self.harness = read_json(self.harness_file)
        if status is None:
            self.status = None
            self.age = 0.0
            return
        fresh = self.status is None or status.get("written_at") != self.status.get("written_at")
        self.status = status
        self.age = (self.now - status["written_at"]) if "written_at" in status else 0.0
        if fresh:
            self._remember(status)

    def _remember(self, status):
        for seat in status.get("seats") or []:
            pid = seat.get("id")
            if pid in self.ping_hist:
                self.ping_hist[pid].append(seat.get("rtt_ms") if seat.get("connected") else None)
        t = status.get("traffic") or {}
        self.traffic_hist["in"].append(float(t.get("in_kbps", 0.0)))
        self.traffic_hist["out"].append(float(t.get("out_kbps", 0.0)))
        for ev in status.get("events") or []:
            key = (ev.get("t"), ev.get("msg"))
            if key in self.seen:
                continue
            self.seen.add(key)
            self.event_ring.append(ev)
            if self.seeded:
                self._maybe_alert(ev)
        if len(self.seen) > 2000:
            self.seen = {(e.get("t"), e.get("msg")) for e in self.event_ring}
        self.seeded = True

    def _maybe_alert(self, ev):
        msg = ev.get("msg", "")
        text = None
        if ev.get("level") == "ERROR":
            text = f"ERROR  {msg}"
        elif ev.get("tag") == "NET" and "stall" in msg.lower():
            text = f"STALL  {msg}"
        elif "harness gate" in msg or "join_locked" in msg:
            text = f"GATE  {msg}"
        if text:
            self.alerts.append((self.now, text))

    def alert_text(self):
        self.alerts = [a for a in self.alerts if self.now - a[0] <= ALERT_KEEP]
        if not self.alerts:
            return None
        text = self.alerts[-1][1]
        if len(self.alerts) > 1:
            text += f"   (+{len(self.alerts) - 1} more)"
        return text

    def message_text(self):
        if self.message and self.now <= self.message[0]:
            return self.message[1]
        return None

    def say(self, text):
        self.message = (self.now + MESSAGE_KEEP, text)

    # -- --controls: the server panel ----------------------------------------
    def lan_ip(self):
        """This machine's LAN address, re-read every 10 s (empty when there is no network)."""
        if self.now - self._ip[1] > 10:
            import socket
            ip = ""
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sock.connect(("1.1.1.1", 80))
                ip = sock.getsockname()[0]
                sock.close()
            except OSError:
                pass
            self._ip = (ip, self.now)
        return self._ip[0]

    def bot_action(self, action, persona=None):
        """Run tools/tbbot.py add [persona] / remove / clear and show its first line."""
        import subprocess
        cmd = [sys.executable, os.path.join(ROOT, "tools", "tbbot.py"), action]
        if persona:
            cmd.append(persona)
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.TimeoutExpired) as e:
            out = f"tbbot failed: {e}"
        self.say((out.strip().splitlines() or ["done"])[0])

    def button_at(self, x, y):
        for by, x0, x1, action in self.button_geom:
            if y == by and x0 <= x <= x1:
                return action
        return None

    # -- the view -------------------------------------------------------------
    @property
    def bin_s(self):
        return ZOOM_LADDER[self.zoom]

    def view(self, cells):
        return {"cells": cells, "bin_s": self.bin_s, "follow": self.follow, "end_t": self.end_t,
                "selected_t": self.selected_t}

    def filtered_events(self):
        return [e for e in self.event_ring if e.get("tag") not in self.hidden_tags]

    def pan(self, steps):
        """Move the window by `steps` columns; + is later, - is earlier."""
        lv = self.last_view
        if not lv:
            return
        span = lv["cells"] * lv["bin_s"]
        end = lv["end_t"] + steps * lv["bin_s"]
        end = max(end, min(span, lv["now_t"]))
        if end >= lv["now_t"]:
            self.follow = True
            self.end_t = None
        else:
            self.follow = False
            self.end_t = end

    def zoom_to(self, index, at_col=None):
        """Change the seconds per column, keeping the time under `at_col` where it is."""
        index = max(0, min(len(ZOOM_LADDER) - 1, index))
        lv = self.last_view
        if index == self.zoom or not lv:
            self.zoom = index
            return
        if at_col is None:
            at_col = lv["cells"] // 2
        t_at = lv["start_t"] + at_col * lv["bin_s"]
        new_bin = ZOOM_LADDER[index]
        start = max(0.0, t_at - at_col * new_bin)
        end = start + lv["cells"] * new_bin
        self.zoom = index
        if end >= lv["now_t"]:
            self.follow = True
            self.end_t = None
        else:
            self.follow = False
            self.end_t = end

    def strip_col(self, x, y):
        """The strip column under terminal cell (x, y), or None."""
        g = self.strip_geom
        if not g:
            return None
        y0, y1, x0, cells, _start, _bin = g
        if y0 <= y <= y1 and x0 <= x < x0 + cells:
            return x - x0
        return None

    def in_events(self, y):
        g = self.events_geom
        return bool(g and g[0] <= y <= g[1])

    def snapshot(self, width):
        name = time.strftime("deck_snapshot_%H-%M-%S.txt")
        path = os.path.join(ROOT, name)
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(render_plain(self, 40, width=width) + "\n")
            self.say(f"saved {name}")
        except OSError as e:
            self.say(f"snapshot failed: {e}")

    def handle(self, events, width):
        """Apply keys and mouse events. Returns True when something changed."""
        changed = False
        for ev in events:
            changed = True
            if ev[0] == "key":
                self._key(ev[1], width)
            elif ev[0] == "wheel":
                _, step, ctrl, shift, x, y = ev
                if ctrl or shift:
                    self.zoom_to(self.zoom + (1 if step > 0 else -1), self.strip_col(x, y))
                elif self.in_events(y):
                    n = len(self.filtered_events())
                    self.events_scroll = max(0, min(n, self.events_scroll - step * 3))
                else:
                    lv = self.last_view
                    cols = max(1, (lv["cells"] // 10) if lv else 5)
                    self.pan(step * cols)
            elif ev[0] == "click":
                _, button, x, y = ev
                action = self.button_at(x, y) if self.controls else None
                if action == "wifi":
                    self.show_wifi = not self.show_wifi
                    continue
                if action == "add":
                    self.show_bots = not self.show_bots
                    continue
                if action == "info":
                    self.show_info = not self.show_info
                    continue
                if action and action.startswith("add:"):
                    self.bot_action("add", action[4:])
                    self.show_bots = False
                    continue
                if action:
                    self.bot_action(action)
                    continue
                c = self.strip_col(x, y)
                if c is not None and self.last_view:
                    self.selected_t = self.last_view["start_t"] + c * self.last_view["bin_s"]
        return changed

    def _key(self, key, width):
        lv = self.last_view
        cols = max(1, (lv["cells"] // 10) if lv else 5)
        if self.controls and self.show_bots and key not in ("q", "Q", "ctrl-c"):
            # v0.0.41: the bot menu owns the keys while it is open, so the digits do
            # not reach the event filter. 1-6 = that persona, a = the next in the list.
            if key in BOT_MENU_KEYS:
                self.bot_action("add", BOT_MENU_KEYS[key])
                self.show_bots = False
            elif key == "a":
                self.bot_action("add")
                self.show_bots = False
            elif key in ("esc", "r", "x", "w"):
                self.show_bots = False
                if key == "r":
                    self.bot_action("remove")
                elif key == "x":
                    self.bot_action("clear")
                elif key == "w":
                    self.show_wifi = True
            return
        if key in ("q", "Q", "ctrl-c"):
            self.quit = True
        elif key == "p":
            self.paused = not self.paused
        elif key == "s":
            self.snapshot(width)
        elif key in ("f", "F", "end"):
            self.follow = True
            self.end_t = None
            self.events_scroll = 0
        elif key == "home":
            if lv:
                self.follow = False
                self.end_t = lv["cells"] * lv["bin_s"]
        elif key == "left":
            self.pan(-cols)
        elif key == "right":
            self.pan(cols)
        elif key in ("+", "="):
            self.zoom_to(self.zoom - 1)
        elif key in ("-", "_"):
            self.zoom_to(self.zoom + 1)
        elif key == "esc":
            self.selected_t = None
            self.show_wifi = False
            self.show_bots = False
            self.show_info = False
        elif self.controls and key == "a":
            self.show_bots = True
        elif self.controls and key == "i":
            self.show_info = not self.show_info
        elif self.controls and key == "r":
            self.bot_action("remove")
        elif self.controls and key == "x":
            self.bot_action("clear")
        elif self.controls and key == "w":
            self.show_wifi = not self.show_wifi
        elif key == "pgup":
            self.events_scroll += 10
        elif key == "pgdn":
            self.events_scroll = max(0, self.events_scroll - 10)
        elif key in FILTER_KEYS and len(key) == 1:
            tag = FILTER_TAGS[FILTER_KEYS.index(key)]
            if tag in self.hidden_tags:
                self.hidden_tags.discard(tag)
            else:
                self.hidden_tags.add(tag)
            self.events_scroll = 0


def filter_title(deck, n_shown, n_total):
    """'events  1 KILL 2 ROUND ...' with hidden tags in brackets, plus the scroll place."""
    bits = []
    for k, tag in zip(FILTER_KEYS, FILTER_TAGS):
        bits.append(f"{k} [{tag}]" if tag in deck.hidden_tags else f"{k} {tag}")
    text = "events  " + "  ".join(bits)
    if deck.events_scroll:
        text += f"   ↑{deck.events_scroll} of {n_total}"
    return text


# ── Plain text picture ────────────────────────────────────────────────────────
def render_plain(deck, n_events, width=100):
    status, age, harness = deck.status, deck.age, deck.harness
    now = deck.now
    lines = []
    view = harness_view(harness, now, deck.expected)
    alert = deck.alert_text()
    if alert:
        lines.append("!! " + alert)
    if status is None or age > STALE_AFTER:
        if view and view["mode"] == "live" and view["state"] == "restarting":
            lines.append("!! server restarting for the next harness scenario")
        else:
            lines.append("!! " + stale_text(status, age))
        if status is None:
            if view:
                lines.append("-" * width)
                lines.extend(harness_lines_plain(view))
            return "\n".join(lines)
    lines.append(header_text(status, age, deck))
    if view:
        lines.append("-" * width)
        lines.extend(harness_lines_plain(view))
    lines.append("-" * width)
    rows = seat_rows(status, deck.ping_hist)
    show_tape = any(r["tape"] != "-" for r in rows)   # v0.0.25: only when a screen sent a tape card
    tape_head = f"{'Tape':<12}" if show_tape else ""
    show_screen = any(r["screen"] != "-" for r in rows)   # v0.0.37: only when a screen sent a client_stats card
    screen_head = f"{'Screen':<14}" if show_screen else ""
    lines.append(f"{'Seat':<5}{'Name':<16}{'Class':<8}{'State':<11}{'Lives':<6}{'Crowns':>6} {'K/D':>8} {'Ping':>7} {'Trend':<9}{'Health':<8}{tape_head}{screen_head}{'Link':<26}{'In/s':>5} {'Q/drop':>7} {'Seen':>5}")
    for r in rows:
        tape_cell = f"{r['tape']:<12}" if show_tape else ""
        screen_cell = f"{r['screen']:<14}" if show_screen else ""
        lines.append(f"{r['seat']:<5}{r['name']:<16}{r['cls']:<8}{r['state']:<11}{r['lives']:<6}{r['crowns']:>6} {r['kd']:>8} {r['ping']:>7} "
                     f"{r['trend']:<9}{r['health']:<8}{tape_cell}{screen_cell}{r['link']:<26}{r['pps']:>5} {r['queue']:>7} {r['seen']:>5}")
    cells_w = max(10, width - LABEL_W - 7)
    strip = build_strip(status, deck.view(cells_w))
    deck.last_view = strip
    if strip:
        lines.append("-" * width)
        lines.append(strip["title"] + (("  ▶ live" if strip["live"] else "  ▶ end") if strip["following"] else ""))
        for label, _style, cells in strip["rows"]:
            lines.append(f"{label:<{LABEL_W}} " + "".join(ch for ch, _s, _b, _sel in cells))
        if strip["inspect"]:
            lines.append(f"{'':<{LABEL_W}} {strip['inspect']}")
        lines.append(f"{'':<{LABEL_W}} {strip['subtitle']}"[:width])
    cards = bot_cards(status, harness if view and view["mode"] == "live" else None)
    if cards:
        rows = bot_rows(cards, now)
        cols = bot_columns(rows)
        lines.append("-" * width)
        lines.append(bot_title(cards))
        lines.append("".join(f"{c[0]:<{12 if c[2] in ('state', 'name') else 9 if c[1] == 'left' else 6}}" for c in cols))
        for r in rows:
            lines.append("".join(f"{str(r[c[2]]):<{12 if c[2] in ('state', 'name') else 9 if c[1] == 'left' else 6}}" for c in cols))
    lines.append("-" * width)
    lines.extend(traffic_lines(status, deck.traffic_hist))
    lines.append("-" * width)
    events = deck.filtered_events() or list(status["events"])
    if deck.hidden_tags:
        lines.append(f"events without {' '.join(sorted(deck.hidden_tags))}")
    for ev in events[-n_events:]:
        lines.append(f"{ev['t']} {ev['msg']}")
    return "\n".join(lines)


# ── Colour picture (rich) ─────────────────────────────────────────────────────
def strip_text(strip, selected_style="reverse"):
    """The strip rows as one rich Text, and the number of lines it takes."""
    from rich.text import Text
    body = Text(no_wrap=True, overflow="crop")
    rows = strip["rows"]
    n_lines = len(rows)
    for i, (label, label_style, cells) in enumerate(rows):
        body.append(f"{label:<{LABEL_W}} ", style=label_style)
        for ch, fg, band, sel in cells:
            style = fg
            if band:
                style += f" on {BAND_BG}"
            if sel:
                style += " " + selected_style
            body.append(ch, style=style)
        if i == 0 and strip["following"]:
            body.append(" ▶", style="bold green")
        if i == len(rows) - 1 and strip["following"]:
            body.append(" live" if strip["live"] else " end", style="bold green" if strip["live"] else "bold cyan")
        if i < n_lines - 1:
            body.append("\n")
    if strip["inspect"]:
        body.append("\n")
        body.append(f"{'':<{LABEL_W}} ", style="dim")
        body.append(strip["inspect"], style="bold yellow")
        n_lines += 1
    return body, n_lines


def render_rich(deck, height, width):
    from rich.console import Group
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text

    status, age, harness = deck.status, deck.age, deck.harness
    now = deck.now
    parts = []
    used = 0      # lines taken so far: the height budget
    view = harness_view(harness, now, deck.expected)
    deck.strip_geom = None
    deck.events_geom = None

    def add(renderable, lines):
        nonlocal used
        parts.append(renderable)
        used += lines

    alert = deck.alert_text()
    if alert:
        add(Text(f" {alert} "[:width], style="bold white on red", no_wrap=True, overflow="crop"), 1)

    deck.button_geom = []
    if deck.controls:
        deck._panel_top = used
        panel, lines = server_panel(deck, width)
        add(panel, lines)
        if deck.show_bots:
            deck._menu_top = used
            panel, lines = bot_menu_panel(deck)
            add(panel, lines)
        if deck.show_wifi:
            panel, lines = wifi_panel()
            add(panel, lines)
        if deck.show_info:
            panel, lines = info_panel(deck)
            add(panel, lines)

    if status is None or age > STALE_AFTER:
        if view and view["mode"] == "live" and view["state"] == "restarting":
            add(Panel(Text("server restarting for the next harness scenario", style="bold black on yellow"),
                      border_style="yellow"), 3)
        else:
            add(Panel(Text(stale_text(status, age), style="bold white on red"), border_style="red"), 3)
        if status is None:
            if view:
                parts.append(harness_panel(view, width))
            return Group(*parts)

    m = status["match"]
    head_style = "bold green" if m["state"] == "PLAYING" else "bold cyan"
    if deck.paused:
        head_style = "bold black on yellow"
    add(Panel(Text(header_text(status, age, deck), no_wrap=True, overflow="ellipsis"), style=head_style,
              border_style="cyan"), 3)

    if view:
        panel, lines = harness_panel(view, width, count=True)
        add(panel, lines)

    rows = seat_rows(status, deck.ping_hist)
    show_trend = width >= 120 and any(r["trend"] for r in rows)   # needs history and a wide terminal
    show_tape = any(r["tape"] != "-" for r in rows)   # v0.0.25: only when a screen sent a tape card
    table = Table(expand=True, border_style="dim", header_style="bold")
    for col, just, key in SEAT_COLS:
        if key == "trend" and not show_trend:
            continue
        if key == "tape" and not show_tape:
            continue
        table.add_column(col, justify=just, no_wrap=True)
    for r in rows:
        cells = [r["seat"], r["name"], r["cls"], Text(r["state"], style=r["colour"]),
                 Text(r["lives"], style="red"), r["crowns"], r["kd"], r["ping"],
                 Text(r["trend"], style="cyan"),
                 Text(r["health"], style=HEALTH_STYLE.get(r["health"], "white")),
                 Text(r["tape"], style="bright_magenta" if r["tape"].startswith("■") else "magenta"),
                 r["link"], r["pps"], r["queue"], r["seen"]]
        if not show_tape:
            del cells[10]
        if not show_trend:
            del cells[8]
        table.add_row(*cells)
    add(table, 4 + len(status["seats"]))

    cells_w = max(10, width - LABEL_W - 11)
    strip = build_strip(status, deck.view(cells_w))
    deck.last_view = strip
    if strip:
        body, n_lines = strip_text(strip)
        # the strip's place on the screen, so the mouse can find a column:
        # panel border (1) + padding (1) + label (LABEL_W + 1) -> first cell, 1-based
        deck.strip_geom = (used + 2, used + 1 + len(strip["rows"]), LABEL_W + 4, strip["cells"],
                           strip["start_t"], strip["bin_s"])
        add(Panel(body, title=strip["title"], subtitle=strip["subtitle"][:max(0, width - 6)],
                  title_align="left", subtitle_align="right", border_style="red"), n_lines + 2)

    cards = bot_cards(status, harness if view and view["mode"] == "live" else None)
    if cards:
        rows = bot_rows(cards, now)
        cols = bot_columns(rows)
        bt = Table(expand=True, border_style="dim", header_style="bold", padding=(0, 1),
                   title=bot_title(cards), title_justify="left", title_style="bold magenta")
        for col, just, key in cols:
            # Fits the terminal width; only the learning chips fold when the terminal is narrow.
            if key == "learn":
                bt.add_column(col, justify=just, no_wrap=False, overflow="fold", max_width=36)
            else:
                bt.add_column(col, justify=just, no_wrap=True)
        for r in rows:
            bt.add_row(*[Text(str(r[key]), style="cyan" if key in ("state", "learn") and r[key] != "-" else "white")
                         for _c, _j, key in cols])
        # A folded learning column adds lines: count them so the budget stays right.
        folded = sum(max(0, -(-len(r["learn"]) // 36) - 1) for r in rows)
        add(bt, 5 + len(rows) + folded)

    # Optional panels: traffic, then the events feed take what is left. Nothing
    # above them is ever cropped (v0.0.24 height budget).
    tl = traffic_lines(status, deck.traffic_hist)
    if used + len(tl) + 2 <= height:
        add(Panel(Text("\n".join(tl), no_wrap=True, overflow="crop"), title="traffic (last second, 60 s curve)",
                  title_align="left", border_style="dim"), len(tl) + 2)

    n_events = height - used - 2
    if n_events >= 1:
        events_all = deck.filtered_events() or [e for e in status["events"] if e.get("tag") not in deck.hidden_tags]
        deck.events_scroll = max(0, min(deck.events_scroll, max(0, len(events_all) - n_events)))
        end = len(events_all) - deck.events_scroll
        events = events_all[max(0, end - n_events):end]
        feed = Text(no_wrap=True, overflow="ellipsis")
        for i, ev in enumerate(events):
            style = TAG_STYLE.get(ev["tag"], "white")
            if ev["level"] in ("WARNING", "ERROR"):
                style = "bold yellow" if ev["level"] == "WARNING" else "bold red"
            feed.append(f"{ev['t']} ", style="dim")
            feed.append(ev["msg"], style=style)
            if i < len(events) - 1:
                feed.append("\n")
        title = Text(filter_title(deck, len(events), len(events_all)))
        keys = "← → pan  + - zoom  Home  End/f live  click inspect  Esc  0-9 filter  p pause  s snapshot  q quit"
        deck.events_geom = (used + 1, height)
        parts.append(Panel(feed if events else Text("no events yet", style="dim"),
                           title=title, title_align="left", subtitle=keys[:max(0, width - 6)],
                           subtitle_align="right", border_style="dim"))
    return Group(*parts)


BUTTONS = (("+ bot", "add"), ("- bot", "remove"), ("clear bots", "clear"), ("wifi help", "wifi"), ("info", "info"))
GITHUB_URL = "https://github.com/nemr118/tower_brawl"

WIFI_HELP = (
    "Plug in a cable if you can. It is faster and needs no setup. Otherwise, in a shell (q leaves the deck):",
    "  nmcli device wifi list                                     see the networks around you",
    "  sudo nmcli device wifi connect \"NAME\" password \"PASS\"     join one (it is remembered)",
    "  nmcli device                                               check: wlan0 should say connected",
    "  tbdash                                                     come back to the deck",
    "The play link uses the address at the top of this panel. It changes on a new network.",
)


def server_panel(deck, width):
    """The SERVER panel (--controls): play links, the bots, clickable buttons.
    Returns (panel, height) and records where the buttons landed for the mouse."""
    from rich.panel import Panel
    from rich.text import Text
    ip = deck.lan_ip()
    body = Text(no_wrap=True, overflow="crop")
    if ip:
        body.append("Play on phones: ", style="bold")
        body.append(f"https://{ip}:8443/play", style="bold green")
        body.append("    PC: ", style="bold")
        body.append(f"http://{ip}:8000", style="green")
    else:
        body.append("no network: plug in the cable or press w for the wifi commands", style="bold red")
    body.append("\n")
    # buttons: the row below the links. Border (1) + padding (1) puts the first cell at x=3.
    y = deck._panel_top + 2
    x = 3
    for i, (label, action) in enumerate(BUTTONS):
        chip = f" {label} "
        body.append(chip, style={"wifi": "bold black on yellow", "info": "bold black on white"}.get(action, "bold black on cyan"))
        deck.button_geom.append((y, x, x + len(chip) - 1, action))
        x += len(chip)
        body.append("  ")
        x += 2
    bots = deck.status.get("bots", 0) if deck.status else 0
    body.append(f"bots: {bots}", style="magenta")
    body.append("   keys: a bot menu  r remove  x clear  w wifi  i info", style="dim")
    return Panel(body, title="server", title_align="left", border_style="green"), 4


# v0.0.41: the bot menu. Opened with a or the + bot button; a key or a click adds that persona.
BOT_MENU = (("1", "wanderer", "roams, random class"), ("2", "chaser", "knight, runs at the nearest fighter"),
            ("3", "sniper", "mage, keeps its distance and shoots"), ("4", "turtle", "knight, shields and counters"),
            ("5", "rusher", "rogue, dashes in for melee bursts"), ("6", "griefer", "druid, harasses: dashes into shots, air shield"))
BOT_MENU_KEYS = {k: persona for k, persona, _ in BOT_MENU}


def bot_menu_panel(deck):
    """The persona menu (--controls, key a): one chip per persona, clickable, with its key.
    Returns (panel, height) and records the chips for the mouse."""
    from rich.panel import Panel
    from rich.text import Text
    body = Text(no_wrap=True, overflow="crop")
    body.append("Add a bot: press its number or click it.  a = the next persona in the list.  Esc closes.", style="bold")
    body.append("\n")
    y = deck._menu_top + 2
    x = 3
    for key, persona, _ in BOT_MENU:
        chip = f" {key} {persona} "
        body.append(chip, style="bold black on cyan")
        deck.button_geom.append((y, x, x + len(chip) - 1, f"add:{persona}"))
        x += len(chip)
        body.append("  ")
        x += 2
    body.append("\n")
    body.append("   ".join(f"{persona}: {what}" for _, persona, what in BOT_MENU), style="dim")
    seats = (deck.status or {}).get("seats") or []
    bots = [f"P{st['id']} {st.get('name') or '-'} ({(st.get('bot') or {}).get('persona', '?')})"
            for st in seats if st.get("bot")]
    body.append("\n")
    body.append("in the game: " + (", ".join(bots) if bots else "no bots yet") + "   (max 4)", style="magenta")
    return Panel(body, title="bots (a or Esc closes this)", title_align="left", border_style="cyan"), 6


def info_panel(deck):
    """v0.0.41: the about panel (key i): what this is and where the code lives."""
    from rich.panel import Panel
    from rich.text import Text
    version = (deck.status or {}).get("version") or "?"
    body = Text(no_wrap=True, overflow="crop")
    body.append("TOWER BRAWL  ", style="bold")
    body.append(f"{version}  ", style="bold green")
    body.append("a 4-player LAN brawler: a Godot 4.7 web client and a Python WebSocket relay. Phones and PCs play in a browser.\n")
    body.append("The code:  ", style="bold")
    body.append(GITHUB_URL, style="bold cyan underline")
    body.append("   (public)\n")
    body.append("The docs/ folder is the project notebook: patch notes per build, playtest sheets, the deck, the tape and the replay.\n", style="dim")
    body.append("Built with Claude Code. This screen is the server's deck (tools/watch_server.py); the game server is serve_game.py; "
                "the bots are headless Godot clients (tools/tbbot.py).", style="dim")
    return Panel(body, title="about (i or Esc closes this)", title_align="left", border_style="white"), 6


def wifi_panel():
    from rich.panel import Panel
    from rich.text import Text
    body = Text("\n".join(WIFI_HELP), no_wrap=True, overflow="ellipsis")
    return Panel(body, title="wifi (w or Esc closes this)", title_align="left", border_style="yellow"), len(WIFI_HELP) + 2


def harness_panel(view, width, count=False):
    """The harness deck as a rich Panel. With count=True also returns its height."""
    from rich.panel import Panel
    from rich.text import Text

    if view["mode"] == "summary":
        panel = Panel(Text(view["text"], style=view["style"]), title="harness", title_align="left",
                      border_style=view["style"].replace("bold ", ""))
        return (panel, 3) if count else panel

    body = Text(no_wrap=True, overflow="crop")
    bar_w = max(min(width - 70, 40), 10)
    body.append(f"{view['title']}  ", style="bold")
    body.append(progress_bar(view["progress"], bar_w), style="green" if view["state"] == "running" else "yellow")
    body.append(f" {view['progress'] * 100:3.0f}%  {fmt_uptime(view['elapsed'])}", style="bold")
    if view["eta"]:
        body.append(f"  {view['eta']}", style="cyan")
    if view["soak"]:
        body.append(f"   {view['soak']}", style="cyan")
    lines = 1
    if view["desc"]:
        body.append("\ntests: ", style="dim")
        body.append(view["desc"][:width - 12])
        lines += 1
    if view["step"]:
        body.append("\nstep:  ", style="dim")
        body.append(view["step"][:width - 12], style="cyan")
        lines += 1
    # The checklist: one chip per scenario, wrapped by hand so the height is known.
    chips = []
    for name, result, elapsed, slow in view["checklist"]:
        if result == "RUNNING":
            chips.append((f"● {name} {elapsed:.0f}s" + (" SLOW" if slow else ""), "bold yellow" if slow else "bold cyan"))
        elif result == "WAITING":
            chips.append((f"○ {name}", "dim"))
        else:
            mark, style = RESULT_MARK[result]
            chips.append((f"{mark} {name}", style))
    body.append("\n")
    lines += 1
    col = 0
    for i, (txt, style) in enumerate(chips):
        if col + len(txt) + 2 > width - 4 and col > 0:
            body.append("\n")
            lines += 1
            col = 0
        body.append(txt, style=style)
        body.append("  ")
        col += len(txt) + 2
    s = view["suite"]
    body.append("\n")
    lines += 1
    body.append(f"passed {s.get('passed', 0)}  ", style="green")
    body.append(f"minor {s.get('minor', 0)}  ", style="yellow" if s.get("minor") else "dim")
    body.append(f"failed {s.get('failed', 0)}", style="bold red" if s.get("failed") else "dim")
    if view["findings"]:
        body.append("   ✖ " + "  ".join(f"{k} ×{v['count']}" for k, v in view["findings"].items()), style="bold red")
    if view["warnings"]:
        body.append("   ▲ " + "  ".join(f"{k} ×{v['count']}" for k, v in view["warnings"].items()), style="yellow")
    border = "red" if s.get("failed") or view["findings"] else ("yellow" if view["state"] == "restarting" or view["slow"] else "green")
    panel = Panel(body, title="harness", title_align="left", border_style=border)
    return (panel, lines + 2) if count else panel


# ── Main loop ─────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Live operations deck for the Tower Brawl server (reads status.json and harness_state.json).")
    ap.add_argument("--file", default=STATUS_FILE, help="status file to read (default: status.json in the repo)")
    ap.add_argument("--harness-file", default=HARNESS_FILE, help="harness state file (default: harness_state.json in the repo)")
    ap.add_argument("--interval", type=float, default=1.0, help="seconds between redraws (default 1)")
    ap.add_argument("--events", type=int, default=15, help="event lines to show in plain mode (default 15)")
    ap.add_argument("--zoom", type=float, default=1.0, help="seconds per strip column to start with (0.5, 1, 2, 5, 10, 30)")
    ap.add_argument("--plain", action="store_true", help="plain text, no colours, no keys")
    ap.add_argument("--once", action="store_true", help="print one picture and exit")
    ap.add_argument("--no-mouse", action="store_true", help="keyboard only, no mouse reporting")
    ap.add_argument("--no-controls", dest="controls", action="store_false",
                    help="hide the SERVER panel (on by default since v0.0.41; the laptop and the PC show the same deck)")
    ap.add_argument("--controls", action="store_true", default=True,
                    help="show the SERVER panel (the default since v0.0.41; kept so old aliases and the laptop's console still work)")
    args = ap.parse_args()

    use_rich = not args.plain
    if use_rich:
        try:
            import rich  # noqa: F401
        except ImportError:
            print("rich is not installed in this Python; falling back to plain text "
                  "(./venv/bin/pip install rich)", file=sys.stderr)
            use_rich = False

    zoom = min(range(len(ZOOM_LADDER)), key=lambda i: abs(ZOOM_LADDER[i] - args.zoom))
    deck = Deck(args.file, args.harness_file, zoom=zoom)
    deck.controls = args.controls   # default True; --no-controls turns the panel off

    if args.once or not use_rich:
        size = shutil.get_terminal_size((100, 40))
        width = max(size.columns, 80)
        while True:
            deck.tick()
            if use_rich:
                from rich.console import Console
                console = Console(width=size.columns, height=size.lines)
                console.print(render_rich(deck, size.lines, size.columns))
            else:
                print(render_plain(deck, args.events, width=width))
            if args.once:
                return 0 if deck.status is not None and deck.age <= STALE_AFTER else 1
            print()
            time.sleep(args.interval)

    from rich.console import Console
    from rich.live import Live
    console = Console()
    reader = InputReader(mouse=not args.no_mouse).start()
    try:
        with Live(console=console, refresh_per_second=8, screen=True, auto_refresh=False) as live:
            next_draw = 0.0
            while not deck.quit:
                events = reader.poll()
                deck.tick()
                if events:
                    deck.handle(events, console.width)
                if events or time.time() >= next_draw:
                    live.update(render_rich(deck, console.height, console.width), refresh=True)
                    next_draw = time.time() + args.interval
                time.sleep(0.03)
    finally:
        reader.stop()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
