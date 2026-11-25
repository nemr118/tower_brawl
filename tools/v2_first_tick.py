#!/usr/bin/env python3
# ==============================================================================
# The slow first tick on an arena, measured on a real server (p4.19's "found, not
# fixed" 2). The bots get around by a route map (bench/sim/routes.gd). It is built
# the first time a bot asks for it: about 1 s after FIGHT in the first round on each
# arena, in the middle of a tick. That one tick took 14 to 33 ms (a tick has 16.7).
# This tool counts the worst tick of many FIRST rounds:
#   a test server starts (7 bots, nobody else); for each arena of the lobby's list the
#   host port picks it, starts a match, waits 1.5 s past FIGHT, and ends the match;
#   the server's own report line (every 5 s: "tick mean .. p99 .. max .. ms") gives the
#   worst tick of that time. Then the server is stopped (by its PID) and the next one
#   starts: a route map is built once per server, so every run is 6 first rounds.
#
#   ./venv/bin/python tools/v2_first_tick.py --runs 17 --port 8310 --admin-port 8320 \
#       [--bench DIR] [--out DIR] [--season harvest]
#   --bench DIR: the server from another copy of bench/ (the "before" number).
#   -> a line per first round, a summary, <out>/first_tick.json.
# ==============================================================================
import argparse, json, os, re, statistics, sys, time
from v2_chaos import Host, Server, ROOT

ap = argparse.ArgumentParser()
ap.add_argument("--runs", type=int, default=17, help="servers started; each plays a first round on every arena (6)")
ap.add_argument("--port", type=int, default=8310)
ap.add_argument("--admin-port", type=int, default=8320)
ap.add_argument("--bench", default="")
ap.add_argument("--season", default="harvest")
ap.add_argument("--out", default=os.path.join(ROOT, "bench_results", "first_tick"))
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
MAX_RE = re.compile(r"tick mean ([\d.]+) p99 ([\d.]+) max ([\d.]+) ms \(sim")
rows = []          # {run, arena, name, worst_ms, slow_line}
start_ms = []      # each server's start: from the process start to the open port


def read_new(path, pos):
    """The server's output from byte pos on, and the new pos."""
    with open(path, "rb") as f:
        f.seek(pos)
        raw = f.read()
    return raw.decode("utf-8", "replace"), pos + len(raw)


for run in range(a.runs):
    t_start = time.time()
    server = Server(a.port, a.admin_port, os.path.join(a.out, f"run{run:02d}"),
                    ["--bots", "7", "--season", a.season, "--arena", "keep"], a.bench or None)
    start_ms.append((time.time() - t_start) * 1000.0)
    host = Host(a.admin_port)
    try:
        time.sleep(0.5)
        arenas = [x for x in host.state()["arenas"] if x["name"] != "MIX"]
        pos = 0
        for ar in arenas:
            _, pos = read_new(server.log_path, pos)        # (what came before this round is not this round's)
            host.cmd("arena", n=ar["n"])
            host.cmd("start")
            seen = ""
            t_fight = 0.0
            stopped = False
            worst, slow = 0.0, ""
            end = time.time() + 30.0
            while time.time() < end:
                time.sleep(0.1)
                text, pos = read_new(server.log_path, pos)
                seen += text
                if t_fight == 0.0 and "FIGHT" in seen:
                    t_fight = time.time()
                if t_fight > 0.0 and not stopped and time.time() >= t_fight + 1.5:
                    host.cmd("stop")
                    stopped = True
                    seen_at_stop = len(seen)
                for line in text.splitlines():
                    if "[SLOW]" in line:
                        slow = line.strip()
                    m = MAX_RE.search(line)
                    if m:
                        worst = max(worst, float(m.group(3)))
                # the report line that holds the tick 1 s after FIGHT: the first one printed after the stop
                if stopped and MAX_RE.search(seen[seen_at_stop:]):
                    break
            rows.append({"run": run, "arena": ar["n"], "name": ar["name"], "worst_ms": worst, "slow": slow, "fight": t_fight > 0.0})
            print(f"run {run:2d}  {ar['name']:<18} worst tick {worst:6.2f} ms{'   ' + slow[slow.find('took'):slow.find('; phase')] if slow else ''}", flush=True)
    finally:
        server.stop()

ok = [r for r in rows if r["fight"]]
worsts = sorted(r["worst_ms"] for r in ok)
summary = {"first_rounds": len(ok), "no_fight": len(rows) - len(ok), "bench": a.bench or "this copy",
           "worst_ms": worsts[-1] if worsts else 0.0, "median_ms": statistics.median(worsts) if worsts else 0.0,
           "over_12_ms": sum(1 for w in worsts if w > 12.0), "over_16_7_ms": sum(1 for w in worsts if w > 16.7),
           "slow_lines": sum(1 for r in ok if r["slow"]),
           "server_start_ms_median": statistics.median(start_ms), "server_start_ms_max": max(start_ms), "by_arena": {}}
for name in sorted(set(r["name"] for r in ok)):
    w = sorted(r["worst_ms"] for r in ok if r["name"] == name)
    summary["by_arena"][name] = {"n": len(w), "median_ms": statistics.median(w), "worst_ms": w[-1]}
print("\n== first rounds: %d (no FIGHT seen: %d), the server from %s" % (summary["first_rounds"], summary["no_fight"], summary["bench"]))
for name, v in summary["by_arena"].items():
    print(f"   {name:<18} {v['n']:3d} first rounds: the worst tick's median {v['median_ms']:6.2f} ms, the worst {v['worst_ms']:6.2f} ms")
print("   all: the worst tick %.2f ms, the median %.2f ms; over 12 ms: %d, over 16.7 ms (a whole tick): %d; [SLOW] lines: %d" % (
    summary["worst_ms"], summary["median_ms"], summary["over_12_ms"], summary["over_16_7_ms"], summary["slow_lines"]))
print("   the server's start (process start to the open port, checked every 0.2 s): median %.0f ms, the longest %.0f ms" % (
    summary["server_start_ms_median"], summary["server_start_ms_max"]))
with open(os.path.join(a.out, "first_tick.json"), "w") as f:
    json.dump({"summary": summary, "rows": rows}, f, indent=1)
sys.exit(0)
