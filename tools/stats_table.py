#!/usr/bin/env python3
"""
Tower Brawl client stats table (v0.0.37).

Every client mails its NetStats numbers to the server every 5 s (a client_stats
card). The server appends each card, and a marker at every match and round start
and end, to client_stats.jsonl, one JSON object per line. This tool turns a time
window of that file into one row per device, the rows the playtest sheet asks for.

    ./venv/bin/python tools/stats_table.py                    # the last match, one row per device
    ./venv/bin/python tools/stats_table.py --list             # every match in the file: number, clock, rounds, players
    ./venv/bin/python tools/stats_table.py --match 3          # match number 3 from --list
    ./venv/bin/python tools/stats_table.py --last 2           # the last two matches, one table each
    ./venv/bin/python tools/stats_table.py --from 20:41 --to 20:52   # a window you wrote on the sheet (today's clock)
    ./venv/bin/python tools/stats_table.py --match 3 --by-round      # one table per round
    ./venv/bin/python tools/stats_table.py --match 3 --scene Arena   # only cards from the arena (drop lobby and load lines)
    ./venv/bin/python tools/stats_table.py --devices          # who reported: model, OS, screen rate, browser
    ./venv/bin/python tools/stats_table.py --raw --from 20:41 --to 20:42   # the cards themselves

A device is one socket's name plus its address. The first card after a scene
change carries the load spike; --skip-load drops it (default on).
"""
import argparse
import datetime as dt
import json
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATS_FILE = os.path.join(ROOT, "client_stats.jsonl")


def load(path):
    recs = []
    for fn in (path + ".1", path):
        if not os.path.exists(fn):
            continue
        with open(fn, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    recs.append(json.loads(line))
                except ValueError:
                    pass
    recs.sort(key=lambda r: r.get("t", 0))
    return recs


def matches(recs):
    """[(number, start_t, end_t or None, start_rec, end_rec, rounds)] from the markers."""
    out = []
    cur = None
    for r in recs:
        if r.get("kind") == "match" and r.get("event") == "start":
            if cur is not None:
                cur["end"] = r["t"]          # a start with no end: the old one ended silently
                out.append(cur)
            cur = {"start": r["t"], "end": None, "start_rec": r, "end_rec": None, "rounds": []}
        elif r.get("kind") == "round" and cur is not None:
            cur["rounds"].append(r)
        elif r.get("kind") == "match" and r.get("event") == "end" and cur is not None:
            cur["end"] = r["t"]
            cur["end_rec"] = r
            out.append(cur)
            cur = None
    if cur is not None:
        out.append(cur)
    for i, m in enumerate(out, 1):
        m["n"] = i
    return out


def clock(t):
    return dt.datetime.fromtimestamp(t).strftime("%H:%M:%S") if t else "-"


def parse_clock(text, date):
    parts = [int(x) for x in text.split(":")]
    while len(parts) < 3:
        parts.append(0)
    return dt.datetime.combine(date, dt.time(*parts)).timestamp()


def device_key(c):
    return f"{c.get('name', '?')} P{c.get('seat', 0)} {c.get('addr', '?').split(':')[0]}"


def device_line(c):
    d = c.get("dev") or {}
    ua = d.get("ua") or ""
    if ua:
        ua = ua.split(") ")[-1][:60]
    kind = "headless" if d.get("headless") else ("web" if d.get("web") else "native")
    return f"{d.get('model', '?')} · {d.get('os', '?')} · {d.get('hz', '?')} Hz · {kind} · {ua}".strip(" ·")


def mean(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else None


def fmt(v, digits=1):
    if v is None:
        return "-"
    return f"{v:.{digits}f}" if isinstance(v, float) else str(v)


COLS = ["Device", "cards", "draw", "phys", "worst", "hitches", "proc", "phys_cpu",
        "rtt", "IN pkt/s", "bundles/5s", "jitter", "p95", "snaps", "stall%", "extrap%", "keys", "focus"]


def rows_for(cards, skip_load=True):
    by_dev = defaultdict(list)
    last_scene = {}
    for c in cards:
        k = device_key(c)
        if skip_load and last_scene.get(k) != c.get("scene"):
            last_scene[k] = c.get("scene")
            continue          # the first card after a scene change is the load spike
        by_dev[k].append(c)
    rows = []
    for k, cs in sorted(by_dev.items()):
        fps = [c.get("fps", {}) for c in cs]
        pj = [c.get("pj", {}) for c in cs]
        rows.append([
            k, str(len(cs)),
            fmt(mean([f.get("draw") for f in fps])),
            fmt(mean([f.get("phys") for f in fps])),
            fmt(max((f.get("worst") or 0) for f in fps)),
            str(sum(int(f.get("hitches") or 0) for f in fps)),
            fmt(mean([f.get("proc") for f in fps]), 2) + "/" + fmt(max((f.get("proc") or 0) for f in fps), 2),
            fmt(mean([f.get("phys_cpu") for f in fps]), 2) + "/" + fmt(max((f.get("phys_cpu") or 0) for f in fps), 2),
            fmt(mean([c.get("rtt") for c in cs]), 0),
            fmt(mean([c.get("in_pps") for c in cs])),
            fmt(mean([c.get("bundles") for c in cs]), 0),
            fmt(mean([p.get("jit") for p in pj])),
            fmt(max((p.get("p95") or 0) for p in pj)),
            str(sum(int(p.get("snaps") or 0) for p in pj)),
            fmt(mean([p.get("stall") for p in pj])),
            fmt(mean([p.get("extrap") for p in pj])),
            str(sum(int(c.get("keys") or 0) for c in cs)),
            str(min(int(c.get("focus", 1)) for c in cs)),
        ])
    return rows


def table(rows, cols=COLS):
    if not rows:
        return "(no cards in this window)"
    w = [max(len(str(x)) for x in col) for col in zip(cols, *rows)]
    line = lambda r: "| " + " | ".join(str(x).ljust(w[i]) for i, x in enumerate(r)) + " |"
    return "\n".join([line(cols), "|" + "|".join("-" * (x + 2) for x in w) + "|"] + [line(r) for r in rows])


def in_window(recs, start, end):
    return [r for r in recs if r.get("kind") == "card" and start <= r.get("t", 0) <= (end or float("inf"))]


def print_window(recs, start, end, title, args):
    cards = in_window(recs, start, end)
    if args.scene:
        cards = [c for c in cards if c.get("scene") == args.scene]
    print(f"\n## {title} ({clock(start)} to {clock(end) if end else 'now'}, {len(cards)} cards)")
    if args.raw:
        for c in cards:
            print(json.dumps(c, separators=(",", ":")))
        return
    print(table(rows_for(cards, not args.keep_load)))
    print("proc and phys_cpu are mean/max over the cards, in ms. worst is the slowest frame. focus 0 = the canvas lost the page focus at least once.")
    seen = set()
    for c in cards:
        k = device_key(c)
        if k not in seen:
            seen.add(k)
            print(f"- {k}: {device_line(c)}")


def main():
    ap = argparse.ArgumentParser(description="One row per device from client_stats.jsonl (Tower Brawl v0.0.37).")
    ap.add_argument("--file", default=STATS_FILE)
    ap.add_argument("--list", action="store_true", help="list the matches in the file")
    ap.add_argument("--devices", action="store_true", help="list every device that reported, with its newest card time")
    ap.add_argument("--match", type=int, help="match number from --list")
    ap.add_argument("--last", type=int, default=1, help="the last N matches (default 1)")
    ap.add_argument("--from", dest="t_from", help="window start, HH:MM or HH:MM:SS, today's clock")
    ap.add_argument("--to", dest="t_to", help="window end (default: now)")
    ap.add_argument("--date", help="YYYY-MM-DD for --from/--to (default today)")
    ap.add_argument("--by-round", action="store_true", help="one table per round of the match")
    ap.add_argument("--scene", help="only cards from this scene (Arena, CharacterSelect, ...)")
    ap.add_argument("--keep-load", action="store_true", help="keep the first card after a scene change (the load spike)")
    ap.add_argument("--raw", action="store_true", help="print the cards instead of the table")
    args = ap.parse_args()

    recs = load(args.file)
    if not recs:
        print(f"no records in {args.file} (is the server on v0.0.37 or later, and has anyone connected?)")
        return 1
    ms = matches(recs)

    if args.list:
        print(f"{len(ms)} matches in {args.file} ({len(recs)} records, {clock(recs[0]['t'])} to {clock(recs[-1]['t'])})")
        for m in ms:
            names = (m["start_rec"].get("names") or {})
            who = ", ".join(f"P{p} {n}" for p, n in names.items())
            end = m.get("end_rec") or {}
            rounds = sum(1 for r in m["rounds"] if r.get("event") == "over")
            winner = f"P{end['winner']}" if end.get("winner") else "-"
            print(f"  match {m['n']}: {clock(m['start'])} to {clock(m['end'])}  rounds={rounds}  "
                  f"winner={winner}  ({end.get('reason', 'no end marker')})  {who}")
        return 0

    if args.devices:
        newest = {}
        for r in recs:
            if r.get("kind") == "card":
                newest[device_key(r)] = r
        for k, c in sorted(newest.items()):
            print(f"- {k}: {device_line(c)}  (last card {clock(c['t'])}, {c.get('v')}, scene {c.get('scene')})")
        return 0

    if args.t_from:
        date = dt.date.fromisoformat(args.date) if args.date else dt.date.today()
        start = parse_clock(args.t_from, date)
        end = parse_clock(args.t_to, date) if args.t_to else None
        print_window(recs, start, end, "window", args)
        return 0

    chosen = [m for m in ms if m["n"] == args.match] if args.match else ms[-args.last:]
    if not chosen:
        print("no such match; try --list")
        return 1
    for m in chosen:
        if args.by_round:
            starts = [r for r in m["rounds"] if r.get("event") == "start"]
            bounds = [(m["start"], 1)] + [(r["t"], r.get("round")) for r in starts]
            for i, (t0, rn) in enumerate(bounds):
                t1 = bounds[i + 1][0] if i + 1 < len(bounds) else m["end"]
                print_window(recs, t0, t1, f"match {m['n']} round {rn}", args)
        else:
            print_window(recs, m["start"], m["end"], f"match {m['n']}", args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
