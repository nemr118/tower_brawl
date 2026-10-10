#!/usr/bin/env python3
# ==============================================================================
# The 8-player benchmark's synthetic clients (branch beta). N threads, each a
# websocket client of bench/server/bench_server.gd: 60 inputs a second (4 ticks
# per packet), a ping every 0.5 s, and it reads every snapshot. It fills the
# seats the phones don't, so the server carries 8 real sockets, and it measures
# the network from where it sits: round trip, gaps between snapshots, stalls.
#
#   ./venv/bin/python tools/bench_synth.py --url wss://192.168.4.29:8091 --n 7 --seconds 300
#   -> one line per client at the end, and bench_results/<date>/synth.jsonl
# ==============================================================================
import argparse, json, os, socket, ssl, struct, threading, time
import websocket

T_SNAP, T_INPUT, T_PING, T_PONG = 1, 2, 3, 4

def pct(vals, p):
    if not vals:
        return 0.0
    s = sorted(vals)
    return s[min(len(s) - 1, int(len(s) * p))]

class Synth(threading.Thread):
    def __init__(self, idx, url, seconds):
        super().__init__(daemon=True)
        self.idx, self.url, self.seconds = idx, url, seconds
        self.name_ = f"synth{idx}"
        self.rtts, self.gaps = [], []
        self.snaps = self.bytes_in = self.bytes_out = 0
        self.err = None
        self.last_rtt = 0
        self.worst_gap = 0
        self.stop = False

    def run(self):
        ws = None
        deadline = time.monotonic() + 8.0
        while ws is None:
            try:
                ws = websocket.create_connection(self.url, timeout=3, enable_multithread=True,
                                                 sslopt={"cert_reqs": ssl.CERT_NONE, "check_hostname": False})
            except Exception as e:
                if time.monotonic() > deadline:
                    self.err = f"connect: {e}"
                    return
                time.sleep(0.25)
        ws.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        ws.settimeout(1.0)
        ws.send(json.dumps({"kind": "hello", "name": self.name_}))
        sender = threading.Thread(target=self.send_loop, args=(ws,), daemon=True)
        sender.start()
        end = time.monotonic() + self.seconds
        last = None
        warm = time.monotonic() + 1.0
        while time.monotonic() < end:
            try:
                op, data = ws.recv_data()
            except websocket.WebSocketTimeoutException:
                continue
            except Exception as e:
                self.err = f"recv: {e}"
                break
            if not data:
                continue
            self.bytes_in += len(data)
            if op == websocket.ABNF.OPCODE_BINARY and data[0] == T_SNAP:
                now = time.monotonic()
                if last is not None and now > warm:
                    g = (now - last) * 1000.0
                    self.gaps.append(g)
                    self.worst_gap = max(self.worst_gap, int(g))
                last = now
                self.snaps += 1
            elif op == websocket.ABNF.OPCODE_BINARY and data[0] == T_PONG and len(data) >= 9:
                sent = struct.unpack_from("<I", data, 1)[0]
                rtt = ((int(time.monotonic() * 1000) & 0xFFFFFFFF) - sent) & 0xFFFFFFFF
                self.rtts.append(rtt)
                self.last_rtt = rtt
        self.stop = True
        try:
            ws.close()
        except Exception:
            pass

    def send_loop(self, ws):
        tick = 0
        next_t = time.monotonic()
        next_ping = next_t
        hist = []
        while not self.stop:
            now = time.monotonic()
            if now < next_t:
                time.sleep(min(0.004, next_t - now))
                continue
            next_t += 1.0 / 60.0
            tick += 1
            hist.append(struct.pack("<BIBH", T_INPUT, tick, (tick // 20) % 256, (tick * 7) % 3600))
            hist = hist[-4:]
            try:
                pkt = b"".join(hist)
                ws.send_binary(pkt)
                self.bytes_out += len(pkt)
                if now >= next_ping:
                    next_ping = now + 0.5
                    ws.send_binary(struct.pack("<BIHH", T_PING, int(now * 1000) & 0xFFFFFFFF,
                                               min(self.last_rtt, 65535), min(self.worst_gap, 65535)))
                    self.worst_gap = 0
            except Exception as e:
                self.err = self.err or f"send: {e}"
                return

    def summary(self):
        stalls = sum(1 for g in self.gaps if g > 150.0)
        secs = max(1, self.seconds)
        return {"kind": "synth", "t": time.time(), "name": self.name_, "url": self.url, "seconds": self.seconds,
                "snaps": self.snaps, "snaps_per_s": round(self.snaps / secs, 1),
                "kb_in_s": round(self.bytes_in / 1000 / secs, 2), "kb_out_s": round(self.bytes_out / 1000 / secs, 2),
                "rtt_med": pct(self.rtts, 0.5), "rtt_p95": pct(self.rtts, 0.95), "rtt_max": max(self.rtts or [0]),
                "gap_p50": round(pct(self.gaps, 0.5), 1), "gap_p99": round(pct(self.gaps, 0.99), 1),
                "gap_max": round(max(self.gaps or [0.0]), 1), "stalls_150ms": stalls, "error": self.err}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="wss://127.0.0.1:8091")
    ap.add_argument("--n", type=int, default=7)
    ap.add_argument("--seconds", type=int, default=30)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bench_results"))
    a = ap.parse_args()
    threads = [Synth(i + 1, a.url, a.seconds) for i in range(a.n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(a.seconds + 15)
    out_dir = os.path.join(a.out, time.strftime("%Y-%m-%d"))
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "synth.jsonl"), "a") as f:
        for t in threads:
            s = t.summary()
            f.write(json.dumps(s) + "\n")
            print(f"🤖 [BenchSynth] {s['name']}: {s['snaps_per_s']} snaps/s {s['kb_in_s']} KB/s in | rtt med {s['rtt_med']} p95 {s['rtt_p95']} max {s['rtt_max']} ms | gap p50 {s['gap_p50']} p99 {s['gap_p99']} max {s['gap_max']} ms | stalls>150ms {s['stalls_150ms']}" + (f" | ERROR {s['error']}" if s['error'] else ""))

if __name__ == "__main__":
    main()
