#!/usr/bin/env python3
# ==============================================================================
# The soak report (G6): reads the new game's server log (v2_server.jsonl:
# bench/server/game_server.gd writes a report line every 5 s, a round line at each
# round's end with every death, and a match line at each match's end) for one run
# of the server (the last start, or the one at --from) and says whether it held:
# every match ended, no round over 55 s, no tick over 50 ms, no stall (two ticks
# more than 100 ms apart), and where the kills fell (the squares of 120 px with a
# death, per arena, and a map in letters). The PNG maps: bench/tools/bot_probe.gd
# -- --deaths=<the jsonl> --png=<dir>.
#
#   ./venv/bin/python tools/v2_soak_report.py [--file bench_results/<date>/v2_server.jsonl] [--from HH:MM] [--map]
#   -> PASS/FAIL lines; exit 1 on a FAIL
# ==============================================================================
import argparse, json, os, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
ARENAS = {0: "THE BENCH", 1: "THE KEEP", 2: "THE BRIDGES"}
CAUSES = {1: "arrow", 2: "blast", 3: "stomp", 4: "fire", 5: "miasma", 6: "the walls"}
LEVELS = ["OLD", "EASY", "NORMAL", "HARD"]
SQ, COLS, ROWS = 120, 16, 9

def load(path, start_hhmm):
    lines = []
    with open(path) as fh:
        for raw in fh:
            raw = raw.strip()
            if raw:
                try:
                    lines.append(json.loads(raw))
                except ValueError:
                    pass
    starts = [i for i, r in enumerate(lines) if r.get("kind") == "start"]
    if not starts:
        sys.exit("no server start in %s" % path)
    pick = starts[-1]
    if start_hhmm:
        for i in starts:
            if time.strftime("%H:%M", time.localtime(lines[i]["t"])) >= start_hhmm:
                pick = i
                break
    end = next((i for i in starts if i > pick), len(lines))
    return lines[pick], lines[pick + 1:end]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default=os.path.join(ROOT, "bench_results", time.strftime("%Y-%m-%d"), "v2_server.jsonl"))
    ap.add_argument("--from", dest="start", default="", help="the run that started at or after HH:MM (default: the last)")
    ap.add_argument("--map", action="store_true", help="a death map in letters per arena")
    a = ap.parse_args()
    start, recs = load(a.file, a.start)
    reports = [r for r in recs if r.get("kind") == "report"]
    rounds = [r for r in recs if r.get("kind") == "round"]
    matches = [r for r in recs if r.get("kind") == "match"]
    up = reports[-1]["up_s"] if reports else 0.0
    print("== %s %s on %s, %s: %.1f h up, %d matches started, %d ended, %d rounds" % (
        start.get("version"), "soak" if start.get("soak") else "server", start.get("host") or start.get("cpu"),
        time.strftime("%Y-%m-%d %H:%M", time.localtime(start["t"])), up / 3600.0,
        max([r["match"] for r in rounds] or [0]), len(matches), len(rounds)))
    fails = 0
    def rule(name, ok, detail):
        nonlocal fails
        fails += 0 if ok else 1
        print("%s %s: %s" % ("PASS" if ok else "FAIL", name, detail))
    started = max([r["match"] for r in rounds] or [0])
    rule("every match ended", started - len(matches) <= 1,
         "%d started, %d ended (the one on at the end may still run)" % (started, len(matches)))
    secs = sorted(r["secs"] for r in rounds)
    over = [r for r in rounds if r["secs"] > 55.0]
    if secs:
        rule("no round over 55 s", not over, "median %.1f s, p90 %.1f s, the longest %.1f s; draws %d%%" % (
            secs[len(secs) // 2], secs[int(len(secs) * 0.9)], secs[-1], round(100.0 * sum(1 for r in rounds if r["draw"]) / len(rounds))))
    worst_tick = max([r["tick_max_ms"] for r in reports] or [0.0])
    worst_gap = max([r["interval_max_ms"] for r in reports] or [0.0])
    mean_tick = sum(r["tick_mean_ms"] for r in reports) / max(1, len(reports))
    stalls = sum(1 for r in reports if r["interval_max_ms"] > 100.0)
    rule("no tick over 50 ms", worst_tick <= 50.0, "the worst %.2f ms, the mean %.3f ms over %d reports" % (worst_tick, mean_tick, len(reports)))
    rule("no stall (ticks over 100 ms apart)", stalls == 0, "the widest gap %.1f ms; %d report windows with a stall" % (worst_gap, stalls))
    if reports:
        rss = [r["rss_mb"] for r in reports]
        print("   memory: %.0f MB at the start, %.0f MB at the end (the most %.0f MB); cpu %.1f%% mean" % (
            rss[0], rss[-1], max(rss), sum(r["cpu_pct"] for r in reports) / len(reports)))
    causes = Counter()
    per_arena = defaultdict(Counter)
    for r in rounds:
        for d in r["deaths"]:
            causes[d[2]] += 1
            per_arena[r["arena"]][(min(COLS - 1, max(0, int(d[3]) // SQ)), min(ROWS - 1, max(0, int(d[4]) // SQ)))] += 1
    total = sum(causes.values())
    print("   deaths: %d (%s); bots: %s" % (total, ", ".join("%s %d%%" % (CAUSES.get(k, k), round(100.0 * v / max(1, total)))
        for k, v in causes.most_common()), ", ".join(sorted({LEVELS[r.get("bot_level", 0)] for r in rounds}))))
    for n in sorted(per_arena):
        sq = per_arena[n]
        deaths = sum(sq.values())
        top = sum(v for _, v in sq.most_common(15))
        nr = sum(1 for r in rounds if r["arena"] == n)
        print("   %s: %d rounds, %d deaths in %d of %d squares, the busiest 15 hold %d%%" % (
            ARENAS.get(n, n), nr, deaths, len(sq), COLS * ROWS, round(100.0 * top / max(1, deaths))))
        if a.map:
            most = max(sq.values())
            for y in range(ROWS):
                print("      " + "".join(" .:-=+*#%@"[min(9, (9 * sq[(x, y)] + most - 1) // most)] if sq[(x, y)] else " " for x in range(COLS)))
    if per_arena:
        spread = min(len(per_arena[n]) for n in per_arena)
        rule("kills spread over the arena (at least 90 of the 144 squares on each arena)", spread >= 90,
             "the fewest: %d squares" % spread)
    sys.exit(1 if fails else 0)

if __name__ == "__main__":
    main()
