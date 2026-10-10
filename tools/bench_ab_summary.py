# Branch beta. One line per stage from tools/bench_ab.py: steady tick cost, the worst
# tick while players join, network thread time, CPU, and what the fake players got.
#   python3 tools/bench_ab_summary.py <out_dir> [<out_dir> ...]
import glob, json, os, statistics, sys
for d in sys.argv[1:]:
    for stage in sorted(glob.glob(os.path.join(d, "*/"))):
        name = os.path.basename(stage.rstrip("/"))
        srv = glob.glob(os.path.join(stage, "*", "server.jsonl"))
        syn = glob.glob(os.path.join(stage, "*", "synth.jsonl"))
        if not srv:
            continue
        recs = [json.loads(l) for l in open(srv[0]) if l.strip()]
        secs = [r for r in recs if r.get("kind") == "second"]
        start = next((r for r in recs if r.get("kind") == "start"), {})
        top = max((r["clients"] for r in secs), default=0)
        full = [r for r in secs if r["clients"] == top and top > 0]
        steady = full[2:-2] if len(full) > 6 else full
        join = [r for r in secs if 0 < r["clients"] < top] + full[:2]
        line = f"{name:14} net_thread={start.get('net_thread', False)!s:5} | {top:2d} clients | "
        if steady:
            line += (f"tick mean {statistics.mean(r['tick_mean_ms'] for r in steady):.2f} ms, p99 median {statistics.median(r['tick_p99_ms'] for r in steady):.2f}, "
                     f"worst {max(r['tick_max_ms'] for r in steady):.2f} | send {statistics.mean(r['send_mean_ms'] for r in steady):.2f} | "
                     f"net thread {statistics.mean(r.get('net_busy_ms', 0) for r in steady):.1f} ms/s | cpu {statistics.mean(r['cpu_pct'] for r in steady if r['cpu_pct'] >= 0):.1f}% | "
                     f"interval p99 worst {max(r['interval_p99_ms'] for r in steady):.1f} ms")
        if join:
            line += f" | JOIN worst tick {max(r['tick_max_ms'] for r in join):.1f} ms, interval {max(r['interval_max_ms'] for r in join):.1f} ms"
        if syn:
            s = [json.loads(l) for l in open(syn[0]) if l.strip()]
            if s:
                line += f" | clients: rtt p95 worst {max(x['rtt_p95'] for x in s)} ms, gap p99 worst {max(x['gap_p99'] for x in s)} ms, stalls {sum(x['stalls_150ms'] for x in s)}"
        print(line)
