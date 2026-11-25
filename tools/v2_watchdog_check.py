#!/usr/bin/env python3
# ==============================================================================
# The PAGE's watchdog for a dead link (bench/client/net.gd QUIET_MAX_MS; p4.19's
# "found, not fixed" 3), on the real page in headless Chromium against real test
# servers. A phone that walks out of the Wi-Fi showed a frozen match until the browser
# itself said the socket had closed. Now the page gives up an open socket that has
# brought nothing for 5 s, and its own "The connection dropped. Joining again by
# itself" path takes over. Three parts:
#   A. THE SERVER STANDS STILL: the server process is stopped for 10 s (SIGSTOP) and
#      continued. The page must close the socket itself about 5 s in, and be back in
#      its own seat by itself when the server runs again, with no tap.
#   B. THE LINK DIES: every packet to and from the game server is thrown away for a
#      while (12 s, then 35 s), as when a phone walks out of the Wi-Fi, and then passes
#      again. The page must be back in its own seat by itself.
#   C. NO FALSE ALARM: pages sit 10 minutes in each thing a page can be in: the lobby,
#      the countdown, a match, the winner's screen; seated, only watching, and THE BIG
#      SCREEN (?tv). The watchdog must never fire, and each page's own report says how
#      long its socket was ever quiet (5 000 ms would close it).
# It runs everything in a network of its own (unshare: a private loopback, no root, no
# sudo), so B can throw packets away with nft and touch nobody else, and so that every
# process it starts ends with it. Nothing opens a window; the browsers are muted.
#
#   tools/v2_build.sh none          (the page under build/web/v2/ must be this copy's)
#   ./venv/bin/python tools/v2_watchdog_check.py [--only A,B,C] [--minutes 10] [--dead 12,35]
#       [--port 8310] [--admin-port 8320] [--file-port 8325] [--debug-port 9610] [--out DIR]
#       [--web DIR]   the folder the page is served from (default build/web; an older
#                     build's folder shows the page with no watchdog: part B's "before")
#       [--bench DIR] the server from another copy of bench/
#       [--setups lobby,countdown]  C: only these of its four servers
#       [--cores 6]   the browsers share this many processor cores (they draw in software
#                     and would take them all; 0: no limit)
#   C uses 4 servers and 7 browsers (ports +0..+3, +0..+6) for about 20 minutes. On a PC
#   that does other work, run it in two halves (--setups lobby,countdown, then --setups
#   match,winner).
# Pictures: <out>/wd_*.png. Exit 1 on any FAIL.
# ==============================================================================
import argparse, base64, glob, json, os, shutil, signal, subprocess, sys, tempfile, threading, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
if "--in-ns" not in sys.argv:
    # A private network, process list and /proc (unshare). The real work is the same
    # script inside it; this outer one only waits. To stop a run early, send THIS process
    # SIGTERM (or Ctrl-C): it ends unshare, the inner script is told (SIGTERM), stops its
    # servers and browsers in order, and whatever were left ends with the private process
    # list. (unshare itself ignores SIGTERM while it waits, so it is killed, by its PID.)
    inner = subprocess.Popen(["unshare", "-r", "-n", "-p", "-f", "-m", "--mount-proc", "--kill-child=SIGTERM",
                              sys.executable, os.path.abspath(__file__), "--in-ns"] + sys.argv[1:])

    def stop(*_):
        if inner.poll() is None and inner.pid > 1:
            inner.kill()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    sys.exit(inner.wait() if inner.wait() >= 0 else 1)
subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
signal.signal(signal.SIGTERM, lambda *a: sys.exit(1))      # (so the finally blocks stop what was started)

import websocket
from v2_chaos import Host, Server, ROOT, PH_LOBBY, PH_COUNTDOWN, PH_ROUND_START, PH_PLAY, PH_ROUND_END, PH_MATCH_END, PHASES

ap = argparse.ArgumentParser()
ap.add_argument("--in-ns", action="store_true")
ap.add_argument("--only", default="A,B,C")
ap.add_argument("--minutes", type=float, default=10.0, help="C: this long in each phase")
ap.add_argument("--setups", default="lobby,countdown,match,winner", help="C: only these of its four servers")
ap.add_argument("--cores", type=int, default=6, help="the browsers share this many processor cores (0: all of them)")
ap.add_argument("--dead", default="12,35", help="B: the link is dead this many seconds, each in turn")
ap.add_argument("--port", type=int, default=8310)
ap.add_argument("--admin-port", type=int, default=8320)
ap.add_argument("--file-port", type=int, default=8325)
ap.add_argument("--debug-port", type=int, default=9610)
ap.add_argument("--web", default=os.path.join(ROOT, "build", "web"))
ap.add_argument("--bench", default="")
ap.add_argument("--out", default=os.path.join(ROOT, "bench_results", "watchdog_check"))
ap.add_argument("--extra", default="look=t1&res=0.5&nohowto", help="page options (a light page: software rendering is slow)")
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
FAILS = []
# A headless browser draws in software and takes every core it can get (7 of them for one
# page on a 24-core PC). All of this tool's browsers are kept on the last --cores cores.
CORES = sorted(os.sched_getaffinity(0))
PIN = ["taskset", "-c", ",".join(str(c) for c in CORES[-a.cores:])] if 0 < a.cores < len(CORES) else []
DOG = "[Net] nothing from the server"          # the watchdog's console line (net.gd _give_up)
PHONE_UA = "Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36"


def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what, flush=True)
    if not ok:
        FAILS.append(what)
    return ok


def wait(test, seconds, step=0.05):
    end = time.time() + seconds
    while time.time() < end:
        try:
            v = test()
        except Exception:
            v = None
        if v:
            return v
        time.sleep(step)
    try:
        return test()
    except Exception:
        return None


class Browser:
    """One headless Chromium with one page; a thread keeps its console lines."""

    def __init__(self, debug_port, tag, size=(1280, 720)):
        self.tag = tag
        self.size = size
        self.prof = tempfile.mkdtemp(prefix="tb-wd-", dir=a.out)      # (its profile, removed in close)
        self.proc = subprocess.Popen(PIN + ["chromium", "--headless=new", "--no-sandbox", "--no-first-run", "--no-default-browser-check",
                                      f"--remote-debugging-port={debug_port}", f"--user-data-dir={self.prof}", "--use-gl=angle",
                                      "--use-angle=swiftshader", "--enable-unsafe-swiftshader", f"--window-size={size[0]},{size[1]}",
                                      "--touch-events=enabled", "--mute-audio", "about:blank"],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tabs = wait(lambda: json.load(urllib.request.urlopen(f"http://127.0.0.1:{debug_port}/json", timeout=3)), 40, 0.5)
        self.ws = websocket.create_connection([t for t in tabs if t["type"] == "page"][0]["webSocketDebuggerUrl"],
                                              suppress_origin=True, timeout=None, enable_multithread=True)
        self.console = []            # (unix time, text)
        self.errors = []             # console.error and exceptions
        self.pending, self.n = {}, 0
        self.cv = threading.Condition()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        while True:
            try:
                m = json.loads(self.ws.recv())
            except Exception:
                return
            method = m.get("method")
            if method == "Runtime.consoleAPICalled":
                p = m["params"]
                text = " ".join(str(x.get("value", "")) for x in p["args"])
                self.console.append((p.get("timestamp", time.time() * 1000.0) / 1000.0, text))
                if p.get("type") == "error":
                    self.errors.append(text)
            elif method == "Runtime.exceptionThrown":
                self.errors.append(str(m["params"].get("exceptionDetails", {}).get("text", "exception")))
            elif "id" in m:
                with self.cv:
                    self.pending[m["id"]] = m.get("result", m)
                    self.cv.notify_all()

    def cmd(self, method, timeout=30.0, **params):
        with self.cv:
            self.n += 1
            i = self.n
        self.ws.send(json.dumps({"id": i, "method": method, "params": params}))
        end = time.time() + timeout
        with self.cv:
            while i not in self.pending:
                left = end - time.time()
                if left <= 0:
                    raise TimeoutError(method)
                self.cv.wait(left)
            return self.pending.pop(i)

    def open(self, url, phone):
        self.cmd("Runtime.enable")
        self.cmd("Page.enable")
        if phone:
            self.cmd("Emulation.setDeviceMetricsOverride", width=self.size[0], height=self.size[1], deviceScaleFactor=1, mobile=True)
            self.cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
            self.cmd("Emulation.setUserAgentOverride", userAgent=PHONE_UA)
        self.cmd("Page.navigate", url=url)

    def tap_gate(self):
        """The page's TAP TO PLAY (a phone's first tap)."""
        self.cmd("Runtime.evaluate", expression="(function(){var g=document.getElementById('fs-gate'); if(g){g.click(); g.remove();} return 'ok'})()")

    def shot(self, name):
        try:
            r = self.cmd("Page.captureScreenshot", format="png", timeout=20)
            with open(os.path.join(a.out, f"wd_{name}.png"), "wb") as f:
                f.write(base64.b64decode(r["data"]))
        except Exception as e:
            print(f"     (no picture {name}: {e})", flush=True)

    def lines(self, word, since=0):
        return [(t, text) for t, text in self.console[since:] if word in text]

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()          # by its PID (never pkill)
            try:
                self.proc.wait(8)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        shutil.rmtree(self.prof, ignore_errors=True)


class Files:
    """The page file server (python -m http.server), stopped by its PID."""

    def __init__(self, port, folder):
        self.proc = subprocess.Popen([sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1", "-d", folder],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        ok = wait(lambda: urllib.request.urlopen(f"http://127.0.0.1:{port}/v2/index.html", timeout=2).status == 200, 15, 0.2)
        if not ok:
            raise RuntimeError(f"no page at {folder}/v2/index.html: run tools/v2_build.sh none")

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def page_url(port, opts):
    return f"http://127.0.0.1:{a.file_port}/v2/index.html?server=ws://127.0.0.1:{port}&{opts}&{a.extra}"


def seat_named(host, name):
    return next((s for s in host.state()["seats"] if s["kind"] == 1 and s["name"] == name), None)


def nft(*args):
    subprocess.run(["nft"] + list(args), check=True)


def link_dead(port):
    """Every packet to and from the game server is thrown away (no answer, no refusal)."""
    nft("add", "rule", "inet", "wd", "c", "tcp", "dport", str(port), "drop")
    nft("add", "rule", "inet", "wd", "c", "tcp", "sport", str(port), "drop")


def link_back():
    nft("flush", "chain", "inet", "wd", "c")


def log_text(server):
    with open(server.log_path, errors="replace") as f:
        return f.read()


def used_inputs(text, seat):
    """The most inputs of that seat the server used in one of its 5 s report lines."""
    best = 0
    for line in text.splitlines():
        if "📊" in line and "| late " in line:
            for part in line.split("| late ")[1].split():
                if part.startswith(f"{seat}:"):
                    best = max(best, int(part.split(":")[1].split("/")[0]))
    return best


def seated_page(tag, port, admin_port, debug_port, sargs):
    """A server, and the phone page 'Kid' seated in a match that has started."""
    server = Server(port, admin_port, os.path.join(a.out, tag), sargs, a.bench or None)
    host = Host(admin_port)
    b = Browser(debug_port, tag)
    b.open(page_url(port, "name=Kid&join"), True)
    seated = wait(lambda: seat_named(host, "Kid") is not None, 90)
    b.tap_gate()
    if not check(bool(seated), f"{tag} (setup) the page joined as Kid"):
        return server, host, b, None
    host.cmd("start")
    wait(lambda: host.state()["phase"] == PH_PLAY, 15)
    time.sleep(6.0)              # (the page's first report has gone, 3 s after its socket opened)
    return server, host, b, seat_named(host, "Kid")


# ---------------------------------------------------------------- A: the server stands still
def part_a():
    server, host, b, before = None, None, None, None
    try:
        server, host, b, before = seated_page("A", a.port, a.admin_port, a.debug_port,
                                              ["--bots", "3", "--goal", "40", "--arena", "keep", "--season", "harvest", "--bot-level", "easy"])
        if before is None:
            return
        pid = server.proc.pid
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            mine = b"game_server.tscn" in f.read()
        assert pid > 1 and mine, "not the test server's PID"
        n0 = len(b.console)
        os.kill(pid, signal.SIGSTOP)
        t0 = time.time()
        time.sleep(7.0)
        b.shot("A_server_stopped_7s")
        time.sleep(max(0.0, t0 + 10.0 - time.time()))
        os.kill(pid, signal.SIGCONT)
        t1 = time.time()
        back = wait(lambda: (lambda k: k is not None and k["online"] and k["client"] != before["client"])(seat_named(host, "Kid")), 20)
        t_back = time.time() - t1
        now = seat_named(host, "Kid")
        dog = b.lines(DOG, n0)
        when = (dog[0][0] - t0) if dog else -1.0
        check(len(dog) == 1 and 4.5 <= when <= 6.0,
              f"A the server process stands still (SIGSTOP): the page closes its open socket itself {when:.1f} s in (5 s wanted; watchdog lines on its console: {len(dog)})")
        check(bool(back) and now is not None and now["i"] == before["i"] and now["points"] >= before["points"],
              f"A the server runs again after 10 s (SIGCONT): the page is back in its own seat by itself {t_back:.1f} s later, no tap "
              f"(seat {now['i'] if now else None}, it was {before['i']}; points {now['points'] if now else '-'}, before {before['points']}; a new socket: client {now['client'] if now else '-'}, it was {before['client']})")
        time.sleep(9.0)
        b.shot("A_back")
        text = log_text(server)
        said = [l for l in text.splitlines() if "closed a dead link by itself" in l]
        one_more = b.lines("ONE MORE STEP", n0)
        used = used_inputs(text.split("is back from")[-1], before["i"])
        check(used >= 100 and not one_more,
              f"A and it plays on: the server used {used} of the page's inputs in one 5 s report after it came back (300 is all of them); "
              f"ONE MORE STEP on the page: {len(one_more)} times (0 wanted)")
        check(len(said) == 1, f"A the night's log says so, from the page's own report: {said[0].strip()[:150] if said else 'NO [PHONE] line'}")
        check(not b.errors, f"A page errors (console.error, exceptions): {len(b.errors)}" + (f", the first: {b.errors[0][:160]}" if b.errors else ""))
    finally:
        for x in (b, server):
            if x is not None:
                (x.close if isinstance(x, Browser) else x.stop)()


# ---------------------------------------------------------------- B: the link dies
def part_b():
    server, host, b, before = None, None, None, None
    nft("add", "table", "inet", "wd")
    nft("add", "chain", "inet", "wd", "c", "{ type filter hook input priority 0 ; }")
    try:
        server, host, b, before = seated_page("B", a.port, a.admin_port, a.debug_port,
                                              ["--bots", "3", "--goal", "40", "--arena", "keep", "--season", "harvest", "--bot-level", "easy"])
        if before is None:
            return
        for dead in [float(x) for x in a.dead.split(",") if x.strip()]:
            before = seat_named(host, "Kid")
            n0 = len(b.console)
            link_dead(a.port)
            t0 = time.time()
            held = wait(lambda: not seat_named(host, "Kid")["online"], 8.0)
            t_held = time.time() - t0
            time.sleep(max(0.0, t0 + min(dead, 8.0) - time.time()))
            b.shot(f"B_dead_{int(dead)}s_at_8s")
            time.sleep(max(0.0, t0 + dead - time.time()))
            link_back()
            t1 = time.time()
            back = wait(lambda: (lambda k: k is not None and k["online"] and k["client"] != before["client"])(seat_named(host, "Kid")), 150)
            t_back = time.time() - t1
            now = seat_named(host, "Kid")
            dog = b.lines(DOG, n0)
            when = (dog[0][0] - t0) if dog else -1.0
            check(bool(held), f"B the link is dead for {dead:.0f} s (every packet thrown away): the server holds the seat {t_held:.1f} s in (its own 3 s rule)")
            check(len(dog) >= 1 and 4.5 <= when <= 6.5,
                  f"B dead {dead:.0f} s: the page closes its open socket itself {when:.1f} s in (5 s wanted; watchdog lines: {len(dog)})")
            check(bool(back) and now is not None and now["i"] == before["i"] and now["points"] >= before["points"],
                  f"B dead {dead:.0f} s: when the link is back the page is in its own seat again by itself {t_back:.1f} s later, no tap "
                  f"(seat {now['i'] if now else None}, it was {before['i']}; points {now['points'] if now else '-'}, before {before['points']})")
            fresh = b.lines("[Net] the new socket has not opened", n0)
            print(f"     (dead {dead:.0f} s: while the link was dead the page gave {len(fresh)} connecting sockets up for a fresh try, one every 4 s)", flush=True)
            time.sleep(8.0)
        b.shot("B_back")
        check(not b.errors, f"B page errors (console.error, exceptions): {len(b.errors)}" + (f", the first: {b.errors[0][:160]}" if b.errors else ""))
    finally:
        try:
            link_back()
        except Exception:
            pass
        for x in (b, server):
            if x is not None:
                (x.close if isinstance(x, Browser) else x.stop)()


# ---------------------------------------------------------------- C: no false alarm
def part_c():
    want_s = a.minutes * 60.0
    # [name, the server's options, the pages (name, options, a phone), the phase that must get its minutes, the host's job]
    setups = [
        ["lobby", ["--bots", "0"], [("Kid", "name=Kid&join", True), ("TV", "tv&name=TV", False)], PH_LOBBY, ""],
        ["countdown", ["--bots", "3", "--bot-level", "easy"], [("Kid", "name=Kid&join", True)], PH_COUNTDOWN, "loop"],
        ["match", ["--bots", "3", "--goal", "3"], [("Kid", "name=Kid&join", True), ("Watcher", "name=Watcher", True), ("TV", "tv&name=TV", False)], PH_PLAY, "start"],
        ["winner", ["--bots", "1", "--goal", "1", "--bot-level", "hard"], [("Kid", "name=Kid&join", True)], PH_MATCH_END, "start"],
    ]
    picked = [x.strip() for x in a.setups.split(",") if x.strip()]
    setups = [x for x in setups if x[0] in picked]
    servers, hosts, pages = [], [], []       # pages: (setup name, page name, Browser)
    try:
        dbg = a.debug_port
        for k, (name, sargs, plist, _, _) in enumerate(setups):
            servers.append(Server(a.port + k, a.admin_port + k, os.path.join(a.out, "C_" + name), sargs + ["--season", "harvest", "--arena", "mix"], a.bench or None))
            hosts.append(Host(a.admin_port + k))
            for pname, opts, phone in plist:
                b = Browser(dbg, f"C_{name}_{pname}", (640, 360))      # (a small picture: each browser draws in software)
                dbg += 1
                b.open(page_url(a.port + k, opts), phone)
                pages.append((name, pname, b))
        # every page is on its server: the seated ones by the seat, the others by the host page's list of watchers
        for k, (name, _, plist, _, _) in enumerate(setups):
            for pname, opts, _ in plist:
                if "join" in opts:
                    ok = wait(lambda: seat_named(hosts[k], pname) is not None, 120)
                else:
                    ok = wait(lambda: any(w["name"] == pname for w in hosts[k].state()["watching"]), 120)
                check(bool(ok), f"C (setup) {name}: the page {pname} is on its server")
        for _, _, b in pages:
            b.tap_gate()
        secs = [[0.0] * 6 for _ in setups]
        n0 = [len(b.console) for _, _, b in pages]
        t_start = last = time.time()
        next_line = t_start + 60.0
        while True:
            time.sleep(0.2)
            now = time.time()
            dt, last = now - last, now
            for k, (name, _, _, _, job) in enumerate(setups):
                try:
                    ph = hosts[k].state()["phase"]
                except Exception:
                    continue
                secs[k][ph] += dt
                if job and ph == PH_LOBBY:
                    hosts[k].cmd("start")    # the host starts every match (the page's own ?start does it only once)
                elif job == "loop" and ph >= PH_ROUND_START:
                    hosts[k].cmd("stop")     # as soon as the countdown is over, back to the lobby: 3 s of countdown in every 3.3
            done = all(secs[k][setups[k][3]] >= want_s for k in range(len(setups)))
            if now >= next_line or done:
                next_line = now + 60.0
                print(f"     {now - t_start:5.0f} s: " + "; ".join(f"{setups[k][0]}: {PHASES[setups[k][3]]} {secs[k][setups[k][3]]:.0f} s" for k in range(len(setups)))
                      + f"; watchdog lines so far: {sum(len(b.lines(DOG, n0[i])) for i, (_, _, b) in enumerate(pages))}", flush=True)
            if done or now - t_start > want_s * 4.0 + 300.0:
                break
        time.sleep(3.0)
        for i, (name, pname, b) in enumerate(pages):
            b.shot(f"C_{name}_{pname}")
        # the pages' own reports (a "client" line in each server's v2_server.jsonl, every 30 s)
        for k, (name, _, plist, target, _) in enumerate(setups):
            reps = {}
            for path in glob.glob(os.path.join(a.out, "C_" + name, "results", "*", "v2_server.jsonl")):
                with open(path, errors="replace") as f:
                    for line in f:
                        try:
                            d = json.loads(line)
                        except ValueError:
                            continue
                        if d.get("kind") == "client":
                            reps.setdefault(d.get("name"), []).append(d)
            spent = ", ".join(f"{PHASES[p]} {secs[k][p]:.0f} s" for p in range(6) if secs[k][p] >= 1.0)
            check(secs[k][target] >= want_s, f"C {name}: the server was in {PHASES[target]} for {secs[k][target]:.0f} s ({want_s:.0f} wanted); in all: {spent}")
            for pname, opts, _ in plist:
                i = next(j for j, (n, p, _) in enumerate(pages) if n == name and p == pname)
                b = pages[i][2]
                dog = b.lines(DOG, n0[i])
                rs = reps.get(pname, [])
                quiet = max([float(r.get("quiet_ms", 0)) for r in rs], default=-1.0)
                closes = max([int(r.get("watchdog", 0)) for r in rs], default=-1)
                again = max([int(r.get("reconnects", 0)) for r in rs], default=-1)
                what = "seated" if "join" in opts else ("THE BIG SCREEN" if "tv" in opts else "a watcher with no seat")
                check(not dog and closes == 0 and again == 0 and len(rs) >= 2 and 0.0 <= quiet < 5000.0,
                      f"C {name}, {pname} ({what}): the watchdog never fired (console lines {len(dog)}, its {len(rs)} reports say closes {closes}, "
                      f"reconnects {again}); the longest its open socket was ever quiet: {quiet:.0f} ms (5 000 closes it); page errors {len(b.errors)}")
    finally:
        for _, _, b in pages:
            b.close()
        for s in servers:
            s.stop()


files = Files(a.file_port, a.web)
try:
    only = [x.strip().upper() for x in a.only.split(",") if x.strip()]
    for name, fn in (("A", part_a), ("B", part_b), ("C", part_c)):
        if name in only:
            try:
                fn()
            except AssertionError as e:
                check(False, f"{name} could not run: {e}")
            except Exception as e:
                check(False, f"{name} broke: {type(e).__name__}: {e}")
finally:
    files.stop()
print("✅ v2_watchdog_check: every check passed" if not FAILS else f"❌ v2_watchdog_check: {len(FAILS)} FAIL", flush=True)
sys.exit(1 if FAILS else 0)
