#!/usr/bin/env python3
# ==============================================================================
# Fake players for the new game (bench/server/game_server.gd, P1). N threads,
# each a websocket client: hello with the game's version (read from
# bench/sim/proto.gd), a seat, 60 inputs a second (4 ticks per packet), a ping
# every 0.5 s, and it reads every snapshot. A small brain: run at the nearest
# fighter, jump now and then, hold shoot and let go aimed at it, dodge when an
# arrow comes close. They fill the seats the phones don't, so a proof can run a
# whole match on the PC with one headless person (bench/tools/play_probe.gd).
# P2: each input carries the server tick it is for: the newest snapshot's tick,
# plus the time since it came, plus the round trip and 3 ticks (a plain version
# of client/net.gd's clock; they ignore T_OWN).
#
#   ./venv/bin/python tools/v2_synth.py --url ws://127.0.0.1:8091 --n 7 --seconds 300 [--start] [--bots 0]
#   --start: the first fake player presses START once the lobby has 2 fighters.
#   -> one line per client at the end, and bench_results/<date>/v2_synth.jsonl
# ==============================================================================
import argparse, json, math, os, random, re, socket, ssl, struct, threading, time
import websocket

T_SNAP, T_INPUT, T_PING, T_PONG = 1, 2, 3, 4
B_LEFT, B_RIGHT, B_UP, B_DOWN, B_JUMP, B_SHOOT, B_DODGE = 1, 2, 4, 8, 16, 32, 64
F_DEAD = 2
S_FLY, S_STUCK = 0, 2
PH_LOBBY, PH_PLAY = 0, 3
W, H = 1920.0, 1080.0
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")

def game_version():
    with open(os.path.join(ROOT, "bench", "sim", "proto.gd")) as f:
        m = re.search(r'const VERSION := "([^"]+)"', f.read())
    return m.group(1) if m else "?"

def wrap_d(a, b, size):
    d = b - a
    if d > size * 0.5:
        d -= size
    elif d < -size * 0.5:
        d += size
    return d

def pct(vals, p):
    if not vals:
        return 0.0
    s = sorted(vals)
    return s[min(len(s) - 1, int(len(s) * p))]

def decode_snapshot(data):
    tick, phase, rnd, left, goal, winner, walls, arena = struct.unpack_from("<IBBHBBHB", data, 1)
    nf, na, nz, ne = struct.unpack_from("<BHBH", data, 14)
    off = 20
    fighters = {}
    for _ in range(nf):
        sid, state, x, y, vx, vy, flags, aim, arrows, st, points, flags2 = struct.unpack_from("<BBhhbbBBBBBB", data, off)
        fighters[sid] = {"state": state, "x": x, "y": y, "points": points, "arrows": arrows, "flags": flags}
        off += 14
    arrows = []
    for _ in range(na):
        aid, ks = struct.unpack_from("<HB", data, off)
        if (ks >> 4) & 3 == S_STUCK:   # stuck: s16 x, s16 y, u8 angle (p4.9: 0x40 marks a BIG arrow)
            x, y, ang = struct.unpack_from("<hhB", data, off + 3)
            arrows.append({"state": (ks >> 4) & 3, "x": x, "y": y, "ang": ang * math.tau / 256.0})
            off += 8
        else:                    # in the air (P2): f32 x, y, vx, vy, u8 age, u8 owner
            x, y, vx, vy, age, owner = struct.unpack_from("<ffffBB", data, off + 3)
            arrows.append({"state": (ks >> 4) & 3, "x": x, "y": y, "ang": math.atan2(vy, vx), "owner": owner})
            off += 21
    return {"tick": tick, "phase": phase, "round": rnd, "goal": goal, "winner": winner,
            "walls": walls & 0x7FFF, "arena": arena, "fighters": fighters, "arrows": arrows}

class Synth(threading.Thread):
    def __init__(self, idx, url, seconds, version, start, bots):
        super().__init__(daemon=True)
        self.idx, self.url, self.seconds, self.version = idx, url, seconds, version
        self.start_wanted, self.bots = start, bots
        self.name_ = f"Fake{idx}"
        self.rtts, self.gaps = [], []
        self.snaps = self.bytes_in = self.bytes_out = 0
        self.err = None
        self.last_rtt = 0
        self.worst_gap = 0
        self.stop = False
        self.seat = -1
        self.snap = None
        self.snap_tick = 0          # the newest snapshot's tick and when it came, for the input ticks
        self.snap_t = 0.0
        self.start_sent = False
        self.rounds_won = 0
        self.matches = 0
        self.rng = random.Random(idx * 7919)
        self.last_pos = None
        self.still_t = 0
        self.unstick_t = 0
        self.unstick_dir = 1

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
        self.ws = ws
        ws.send(json.dumps({"kind": "hello", "name": self.name_, "version": self.version, "token": f"fake{self.idx}"}))
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
            if op == websocket.ABNF.OPCODE_TEXT:
                self.on_text(ws, data.decode("utf-8", "replace"))
            elif op == websocket.ABNF.OPCODE_BINARY and data[0] == T_SNAP:
                now = time.monotonic()
                if last is not None and now > warm:
                    g = (now - last) * 1000.0
                    self.gaps.append(g)
                    self.worst_gap = max(self.worst_gap, int(g))
                last = now
                self.snaps += 1
                try:
                    self.snap = decode_snapshot(data)
                    self.snap_tick, self.snap_t = self.snap["tick"], now
                except struct.error as e:
                    self.err = self.err or f"snapshot: {e}"
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

    def on_text(self, ws, s):
        try:
            d = json.loads(s)
        except json.JSONDecodeError:
            return
        kind = d.get("kind")
        if kind == "welcome":
            self.seat = int(d.get("seat", -1))
            if self.seat < 0:
                ws.send(json.dumps({"kind": "join", "name": self.name_}))
            elif self.bots is not None and self.idx == 1:
                ws.send(json.dumps({"kind": "bots", "n": self.bots}))
        elif kind == "version_error":
            self.err = f"version_error: server {d.get('server')} mine {d.get('yours')}"
        elif kind == "full":
            self.err = "full"
        elif kind == "seats":
            if (self.start_wanted and self.idx == 1 and not self.start_sent and self.seat >= 0
                    and int(d.get("phase", 0)) == PH_LOBBY and int(d.get("people", 0)) + int(d.get("bots", 0)) >= 2):
                self.start_sent = True
                ws.send(json.dumps({"kind": "start"}))
                print(f"🤖 [V2Synth] {self.name_} pressed START ({d.get('people')} people + {d.get('bots')} bots)", flush=True)
        elif kind == "round_end":
            if int(d.get("winner", 255)) == self.seat:
                self.rounds_won += 1
        elif kind == "match_end":
            self.matches += 1
            self.start_sent = False   # the next lobby: press START again

    # The brain: a few buttons from the last snapshot.
    def think(self, tick):
        s = self.snap
        if s is None or self.seat < 0 or s["phase"] != PH_PLAY or self.seat not in s["fighters"]:
            return 0, 0
        me = s["fighters"][self.seat]
        if me["state"] == F_DEAD:
            return 0, 0
        mx, my = me["x"] + 18, me["y"] + 31
        best, bd = None, 1e18
        for sid, f in s["fighters"].items():
            if sid == self.seat or f["state"] == F_DEAD:
                continue
            dx, dy = wrap_d(mx, f["x"] + 18, W), wrap_d(my, f["y"] + 31, H)
            d2 = dx * dx + dy * dy
            if d2 < bd:
                bd, best = d2, (dx, dy)
        buttons = 0
        aim = 0
        goal = best
        if me["arrows"] == 0:
            # an empty quiver: walk to the nearest stuck arrow (the pickup is automatic),
            # the ones level with me or below first (a dumb walker cannot climb far)
            sd = 1e18
            for a in s["arrows"]:
                if a["state"] != S_STUCK:
                    continue
                ax, ay = wrap_d(mx, a["x"], W), wrap_d(my, a["y"], H)
                d2 = ax * ax + ay * ay + (400 * 400 if ay < -80 else 0)
                if d2 < sd:
                    sd, goal = d2, (ax, ay)
        # stuck against something: hop and go the other way for a moment
        pos = (me["x"], me["y"])
        if self.last_pos is not None and abs(pos[0] - self.last_pos[0]) < 3 and abs(pos[1] - self.last_pos[1]) < 3:
            self.still_t += 1
        else:
            self.still_t = 0
        self.last_pos = pos
        if self.still_t > 60 and self.unstick_t == 0:
            self.unstick_t = 40
            self.unstick_dir = -1 if (goal is not None and goal[0] > 0) else 1
            self.still_t = 0
        if self.unstick_t > 0:
            self.unstick_t -= 1
            buttons |= B_RIGHT if self.unstick_dir > 0 else B_LEFT
            if self.unstick_t > 25:
                buttons |= B_JUMP
        elif goal is not None:
            dx, dy = goal
            if abs(dx) > 30:
                buttons |= B_RIGHT if dx > 0 else B_LEFT
            if dy < -60 and (tick // 20) % 3 == 0:
                buttons |= B_JUMP
            if dy > 120 and (tick // 30) % 4 == 0:
                buttons |= B_DOWN | B_JUMP
        if best is not None and me["arrows"] > 0:
            dx, dy = best
            # hold shoot 12 ticks, let go: a shot every ~90 ticks, closer = more often
            near = dx * dx + dy * dy < 500 * 500
            cyc = (tick + self.idx * 11) % (50 if near else 90)
            if cyc < 12:
                buttons |= B_SHOOT
            aim = int(math.degrees(math.atan2(dy, dx)) * 10) % 3600
        for a in s["arrows"]:
            if a["state"] != S_FLY:
                continue
            ax, ay = wrap_d(mx, a["x"], W), wrap_d(my, a["y"], H)
            if ax * ax + ay * ay < 120 * 120 and (tick % 8) == 0:
                buttons |= B_DODGE
                break
        if (tick + self.idx * 5) % 90 == 0 and self.rng.random() < 0.6:
            buttons |= B_JUMP   # a hop now and then: over a bump, off a ledge
        return buttons, aim

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
            if self.snap_t <= 0.0:
                continue   # no snapshot yet: no clock
            # the server tick this input is for: never back, never a gap of more than 20
            want = int(self.snap_tick + (now - self.snap_t) * 60.0 + self.last_rtt * 0.06) + 3
            if tick == 0 or want - tick > 20:
                tick = want
            elif tick > want + 3:
                continue   # ahead enough: skip one
            else:
                tick += 1
            buttons, aim = self.think(tick)
            hist.append(struct.pack("<BIBH", T_INPUT, tick, buttons, aim))
            hist = hist[-4:]
            try:
                if self.seat >= 0:
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
        return {"kind": "v2_synth", "t": time.time(), "name": self.name_, "seat": self.seat, "url": self.url,
                "seconds": self.seconds, "snaps": self.snaps, "snaps_per_s": round(self.snaps / secs, 1),
                "kb_in_s": round(self.bytes_in / 1000 / secs, 2), "kb_out_s": round(self.bytes_out / 1000 / secs, 2),
                "rtt_med": pct(self.rtts, 0.5), "rtt_p95": pct(self.rtts, 0.95), "rtt_max": max(self.rtts or [0]),
                "gap_p50": round(pct(self.gaps, 0.5), 1), "gap_p99": round(pct(self.gaps, 0.99), 1),
                "gap_max": round(max(self.gaps or [0.0]), 1), "stalls_150ms": stalls,
                "rounds_won": self.rounds_won, "matches_seen": self.matches, "error": self.err}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="ws://127.0.0.1:8091")
    ap.add_argument("--n", type=int, default=7)
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--start", action="store_true", help="the first fake player presses START")
    ap.add_argument("--bots", type=int, default=None, help="the first fake player sets the bot count")
    ap.add_argument("--out", default=os.path.join(ROOT, "bench_results"))
    a = ap.parse_args()
    version = game_version()
    threads = [Synth(i + 1, a.url, a.seconds, version, a.start, a.bots) for i in range(a.n)]
    for t in threads:
        t.start()
        time.sleep(0.05)
    for t in threads:
        t.join(a.seconds + 15)
    out_dir = os.path.join(a.out, time.strftime("%Y-%m-%d"))
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "v2_synth.jsonl"), "a") as f:
        for t in threads:
            s = t.summary()
            f.write(json.dumps(s) + "\n")
            print(f"🤖 [V2Synth] {s['name']} seat {s['seat']}: {s['snaps_per_s']} snaps/s {s['kb_in_s']} KB/s in | rtt med {s['rtt_med']} p95 {s['rtt_p95']} max {s['rtt_max']} ms | gap p50 {s['gap_p50']} p99 {s['gap_p99']} max {s['gap_max']} ms | stalls>150ms {s['stalls_150ms']} | rounds won {s['rounds_won']} matches {s['matches_seen']}" + (f" | ERROR {s['error']}" if s['error'] else ""), flush=True)

if __name__ == "__main__":
    main()
