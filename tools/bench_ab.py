# Branch beta. Runs the bench server with different settings, one stage after
# another, locally or on the laptop (a copy in ~/tower_brawl_bench there), with the
# fake players from this PC. Used for the network thread tests in bench-8p-results.md.
#   python3 tools/bench_ab.py <out_dir> local|laptop <port> name:fighters:cap:clients:secs:netthread[:sleep_ms[:cores]] ...
#   python3 tools/bench_ab.py /tmp/ab laptop 8093 off:8:24:7:120:0 on:8:24:7:120:1:4 pinned:8:24:7:120:1:4:2,3
# Then: python3 tools/bench_ab_summary.py /tmp/ab
import json, os, socket, subprocess, sys, time
out, where, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
os.makedirs(out, exist_ok=True)
ip = "127.0.0.1" if where == "local" else "192.168.4.29"
def port_open():
    try:
        socket.create_connection((ip, port), timeout=1).close(); return True
    except OSError:
        return False
for spec in sys.argv[4:]:
    parts = spec.split(":")
    name, f, cap, n, secs, nt = parts[:6]
    sleep_ms = parts[6] if len(parts) > 6 else "1"
    pin = parts[7] if len(parts) > 7 else ""
    prefix = f"taskset -c {pin} " if pin else ""
    res = f"{out}/{name}"
    args = f"--port {port} --fighters {f} --arrow-cap {cap} --seconds {secs} --net-thread {nt} --net-sleep-ms {sleep_ms}"
    if where == "local":
        proc = subprocess.Popen(["godot", "--headless", "--path", "bench", "res://server/bench_server.tscn", "--"] + args.split() + ["--out", res],
                                stdout=open(f"{res}.log", "w"), stderr=subprocess.STDOUT)
    else:
        subprocess.run(["ssh", "-o", "BatchMode=yes", "nemr@192.168.4.29",
            f"cd ~/tower_brawl_bench; setsid nohup {prefix}godot --headless --path . res://server/bench_server.tscn -- {args} "
            f"--out ~/tower_brawl_bench/ab/{name} --cert ~/tower_brawl/cert.pem --key ~/tower_brawl/key.pem > ~/tower_brawl_bench/ab_{name}.log 2>&1 < /dev/null &"])
    t0 = time.time()
    while not port_open():
        if time.time() - t0 > 60:
            print(name, "server never opened"); sys.exit(1)
        time.sleep(0.3)
    time.sleep(3)   # a few quiet ticks before the joins
    subprocess.run(["./venv/bin/python", "tools/bench_synth.py", "--url", f"wss://{ip}:{port}", "--n", n,
                    "--seconds", str(int(secs) - 20), "--out", res], stdout=open(f"{res}_synth.log", "w"), stderr=subprocess.STDOUT)
    while port_open():
        time.sleep(1)
    if where == "laptop":
        subprocess.run(["rsync", "-a", f"nemr@192.168.4.29:tower_brawl_bench/ab/{name}/", f"{res}/"])
    time.sleep(2)
    print(name, "done", flush=True)
print("all done", flush=True)
