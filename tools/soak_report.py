#!/usr/bin/env python3
"""
Soak report (v0.1.5): is a long bot run still fighting, or has it stalled?

    ./venv/bin/python tools/soak_report.py --from 23:08                                  # this PC
    ./venv/bin/python tools/soak_report.py --dir playtest_logs/<folder> --from 23:08     # a pulled laptop night

It reads the match, round and kill records in client_stats.jsonl from the start
clock on, and each bot's console in .bots/ (bots/ in a pulled folder):
  - rounds: how many ended, the median and the longest, how many ran over
    STALL_S, and a round still open with its age (a stall shows up here first);
  - kills: per minute, and the longest gap without one;
  - per bot: the nav fields of its last status line (steps, misses, stucks,
    hunt), its "hunt on" and "stuck" line counts, and script errors.
A start clock later than now means the run began yesterday. Exit code 1 when a
round ran (or is still running) longer than STALL_S.
"""
import argparse
import datetime
import glob
import json
import os
import re
import statistics
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STALL_S = 300.0   # a round longer than this is a stall (bot rounds run 13-53 s, human ones 23-99 s)


def main():
    ap = argparse.ArgumentParser(description="round lengths, kill gaps and bot nav stats for a soak")
    ap.add_argument("--dir", help="a pulled folder (client_stats.jsonl + bots/); default: this project")
    ap.add_argument("--from", dest="t_from", required=True, help="start clock, HH:MM or HH:MM:SS")
    ap.add_argument("--date", help="YYYY-MM-DD of the start clock (default: today, or yesterday if the clock is later than now)")
    args = ap.parse_args()
    stats = os.path.join(args.dir, "client_stats.jsonl") if args.dir else os.path.join(ROOT, "client_stats.jsonl")
    bots = os.path.join(args.dir, "bots") if args.dir else os.path.join(ROOT, ".bots")

    now = time.time()
    clock = args.t_from if args.t_from.count(":") == 2 else args.t_from + ":00"
    day = datetime.date.fromisoformat(args.date) if args.date else datetime.date.today()
    t0 = datetime.datetime.fromisoformat(f"{day.isoformat()}T{clock}").timestamp()
    if not args.date and t0 > now:
        t0 -= 86400.0
    # a pulled folder ends when it was pulled (status.json is written once a second), not now
    end = now
    if args.dir:
        end = os.path.getmtime(stats)
        try:
            end = float(json.load(open(os.path.join(args.dir, "status.json")))["written_at"])
        except (OSError, ValueError, KeyError):
            pass
    hms = lambda t: datetime.datetime.fromtimestamp(t).strftime("%H:%M:%S")

    rows = []
    for line in open(stats, errors="replace"):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("t", 0.0) >= t0:
            rows.append(r)
    print(f"window {hms(t0)} to {hms(end)} = {(end - t0) / 3600:.2f} h, {len(rows)} records")

    ends = [r for r in rows if r.get("kind") == "match" and r.get("event") == "end"]
    reasons = {}
    for m in ends:
        reasons[m.get("reason")] = reasons.get(m.get("reason"), 0) + 1
    started = sum(1 for r in rows if r.get("kind") == "match" and r.get("event") == "start")
    print(f"matches: {started} started, {len(ends)} ended" + ("".join(f", {n} x {why}" for why, n in reasons.items())))

    # A match start is round 1's start (the server writes no round start for it);
    # a match end closes whatever round was open.
    starts, lengths, open_round, longest_at = {}, [], None, None
    for r in rows:
        if r.get("kind") == "match":
            starts = {1: r["t"]} if r.get("event") == "start" else {}
            open_round = (1, r["t"]) if r.get("event") == "start" else None
            continue
        if r.get("kind") != "round":
            continue
        if r.get("event") == "start":
            starts[r.get("round")] = r["t"]
            open_round = (r.get("round"), r["t"])
        elif r.get("event") == "over" and r.get("round") in starts:
            dur = r["t"] - starts.pop(r.get("round"))
            if not lengths or dur > max(lengths):
                longest_at = r["t"] - dur
            lengths.append(dur)
            open_round = None
    stalled = False
    if lengths:
        over = sum(1 for x in lengths if x > STALL_S)
        stalled = over > 0
        print(f"rounds: {len(lengths)} ended, median {statistics.median(lengths):.0f} s, longest {max(lengths):.0f} s "
              f"(started {hms(longest_at)}), over {STALL_S:.0f} s: {over}")
    if open_round:
        age = end - open_round[1]
        stalled = stalled or age > STALL_S
        print(f"round {open_round[0]} still open: {age:.0f} s (started {hms(open_round[1])})")

    kills = sorted(r["t"] for r in rows if r.get("kind") == "kill")
    marks = [t0] + kills + [end]
    gaps = [b - a for a, b in zip(marks, marks[1:])]
    print(f"kills: {len(kills)}, {len(kills) / max((end - t0) / 60.0, 0.01):.1f} a minute, "
          f"longest gap without one {max(gaps):.0f} s, gaps over 60 s: {sum(1 for g in gaps if g > 60.0)}")

    for path in sorted(glob.glob(os.path.join(bots, "bot*.log"))):
        text = open(path, errors="replace").read()
        status = [l for l in text.splitlines() if "🧠 [Bot " in l]
        who = re.search(r"\[Bot (\w+) P(\d) (\d+)s\]", status[-1]) if status else None
        nav = re.search(r"nav surf=(\S+) steps=(\d+) misses=(\d+) stucks=(\d+) hunt=(\d)", status[-1]) if status else None
        stuck = [l for l in text.splitlines() if "[BotNav]" in l and " stuck " in l]
        errors = len(re.findall(r"^SCRIPT ERROR|^ERROR:", text, re.M))
        name = f"{who.group(1)} P{who.group(2)}, up {int(who.group(3)) / 3600:.1f} h" if who else os.path.basename(path)
        navs = f"steps {nav.group(2)}, misses {nav.group(3)}, stucks {nav.group(4)}" if nav else "no nav fields (older than v0.1.5?)"
        print(f"  {name}: {navs}, hunt-on lines {text.count('hunt on:')}, stuck lines {len(stuck)}, errors {errors}")
    print("STALL: a round ran over %d s" % STALL_S if stalled else "no stall")
    return 1 if stalled else 0


if __name__ == "__main__":
    sys.exit(main())
