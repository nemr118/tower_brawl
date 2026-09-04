#!/usr/bin/env python3
"""
Tower Brawl live operations deck (v0.0.21 dashboard, grown in v0.0.22).

    ./venv/bin/python tools/watch_server.py             # live view, redraws every second
    ./venv/bin/python tools/watch_server.py --plain     # no colours, one text block per second
    ./venv/bin/python tools/watch_server.py --once      # print one picture and exit
    ./venv/bin/python tools/watch_server.py --events 25 # show more event lines (plain mode)

The story: to watch a match from the terminal you had to read raw log lines.
Now serve_game.py writes a small file, status.json, once a second, and the test
harness (tools/chaos_bots.py) writes harness_state.json while it runs. This
tool only reads those two files and draws them. It never talks to the server.

The picture is a stack of panels. A panel that has nothing to show is not drawn:
  HEADER     match state, players, bots, spectators, uptime
  HARNESS    only while a harness run is alive: scenario, progress bar, checklist
  SEATS      one row per seat: lives, crowns, kills/deaths, ping, health, link
  FIGHT      only when the match has kills: a kill timeline with round marks
  BOT ARENA  only when bots are in the match: persona, state, actions, learning
  TRAFFIC    packets and bytes per second, in and out
  EVENTS     the last tagged server log lines

Colours come from the `rich` library (installed in the venv). Without it, or
with --plain, the same picture is printed as plain text.
"""
import argparse
import json
import os
import shutil
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATUS_FILE = os.path.join(ROOT, "status.json")
HARNESS_FILE = os.path.join(ROOT, "harness_state.json")
STALE_AFTER = 3.0      # seconds without a fresh status write = the server is probably down
HARNESS_STALE = 5.0    # seconds without a harness heartbeat = the run stopped answering
HARNESS_KEEP = 600.0   # a finished run stays as one summary line this long
TIMELINE_BIN_S = 5.0   # one timeline column = this many seconds
SPARK = " ▁▂▃▄▅▆▇█"    # kill counts per column, low to high

# One colour per tag. The same names the server puts at the start of its lines.
TAG_STYLE = {
    "JOIN": "green", "LEAVE": "yellow", "CONN": "dim", "NAME": "magenta", "LOCK": "blue",
    "MATCH": "bold cyan", "ROUND": "cyan", "KILL": "red", "NET": "yellow",
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


def fmt_uptime(seconds):
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h {m:02d}m"
    if m:
        return f"{m}m {s:02d}s"
    return f"{s}s"


def dash(value, fmt="{}"):
    """A value as text, or '-' when it is missing."""
    if value is None or value == "":
        return "-"
    try:
        return fmt.format(value)
    except (ValueError, TypeError):
        return str(value)


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


def seat_rows(status):
    """The seat table as plain values: one dict per seat."""
    rows = []
    for seat in status["seats"]:
        state, colour = seat_state(seat, status["match"]["state"])
        playing = status["match"]["state"] == "PLAYING" and seat["playing"]
        bot = seat.get("bot")
        name = seat["name"] or "-"
        if bot:
            name += " 🤖"
        rows.append({
            "seat": f"P{seat['id']}", "name": name,
            "cls": seat["class_name"] or "-", "state": state, "colour": colour,
            "lives": "♥" * seat["stocks"] if playing else "-",
            "crowns": str(seat["crowns"]) if seat["crowns"] else "-",
            "kd": kd_text(seat),
            "ping": dash(seat.get("rtt_ms"), "{} ms") if seat["connected"] else "-",
            "health": seat_health(seat),
            "link": f"{seat['transport']} {seat['ip']}" if seat["connected"] else "-",
            "pps": f"{seat['in_pps']:.0f}" if seat["connected"] else "-",
            "queue": f"{seat['queue']}/{seat['dropped']}" if seat["connected"] else "-",
            "seen": f"{seat['seen_s']:.0f}s" if seat["seen_s"] is not None else "-",
        })
    return rows


SEAT_COLS = (("Seat", "left", "seat"), ("Name", "left", "name"), ("Class", "left", "cls"),
             ("State", "left", "state"), ("Lives", "left", "lives"), ("Crowns", "right", "crowns"),
             ("K/D", "right", "kd"), ("Ping", "right", "ping"), ("Health", "left", "health"),
             ("Link", "left", "link"), ("In/s", "right", "pps"), ("Q/drop", "right", "queue"),
             ("Seen", "right", "seen"))


# ── Header and traffic ────────────────────────────────────────────────────────
def header_text(status, age):
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
    parts.append(f"up {fmt_uptime(status['uptime_s'])}")
    parts.append(f"{age:.1f}s ago")
    return " | ".join(parts)


def traffic_lines(status):
    """Two tidy lines: what comes in, what goes out."""
    t = status["traffic"]
    top = "   ".join(f"{k} {v:g}/s" for k, v in sorted(t["in_types_s"].items(), key=lambda kv: -kv[1])[:5])
    queued = sum(s.get("queue", 0) for s in status["seats"])
    line_in = f"IN  {t['in_pps']:7.1f} pkt/s {t['in_kbps']:7.2f} KB/s     {top or '-'}"
    line_out = (f"OUT {t['out_pps']:7.1f} pkt/s {t['out_kbps']:7.2f} KB/s     "
                f"fail {t['fail_s']:g}/s   drop {t['drop_s']:g}/s   queued {queued}   threads {status['threads']}")
    return [line_in, line_out]


def stale_text(status, age):
    if status is None:
        return f"no {os.path.basename(STATUS_FILE)} yet. Is the server running?  systemctl --user status towerbrawl"
    return f"no fresh status for {age:.0f} s. Is the server running?  systemctl --user status towerbrawl"


# ── Fight timeline ────────────────────────────────────────────────────────────
def timeline_cells(status, width):
    """The kill timeline as columns. Returns (cells, seats) or (None, None) when
    there is nothing to draw. Each cell is a dict: {"sep": round number} for a
    round line, or {"bin": i, "kills": {pid: n}, "deaths": {pid: n}, "total": n,
    "round_start": n or None}."""
    tl = status["match"].get("timeline") or {}
    kills = tl.get("kills") or []
    rounds = tl.get("rounds") or []
    started = tl.get("started_at")
    if not kills or not started:
        return None, None
    now_t = 0.0
    if status["match"]["state"] == "PLAYING":
        now_t = status["written_at"] - started
    last_t = max([k[0] for k in kills] + [r[1] for r in rounds] + [now_t])
    n_bins = int(last_t // TIMELINE_BIN_S) + 1
    bins = [{"bin": i, "kills": {}, "deaths": {}, "total": 0, "round_start": None} for i in range(n_bins)]
    for t, killer, victim, _weapon, _rnd in kills:
        b = bins[min(int(t // TIMELINE_BIN_S), n_bins - 1)]
        b["total"] += 1
        b["deaths"][victim] = b["deaths"].get(victim, 0) + 1
        if killer and killer != victim:
            b["kills"][killer] = b["kills"].get(killer, 0) + 1
    seps = {}
    for rnd, t0, _winner in rounds:
        i = min(int(t0 // TIMELINE_BIN_S), n_bins - 1)
        if bins[i]["round_start"] is None:
            bins[i]["round_start"] = rnd
        if rnd > 1:
            seps[i] = rnd
    cells = []
    for b in bins:
        if b["bin"] in seps:
            cells.append({"sep": seps[b["bin"]]})
        cells.append(b)
    if width > 0 and len(cells) > width:
        cells = cells[-width:]
    seats = sorted({pid for k in kills for pid in (k[1], k[2]) if 1 <= pid <= 4})
    return cells, seats


def timeline_rows(status, width):
    """Text rows of the timeline: [(label, [(char, style), ...]), ...]."""
    cells, seats = timeline_cells(status, width)
    if cells is None:
        return []
    names = {s["id"]: (s["name"] or f"P{s['id']}") for s in status["seats"]}
    peak = max((c.get("total", 0) for c in cells), default=1) or 1
    rows = []
    spark = []
    for c in cells:
        if "sep" in c:
            spark.append(("┃", "bold white"))
        else:
            level = 0 if c["total"] == 0 else max(1, round(c["total"] / peak * (len(SPARK) - 1)))
            spark.append((SPARK[level], "red" if c["total"] else "dim"))
    rows.append(("kills/5s", spark))
    for pid in seats:
        lane = []
        for c in cells:
            if "sep" in c:
                lane.append(("┃", "bold white"))
                continue
            k, d = c["kills"].get(pid, 0), c["deaths"].get(pid, 0)
            if k and d:
                lane.append(("◈", "magenta"))
            elif k:
                lane.append(("◆", "green"))
            elif d:
                lane.append(("✕", "red"))
            else:
                lane.append(("·", "dim"))
        label = f"P{pid} {names.get(pid, '')}"[:11]
        rows.append((label, lane))
    marks = []
    i = 0
    while i < len(cells):
        c = cells[i]
        if "sep" in c:
            marks.append(("┃", "bold white"))
            i += 1
            continue
        if c["round_start"] is not None:
            label = f"R{c['round_start']}"
            # The round label sits on the first cells of its round, one letter per cell.
            for ch in label:
                if i < len(cells) and "sep" not in cells[i]:
                    marks.append((ch, "cyan"))
                    i += 1
            continue
        marks.append(("─", "dim"))
        i += 1
    rows.append(("round", marks))
    return rows


def fight_title(status):
    tl = status["match"].get("timeline") or {}
    kills = tl.get("kills") or []
    rounds = tl.get("rounds") or []
    live = status["match"]["state"] == "PLAYING"
    where = f"round {rounds[-1][0]}" if rounds else ""
    return f"FIGHT  {len(kills)} kill{'s' if len(kills) != 1 else ''}  {where}" + ("" if live else "  (last match)")


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
    """All bot cards by seat, brains only (protocol bots get a badge in the seat table)."""
    by_seat = {}
    for seat in status["seats"]:
        card = seat.get("bot")
        if card and card.get("kind") == "brain":
            by_seat[seat["id"]] = merge_cards(card, None)
    if harness:
        for card in harness.get("bots") or []:
            pid = card.get("seat")
            if pid is None:
                continue
            by_seat[pid] = merge_cards(by_seat.get(pid), card)
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


def bot_rows(cards):
    rows = []
    for c in cards:
        actions = c.get("actions") or {}
        nav = c.get("nav") or {}
        aim = c.get("aim") or {}
        combat = c.get("combat") or {}
        goal = c.get("goal")
        goal_txt = f"{goal[0]},{goal[1]}" if isinstance(goal, list) and len(goal) == 2 else "-"
        rows.append({
            "seat": f"P{c.get('seat', '?')}",
            "persona": dash(c.get("persona")),
            "diff": dash(c.get("difficulty"), "{:.2f}"),
            "state": dash(c.get("state")),
            "target": dash(c.get("target"), "P{}"),
            "goal": goal_txt,
            "acc": pct(combat.get("accuracy")),
            "air": pct(combat.get("air_time_pct")),
            "decisions": dash(actions.get("decisions")),
            "attacks": dash(actions.get("attacks")),
            "specials": dash(actions.get("specials")),
            "evades": dash(actions.get("evades")),
            "wraps": dash(nav.get("wraps")),
            "loop": dash(nav.get("max_loop")),
            "aim": dash(aim.get("err_mean_deg"), "{:.1f}°"),
            "learn": learn_text(c),
            "up": dash(c.get("uptime_s"), "{}s"),
        })
    return rows


BOT_COLS = (("Seat", "left", "seat"), ("Persona", "left", "persona"), ("Diff", "right", "diff"),
            ("State", "left", "state"), ("Target", "left", "target"),
            ("Acc", "right", "acc"), ("Air", "right", "air"), ("Decis", "right", "decisions"),
            ("Atk", "right", "attacks"), ("Spec", "right", "specials"), ("Evade", "right", "evades"),
            ("Wraps", "right", "wraps"), ("Loop", "right", "loop"), ("Aim", "right", "aim"),
            ("Up", "right", "up"), ("Learn Δ", "left", "learn"))


# ── Harness deck ──────────────────────────────────────────────────────────────
def harness_view(harness, now):
    """What to draw for the harness, or None. Returns a dict:
    {"mode": "live" | "summary", ...} with the pieces the renderers need."""
    if harness is None:
        return None
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
    for name in names:
        if name in done:
            checklist.append((name, done[name]["result"], done[name].get("elapsed_s")))
        elif sc and name == sc.get("name"):
            checklist.append((name, "RUNNING", sc.get("elapsed_s", 0.0)))
        else:
            checklist.append((name, "WAITING", None))
    soak = harness.get("soak")
    soak_txt = ""
    if soak:
        left = max(soak.get("deadline_at", now) - now, 0)
        soak_txt = f"soak pass {soak.get('pass_no', 0) + 1}, {fmt_uptime(left)} left"
    return {"mode": "live", "title": title, "progress": progress, "elapsed": elapsed,
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
             + (f"   {view['soak']}" if view["soak"] else "")]
    if view["desc"]:
        lines.append(f"tests: {view['desc']}")
    if view["step"]:
        lines.append(f"step:  {view['step']}")
    marks = {"PASS": "✔", "FAIL": "✖", "MINOR": "▲", "RUNNING": "●", "WAITING": "○"}
    items = []
    for name, result, elapsed in view["checklist"]:
        item = f"{marks[result]} {name}"
        if result == "RUNNING" and elapsed is not None:
            item += f" {elapsed:.0f}s"
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


# ── Plain text picture ────────────────────────────────────────────────────────
def render_plain(status, age, harness, n_events, width=100):
    now = time.time()
    lines = []
    view = harness_view(harness, now)
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
    lines.append(header_text(status, age))
    if view:
        lines.append("-" * width)
        lines.extend(harness_lines_plain(view))
    lines.append("-" * width)
    lines.append(f"{'Seat':<5}{'Name':<16}{'Class':<8}{'State':<11}{'Lives':<6}{'Crowns':>6} {'K/D':>8} {'Ping':>7} {'Health':<8}{'Link':<26}{'In/s':>5} {'Q/drop':>7} {'Seen':>5}")
    for r in seat_rows(status):
        lines.append(f"{r['seat']:<5}{r['name']:<16}{r['cls']:<8}{r['state']:<11}{r['lives']:<6}{r['crowns']:>6} {r['kd']:>8} {r['ping']:>7} "
                     f"{r['health']:<8}{r['link']:<26}{r['pps']:>5} {r['queue']:>7} {r['seen']:>5}")
    rows = timeline_rows(status, width - 13)
    if rows:
        lines.append("-" * width)
        lines.append(fight_title(status) + "   (◆ kill  ✕ death  ◈ both  ┃ new round)")
        for label, cells in rows:
            lines.append(f"{label:<11} " + "".join(ch for ch, _ in cells))
    cards = bot_cards(status, harness if view and view["mode"] == "live" else None)
    if cards:
        lines.append("-" * width)
        lines.append(f"BOT ARENA  {len(cards)} brain{'s' if len(cards) != 1 else ''}")
        head = "".join(f"{c[0]:<{9 if c[1] == 'left' else 7}}" for c in BOT_COLS)
        lines.append(head)
        for r in bot_rows(cards):
            lines.append("".join(f"{str(r[c[2]]):<{9 if c[1] == 'left' else 7}}" for c in BOT_COLS))
    lines.append("-" * width)
    lines.extend(traffic_lines(status))
    lines.append("-" * width)
    for ev in status["events"][-n_events:]:
        lines.append(f"{ev['t']} {ev['msg']}")
    return "\n".join(lines)


# ── Colour picture (rich) ─────────────────────────────────────────────────────
def render_rich(status, age, harness, height, width):
    from rich.console import Group
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text

    now = time.time()
    parts = []
    used = 0      # lines taken so far, so the events panel can take the rest
    view = harness_view(harness, now)

    def add(renderable, lines):
        nonlocal used
        parts.append(renderable)
        used += lines

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
    add(Panel(Text(header_text(status, age), style=head_style), border_style="cyan"), 3)

    if view:
        panel, lines = harness_panel(view, width, count=True)
        add(panel, lines)

    table = Table(expand=True, border_style="dim", header_style="bold")
    for col, just, _key in SEAT_COLS:
        table.add_column(col, justify=just, no_wrap=True)
    for r in seat_rows(status):
        table.add_row(r["seat"], r["name"], r["cls"], Text(r["state"], style=r["colour"]),
                      Text(r["lives"], style="red"), r["crowns"], r["kd"], r["ping"],
                      Text(r["health"], style=HEALTH_STYLE.get(r["health"], "white")),
                      r["link"], r["pps"], r["queue"], r["seen"])
    add(table, 4 + len(status["seats"]))

    rows = timeline_rows(status, width - 18)
    if rows:
        body = Text()
        for i, (label, cells) in enumerate(rows):
            body.append(f"{label:<11} ", style="bold" if label != "round" else "dim")
            for ch, style in cells:
                body.append(ch, style=style)
            if i < len(rows) - 1:
                body.append("\n")
        add(Panel(body, title=fight_title(status), subtitle="◆ kill  ✕ death  ◈ both  ┃ new round",
                  title_align="left", subtitle_align="right", border_style="red"), len(rows) + 2)

    cards = bot_cards(status, harness if view and view["mode"] == "live" else None)
    if cards:
        bt = Table(expand=False, border_style="dim", header_style="bold",
                   title=f"BOT ARENA  {len(cards)} brain{'s' if len(cards) != 1 else ''}", title_justify="left",
                   title_style="bold magenta")
        for col, just, key in BOT_COLS:
            # The numbers keep their width; only the learning chips fold when the terminal is narrow.
            if key == "learn":
                bt.add_column(col, justify=just, no_wrap=False, overflow="fold", max_width=36)
            else:
                bt.add_column(col, justify=just, no_wrap=True, min_width=len(col))
        for r in bot_rows(cards):
            bt.add_row(*[Text(str(r[key]), style="cyan" if key in ("state", "learn") and r[key] != "-" else "white")
                         for _c, _j, key in BOT_COLS])
        # A folded learning column adds lines: count them so the events panel still fits.
        folded = sum(max(0, -(-len(r["learn"]) // 36) - 1) for r in bot_rows(cards))
        add(bt, 5 + len(cards) + folded)

    tl = traffic_lines(status)
    add(Panel(Text(tl[0] + "\n" + tl[1], style="white"), title="traffic (last second)",
              title_align="left", border_style="dim"), 4)

    n_events = max(height - used - 2, 3)
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


def harness_panel(view, width, count=False):
    """The harness deck as a rich Panel. With count=True also returns its height."""
    from rich.panel import Panel
    from rich.text import Text

    if view["mode"] == "summary":
        panel = Panel(Text(view["text"], style=view["style"]), title="harness", title_align="left",
                      border_style=view["style"].replace("bold ", ""))
        return (panel, 3) if count else panel

    body = Text()
    bar_w = max(min(width - 60, 40), 10)
    body.append(f"{view['title']}  ", style="bold")
    body.append(progress_bar(view["progress"], bar_w), style="green" if view["state"] == "running" else "yellow")
    body.append(f" {view['progress'] * 100:3.0f}%  {fmt_uptime(view['elapsed'])}", style="bold")
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
    for name, result, elapsed in view["checklist"]:
        if result == "RUNNING":
            chips.append((f"● {name} {elapsed:.0f}s", "bold cyan"))
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
    border = "red" if s.get("failed") or view["findings"] else ("yellow" if view["state"] == "restarting" else "green")
    panel = Panel(body, title="harness", title_align="left", border_style=border)
    return (panel, lines + 2) if count else panel


# ── Main loop ─────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Live operations deck for the Tower Brawl server (reads status.json and harness_state.json).")
    ap.add_argument("--file", default=STATUS_FILE, help="status file to read (default: status.json in the repo)")
    ap.add_argument("--harness-file", default=HARNESS_FILE, help="harness state file (default: harness_state.json in the repo)")
    ap.add_argument("--interval", type=float, default=1.0, help="seconds between redraws (default 1)")
    ap.add_argument("--events", type=int, default=15, help="event lines to show in plain mode (default 15)")
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
        status = read_json(args.file)
        age = (time.time() - status["written_at"]) if status and "written_at" in status else 0.0
        harness = read_json(args.harness_file)
        return status, age, harness

    if args.once or not use_rich:
        width = shutil.get_terminal_size((100, 24)).columns
        while True:
            status, age, harness = picture()
            print(render_plain(status, age, harness, args.events, width=max(width, 80)))
            if args.once:
                return 0 if status is not None and age <= STALE_AFTER else 1
            print()
            time.sleep(args.interval)

    from rich.console import Console
    from rich.live import Live
    console = Console()
    with Live(console=console, refresh_per_second=4, screen=True) as live:
        while True:
            status, age, harness = picture()
            live.update(render_rich(status, age, harness, console.height, console.width))
            time.sleep(args.interval)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
