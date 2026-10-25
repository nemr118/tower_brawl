#!/usr/bin/env python3
"""A night of the new game, read back from the server's log (v2_server.jsonl).

The server's health (its 5 s lines), the matches and rounds, the people, and since
p4.7 each phone's own report (the look, the frame rate in matches, the ping,
reconnects, step-downs, page errors, the shots it let go), then a list of what to
look at. Plain words, for finding bugs after a play night.

    ./venv/bin/python tools/v2_night_report.py --file <v2_server.jsonl> [--from "2026-10-25 17:00"] [--to "..."] [--stats <v2_stats.json>]
"""
import argparse
import json
import os
import re
import statistics
import sys
import time
from collections import Counter, defaultdict

CAUSES = {1: "arrow", 2: "blast", 3: "stomp", 4: "fire", 5: "poison", 6: "the walls", 7: "lightning", 8: "a ghost cat", 9: "spikes"}
BIG = {"GHOST CATS", "RAIN", "INVISIBLE", "FREEZE", "SPIKED SHIELD", "SUPER SPEED"}   # p4.9's BIG power-ups
ARENAS = {0: "THE BENCH", 1: "THE KEEP", 2: "THE BRIDGES", 3: "THE HAUNTED HOUSE"}


def when(t):
    return time.strftime("%H:%M", time.localtime(t))


def parse_time(s):
    if not s:
        return None
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S"):
        try:
            return time.mktime(time.strptime(s, fmt))
        except ValueError:
            pass
    sys.exit(f"cannot read the time {s!r} (use YYYY-MM-DD HH:MM)")


def model(ua):
    m = re.search(r"Android [\d.]+; ([^;)]+)", ua)
    if m:
        return m.group(1).strip()
    if "iPhone" in ua:
        return "iPhone"
    if "iPad" in ua or "Macintosh" in ua:
        return "iPad or Mac"
    if "Windows" in ua:
        return "Windows PC"
    if "Linux" in ua:
        return "Linux PC"
    return ua[:30] or "?"


def med(xs):
    return statistics.median(xs) if xs else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--file", required=True)
    ap.add_argument("--from", dest="t0", default="")
    ap.add_argument("--to", dest="t1", default="")
    ap.add_argument("--stats", default="", help="v2_stats.json (default: next to the log)")
    a = ap.parse_args()
    t0, t1 = parse_time(a.t0), parse_time(a.t1)
    lines = []
    with open(a.file, encoding="utf-8", errors="replace") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            t = d.get("t", 0)
            if (t0 and t < t0) or (t1 and t > t1):
                continue
            lines.append(d)
    if not lines:
        sys.exit("no lines in that window")
    by = defaultdict(list)
    for d in lines:
        by[d.get("kind", "?")].append(d)
    look_at = []
    print(f"The night in {os.path.basename(a.file)}: {when(lines[0]['t'])} to {when(lines[-1]['t'])} ({len(lines)} lines)")

    # the server
    print("\nTHE SERVER")
    for s in by["start"]:
        print(f"  {when(s['t'])} started {s.get('version')} ({s.get('bots')} bots {s.get('bot_level')}, arena {s.get('arena')}, host port {s.get('admin_port', 0)})")
    reps = by["report"]
    if reps:
        worst = max(reps, key=lambda r: r.get("tick_max_ms", 0))
        stalls = [r for r in reps if r.get("interval_max_ms", 0) > 100]
        print(f"  {len(reps)} five-second lines; the worst tick {worst['tick_max_ms']:.1f} ms at {when(worst['t'])}; "
              f"memory {reps[0].get('rss_mb', 0):.0f} to {reps[-1].get('rss_mb', 0):.0f} MB; the most people at once {max(r.get('people', 0) for r in reps)}")
        if stalls:
            look_at.append(f"the server stalled (a gap over 100 ms between ticks) {len(stalls)} times, the first at {when(stalls[0]['t'])}")
        if worst["tick_max_ms"] > 50:
            look_at.append(f"a tick took {worst['tick_max_ms']:.0f} ms at {when(worst['t'])}")
        late = sum(v[2] for r in reps for v in r.get("inputs", []))
        inputs = sum(v[1] for r in reps for v in r.get("inputs", []))
        if inputs:
            print(f"  people's inputs: {inputs}, late {late} ({100.0 * late / inputs:.2f}%)")

    # matches and rounds
    rounds, matches = by["round"], by["match"]
    print("\nMATCHES AND ROUNDS")
    if rounds:
        secs = [r["secs"] for r in rounds]
        arenas = Counter(ARENAS.get(r.get("arena"), str(r.get("arena"))) for r in rounds)
        causes = Counter(CAUSES.get(d[2], str(d[2])) for r in rounds for d in r.get("deaths", []))
        print(f"  {len(matches)} matches ended, {len(rounds)} rounds (a median {med(secs):.1f} s, the longest {max(secs):.1f} s), "
              f"{sum(1 for r in rounds if r.get('draw'))} draws")
        print("  arenas: " + ", ".join(f"{k} {v}" for k, v in arenas.most_common()))
        print("  deaths by: " + ", ".join(f"{k} {v}" for k, v in causes.most_common()))
        long = [r for r in rounds if r["secs"] > 55]
        if long:
            look_at.append(f"{len(long)} rounds ran past 55 s")
    else:
        print("  no rounds")
    # p4.9 the power-ups: what was taken, by whom, the BIG ones (for the people behind)
    powers = by["power"]
    if powers:
        kinds = Counter(d.get("power", "?") for d in powers)
        takers = Counter(d.get("name", "?") for d in powers)
        bigs = [d for d in powers if d.get("power") in BIG]
        print(f"\nPOWER-UPS\n  {len(powers)} taken: " + ", ".join(f"{k} {v}" for k, v in kinds.most_common()))
        print("  by: " + ", ".join(f"{k} {v}" for k, v in takers.most_common(8)))
        if bigs:
            print("  BIG ones: " + ", ".join(f"{d.get('name', '?')} {d.get('power')}" for d in bigs[:12]))
    people = Counter()
    wins = Counter()
    for r in rounds:
        names = r.get("names", [])
        for n in names:
            if n and not n.startswith("BOT "):
                people[n] += 1
        w = r.get("winner", 255)
        if not r.get("draw") and isinstance(w, int) and w < len(names) and names[w] and not names[w].startswith("BOT "):
            wins[names[w]] += 1
    if people:
        print("  people (rounds played, rounds won): " + ", ".join(f"{n} {c}/{wins[n]}" for n, c in people.most_common()))

    # the phones
    phones = defaultdict(list)
    for c in by["client"]:
        phones[(c.get("name", "?"), c.get("ua", ""))].append(c)
    print("\nTHE PHONES (their own reports, every 30 s)")
    if not phones:
        print("  none (phones report from v0.2.0-p4.7 on)")
    stats_path = a.stats or os.path.join(os.path.dirname(a.file), "v2_stats.json")
    server_shots = {}
    if os.path.exists(stats_path):
        try:
            for p in json.load(open(stats_path)).get("players", []):
                if not p.get("bot"):
                    server_shots[p["name"]] = p.get("shots", 0)
        except (ValueError, KeyError):
            pass
    for (name, ua), rs in sorted(phones.items(), key=lambda kv: kv[1][0]["t"]):
        dev = rs[-1].get("device", "?")
        fps = [r["fps"] for r in rs if r.get("frames", 0) >= 30]
        slow = [r["slow_pct"] for r in rs if r.get("frames", 0) >= 30]
        pings = [r["ping_ms"] for r in rs if r.get("ping_ms", 0) > 0]
        looks = Counter(f"{r.get('pick')}/{r.get('look')}" for r in rs)
        steps = [r for r in rs if r.get("why") == "step"]
        reconnects = max(r.get("reconnects", 0) for r in rs)
        errors = Counter(e for r in rs for e in r.get("errors", []))
        armed = max(r.get("shots_armed", 0) for r in rs)
        cancelled = max(r.get("shots_cancelled", 0) for r in rs)
        mouse = max(r.get("mouse_shots", 0) for r in rs)
        print(f"  {name}: {model(ua)} ({dev}, {rs[-1].get('screen', '?')}), {len(rs)} reports {when(rs[0]['t'])} to {when(rs[-1]['t'])}")
        print(f"    look (pick/in use): " + ", ".join(f"{k} x{v}" for k, v in looks.most_common()) + (f"; stepped down {len(steps)} times" if steps else ""))
        if fps:
            print(f"    frame rate in matches: a median {med(fps):.0f} fps, the lowest {min(fps):.0f}; slow frames a median {med(slow):.1f}%, the most {max(slow):.1f}%; "
                  f"the longest frame {max(r.get('frame_max_ms', 0) for r in rs):.0f} ms")
        if pings:
            print(f"    ping: a median {med(pings):.0f} ms, the most {max(pings)} ms; reconnects {reconnects}")
        print(f"    shots let go: {armed} armed, {cancelled} let go inside the ring, {mouse} with the mouse"
              + (f"; the server counted {server_shots[name]} shots for {name}" if name in server_shots else ""))
        for e, n in errors.most_common(5):
            print(f"    page error x{n}: {e}")
        if steps:
            look_at.append(f"{name}'s {model(ua)} stepped its look down {len(steps)} times (first at {when(steps[0]['t'])}, to {steps[0].get('look')})")
        if fps and med(fps) < 45:
            look_at.append(f"{name}'s {model(ua)} ran a median {med(fps):.0f} fps in matches")
        if reconnects:
            look_at.append(f"{name}'s {model(ua)} reconnected {reconnects} times")
        if errors:
            look_at.append(f"{name}'s {model(ua)} logged {sum(errors.values())} page errors ({len(errors)} kinds)")
        if pings and max(pings) > 200:
            look_at.append(f"{name}'s ping reached {max(pings)} ms")
        if name in server_shots and armed + mouse > server_shots[name] + 2:
            look_at.append(f"{name} let go {armed + mouse} armed shots, the server counted {server_shots[name]} (a page reload resets the phone's count)")

    print("\nTO LOOK AT")
    for line in look_at or ["nothing stood out"]:
        print(f"  - {line}")


if __name__ == "__main__":
    main()
