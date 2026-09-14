#!/usr/bin/env python3
# ==============================================================================
# The 8-player benchmark's report (branch bench/8p). Reads one day's results:
# bench_results/<date>/server.jsonl (a line a second from bench_server.gd),
# synth.jsonl (bench_synth.py) and cards.jsonl (a card per phone step), and
# prints a table each with the pass marks of docs/reference/bench-8p-plan.md.
#   ./venv/bin/python tools/bench_report.py [--date 2026-09-10] [--dir bench_results]
# ==============================================================================
import argparse, json, os, statistics, time

def load(path):
    if not os.path.exists(path):
        return []
    out = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return out

def mark(ok):
    return "PASS" if ok else "fail"

def server_table(recs):
    runs, cur = [], None
    for r in recs:
        if r.get("kind") == "start":
            cur = {"start": r, "secs": []}
            runs.append(cur)
        elif r.get("kind") == "second" and cur is not None:
            cur["secs"].append(r)
    print("== Server (bench_server.gd) ==")
    for run in runs:
        s, secs = run["start"], [x for x in run["secs"] if x.get("clients", 0) > 0] or run["secs"]
        if not secs:
            continue
        # joins do a TLS handshake inside a tick: judge the steady state (after the
        # first 5 s with clients) and show the join spike on its own line
        steady = secs[5:] if len(secs) > 10 else secs
        join_worst = max(x["tick_p99_ms"] for x in secs[:5])
        p99s = [x["tick_p99_ms"] for x in steady]
        cpu = [x["cpu_pct"] for x in secs if x.get("cpu_pct", -1) >= 0]
        rss = [x["rss_mb"] for x in secs if x.get("rss_mb", -1) > 0]
        limit = 4.0 if s["fighters"] <= 8 else 8.0
        cpu_ok = (max(cpu) <= 25.0) if cpu else False
        rss_ok = (rss[-1] <= rss[0] * 1.1 + 5) if len(rss) > 1 else True
        started = time.strftime("%H:%M:%S", time.localtime(s["t"]))
        print(f"{started} {s.get('cpu','?')} x{s.get('cores','?')} | {s['fighters']} fighters, cap {s['arrow_cap']}, {'wss' if s.get('tls') else 'ws'} | {len(secs)} s with clients, up to {max(x['clients'] for x in secs)} clients")
        print(f"   steady: tick mean {statistics.mean(x['tick_mean_ms'] for x in steady):.2f} ms | p99 median {statistics.median(p99s):.2f} worst {max(p99s):.2f} ms (<= {limit}: {mark(max(p99s) <= limit)}) | max {max(x['tick_max_ms'] for x in steady):.2f} ms | while clients joined: worst tick {join_worst:.2f} ms")
        if cpu:
            print(f"   cpu mean {statistics.mean(cpu):.1f}% max {max(cpu):.1f}% (<= 25%: {mark(cpu_ok)}) | rss {rss[0] if rss else -1:.0f} -> {rss[-1] if rss else -1:.0f} MB ({mark(rss_ok)}) | out {statistics.mean(x['out_kbps'] for x in secs):.1f} KB/s | tick interval p99 worst {max(x['interval_p99_ms'] for x in secs):.1f} ms")

def synth_table(recs):
    if not recs:
        return
    print("\n== Synthetic clients (bench_synth.py) ==")
    for r in recs:
        ok = r["rtt_p95"] <= 40 and r["gap_p99"] <= 50 and r["stalls_150ms"] == 0 and not r.get("error")
        when = time.strftime("%H:%M:%S", time.localtime(r["t"]))
        print(f"{when} {r['name']:8} {r['url']:28} {r['seconds']:4d} s | rtt med {r['rtt_med']} p95 {r['rtt_p95']} max {r['rtt_max']} ms | gap p99 {r['gap_p99']} max {r['gap_max']} ms | stalls {r['stalls_150ms']} | {mark(ok)}" + (f" | {r['error']}" if r.get("error") else ""))

# Held 60: at 60 Hz frame times wobble around 16.7 ms, so judge by fps and the p99.
# Cards from before 2026-09-11 carry a stricter 'pass' that failed even a steady 60; it is ignored.
def held60(c):
    return c['fps'] >= 58 and c['ft_p99'] <= 25.0 and int(c.get('hitches_50ms', 0)) == 0

def cards_table(recs):
    runs = {}
    for c in recs:
        if c.get("kind") != "bench_card":
            continue
        runs.setdefault((c.get("name", "?"), c.get("run", "?")), []).append(c)
    if not runs:
        return
    print("\n== Phones (bench cards) ==")
    for (name, run), cards in runs.items():
        dev = cards[0].get("device", {})
        print(f"\n{name} (run {run}) | {dev.get('gpu', dev.get('adapter', '?'))} | screen {dev.get('sw','?')}x{dev.get('sh','?')} dpr {dev.get('dpr','?')} cores {dev.get('cores','?')} mem {dev.get('mem','?')} GB")
        print(f"   {'tier':12} {'res':6} {'cpu':3} {'render':10} {'fps':>5} {'p50':>6} {'p95':>6} {'p99':>6} {'max':>7} {'hitch':>5} {'proc':>5} {'draws':>5} {'lights':>6} {'rtt95':>5} {'gap99':>6} {'stall':>5}  verdict")
        best = {}
        w0 = next((c['window'] for c in cards if c.get('window')), None)
        for c in cards:
            if c.get("tier") == "done":
                continue
            # Godot's JSON writes every number as a float.
            for k in ("hitches_50ms", "draw_calls_max", "lights_now", "stalls_150ms", "tier_i", "limit_level"):
                if k in c:
                    c[k] = int(c[k])
            for lv in c.get("levels", []):
                for k in ("level", "fog_layers", "fighters", "lights"):
                    lv[k] = int(lv[k])
            if c.get("skipped"):
                print(f"   {c['tier']:12} {c['res']:6} {'cpu' if c.get('cpu_particles') else '':3} skipped: {c['skipped']}")
                continue
            if c.get("levels"):
                print(f"   {c['tier']:12} {c['res']:6} limit test: stopped at level {len(c['levels'])}")
                for lv in c["levels"]:
                    print(f"      level {lv['level']:2d}: particles x{lv['particles']:.2f} fog layers {lv['fog_layers']} fighters {lv['fighters']:2d} lights {lv['lights']:2d} | {lv['fps']:5.0f} fps p95 {lv['ft_p95']:6.1f} p99 {lv['ft_p99']:6.1f} ms proc {lv['proc_ms']:4.1f} | {mark(held60(lv))}")
                continue
            rs = "x".join(str(v) for v in c.get("render_size", []))
            print(f"   {c['tier']:12} {c['res']:6} {'cpu' if c.get('cpu_particles') else '':3} {rs:10} {c['fps']:5.0f} {c['ft_p50']:6.1f} {c['ft_p95']:6.1f} {c['ft_p99']:6.1f} {c['ft_max']:7.1f} {c['hitches_50ms']:5d} {c['proc_ms']:5.1f} {c['draw_calls_max']:5d} {c['lights_now']:6d} {c['rtt_p95']:5.0f} {c['gap_p99']:6.1f} {c['stalls_150ms']:5d}  {mark(held60(c))}" + (f"  (window changed to {c['window'][0]:.0f}x{c['window'][1]:.0f})" if w0 and c.get('window') != w0 else ""))
            if held60(c) and not c.get("cpu_particles"):
                best[c["res"]] = max(best.get(c["res"], -1), c["tier_i"])
        names = ["T0 plain", "T1 lights", "T2 effects", "T3 shaders", "T4 live 3D", "T5 stress", "T6 max", "T7 limit"]
        print("   highest tier held at 60 fps: " + ", ".join(f"{res}: {names[t] if t >= 0 else 'none'}" for res, t in best.items()) if best else "   highest tier held at 60 fps: none")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bench_results"))
    ap.add_argument("--date", default=time.strftime("%Y-%m-%d"))
    a = ap.parse_args()
    d = os.path.join(a.dir, a.date)
    server_table(load(os.path.join(d, "server.jsonl")))
    synth_table(load(os.path.join(d, "synth.jsonl")))
    cards_table(load(os.path.join(d, "cards.jsonl")))

if __name__ == "__main__":
    main()
