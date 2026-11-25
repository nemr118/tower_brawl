# The page's watchdog for a dead link (client/net.gd QUIET_MAX_MS), tried against a
# small server of this probe's own. The real server drops a silent socket after 3 s,
# so it cannot show what the watchdog does with a page that slept 8 s: this one never
# drops anyone, and sends a small packet 30 times a second (as the real one sends
# snapshots) or nothing at all, as the test asks.
#   godot --headless --path bench --script res://tools/watchdog_probe.gd [-- --port=8319]
# The rules it checks (about 90 s):
#   1. a live link: the watchdog never fires, the quiet time stays small
#   2. 4 s of nothing, then packets again (under the 5 s): it does not fire
#   3. nothing at all: it fires 5 s in, poll() says CLOSED, and a new socket opens fine
#   4. THE SLEEPER on a live link: the page does not poll for 8 s (a background tab, a
#      phone that wakes up) while packets keep coming: on its first poll it reads them
#      and does not fire
#   5. the sleeper on a link that died in its sleep: it does not fire on waking (the
#      sleep is no silence); it fires after 5 s awake with nothing
#   6. slow frames (a poll every 400 ms) on a live link: it does not fire
#   7. slow frames (a poll every 500 ms) on a dead link: it fires, later (each poll
#      counts 250 ms at most: about 10 s), never sooner
#   8. the new socket will not open (the server takes the connection and says nothing):
#      every 4 s it gives way to a fresh one, and when the server answers again the page
#      is connected within a second
#   9. a page's very FIRST socket is left alone, however long it takes (as before)
# (The real page against the real server: tools/v2_watchdog_check.py.)
# Prints a PASS/FAIL line per rule and exits 1 on a fail.
extends SceneTree

const Net = preload("res://client/net.gd")

var fails := 0
var checks := 0
var port := 8319
var listener := TCPServer.new()
var peers: Array = []          # the fake server's sockets (WebSocketPeer)
var hellos := 0                # texts the fake server got (a hello per socket)
var sending := true            # the fake server sends its 30 packets a second
var answering := true          # it answers new sockets (false: it takes the connection and says nothing)
var held: Array = []           # the connections it took while it did not answer
var next_send_ms := 0.0
var net

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
	if listener.listen(port, "127.0.0.1") != OK:
		printerr("❌ watchdog_probe: cannot listen on 127.0.0.1:%d (--port=N for another)" % port)
		quit(1)
		return
	net = Net.new()
	net.open("ws://127.0.0.1:%d" % port, "Probe", "probetoken")
	_run(1500.0, 16.0)          # the socket opens, the hello goes
	_check("(setup) the socket to the probe's own server is open", net.state == WebSocketPeer.STATE_OPEN and hellos == 1, "state %d, hellos %d" % [net.state, hellos])

	# 1. a live link
	net.take_quiet()
	_run(6000.0, 16.0)
	var q1: float = net.take_quiet()
	_check("1. a live link (30 packets a second) for 6 s: the watchdog does not fire, the longest quiet time is %.0f ms (5 000 closes)" % q1,
		net.watchdog_closes == 0 and net.state == WebSocketPeer.STATE_OPEN and q1 < 300.0, "closes %d" % net.watchdog_closes)

	# 2. 4 s of nothing, then packets again
	sending = false
	_run(4000.0, 16.0)
	sending = true
	_run(1000.0, 16.0)
	var q2: float = net.take_quiet()
	_check("2. 4 s of nothing, then packets again: it does not fire, the longest quiet time is %.2f s" % (q2 / 1000.0),
		net.watchdog_closes == 0 and net.state == WebSocketPeer.STATE_OPEN and q2 > 3700.0 and q2 < 4400.0, "closes %d, state %d" % [net.watchdog_closes, net.state])

	# 3. nothing at all: it fires at 5 s
	sending = false
	var t0 := Time.get_ticks_msec()
	var fired_ms := -1
	while Time.get_ticks_msec() - t0 < 7000:
		_step(true)
		if fired_ms < 0 and net.watchdog_closes == 1:
			fired_ms = Time.get_ticks_msec() - t0
		OS.delay_msec(8)
	_check("3. nothing at all on an open socket: the watchdog fires %.2f s in (5 s wanted) and poll() says CLOSED" % (fired_ms / 1000.0),
		fired_ms >= 4900 and fired_ms <= 5200 and net.watchdog_closes == 1 and net.state == WebSocketPeer.STATE_CLOSED, "closes %d, state %d" % [net.watchdog_closes, net.state])
	sending = true
	net.open("ws://127.0.0.1:%d" % port, "Probe", "probetoken")   # what the page does 0.3 s after a close
	_run(1500.0, 16.0)
	_check("3. a new socket opens after it, and says hello (%d hellos at the server)" % hellos,
		net.state == WebSocketPeer.STATE_OPEN and hellos == 2 and net.watchdog_closes == 1, "state %d" % net.state)

	# 4. the sleeper on a live link: no poll for 8 s while packets keep coming
	net.take_quiet()
	_run(8000.0, 0.0)           # (0: the page does not poll; the server goes on sending)
	_step(true)                 # the first poll after the sleep
	var q4: float = net.quiet_ms
	_run(1000.0, 16.0)
	_check("4. the page does not poll for 8 s on a live link (a background tab, a phone that wakes): its first poll reads what came, the quiet count is %.0f ms, the watchdog does not fire" % q4,
		net.watchdog_closes == 1 and net.state == WebSocketPeer.STATE_OPEN and q4 == 0.0, "closes %d, state %d" % [net.watchdog_closes, net.state])

	# 5. the sleeper on a link that died in its sleep
	_run(300.0, 16.0)
	sending = false
	_run(200.0, 16.0)           # (what was on its way has arrived and is read)
	_run(8000.0, 0.0)           # asleep, and nothing comes
	_step(true)                 # the first poll after the sleep
	var at_wake: int = net.watchdog_closes
	var q5: float = net.quiet_ms
	t0 = Time.get_ticks_msec()
	fired_ms = -1
	while Time.get_ticks_msec() - t0 < 7000:
		_step(true)
		if fired_ms < 0 and net.watchdog_closes == 2:
			fired_ms = Time.get_ticks_msec() - t0
		OS.delay_msec(8)
	_check("5. the link dies while the page sleeps 8 s: on waking the watchdog does not fire (the sleep counts as %.0f ms, not 8 000); it fires %.2f s after waking, with still nothing" % [q5, fired_ms / 1000.0],
		at_wake == 1 and q5 <= 700.0 and fired_ms >= 4200 and fired_ms <= 5200 and net.watchdog_closes == 2, "closes at waking %d, now %d" % [at_wake, net.watchdog_closes])
	sending = true
	net.open("ws://127.0.0.1:%d" % port, "Probe", "probetoken")
	_run(1500.0, 16.0)

	# 6. slow frames on a live link
	net.take_quiet()
	_run(8000.0, 400.0)
	var q6: float = net.take_quiet()
	_check("6. a poll every 400 ms (a page at 2.5 frames a second) on a live link for 8 s: it does not fire (the longest quiet time %.0f ms)" % q6,
		net.watchdog_closes == 2 and net.state == WebSocketPeer.STATE_OPEN and q6 < 300.0, "closes %d, state %d" % [net.watchdog_closes, net.state])

	# 7. slow frames on a dead link: later, never sooner
	sending = false
	t0 = Time.get_ticks_msec()
	fired_ms = -1
	var next_poll := 0
	while Time.get_ticks_msec() - t0 < 12500:
		var now := Time.get_ticks_msec() - t0
		_step(now >= next_poll)
		if now >= next_poll:
			next_poll = now + 500
		if fired_ms < 0 and net.watchdog_closes == 3:
			fired_ms = now
		OS.delay_msec(8)
	_check("7. a poll every 500 ms on a dead link: each poll counts 250 ms at most, so it fires later, %.1f s in (about 10), never sooner than 5" % (fired_ms / 1000.0),
		fired_ms >= 9000 and fired_ms <= 11500, "closes %d" % net.watchdog_closes)

	# 8. the new socket will not open
	_run(1000.0, 16.0)          # (rule 7's close has shown)
	answering = false
	sending = true
	var hellos0 := hellos
	net.open("ws://127.0.0.1:%d" % port, "Probe", "probetoken")
	_run(9500.0, 16.0)
	var tries: int = net.connect_retries
	var state8: int = net.state
	answering = true
	t0 = Time.get_ticks_msec()
	var open_ms := -1
	while Time.get_ticks_msec() - t0 < 3000:
		_step(true)
		if open_ms < 0 and net.state == WebSocketPeer.STATE_OPEN:
			open_ms = Time.get_ticks_msec() - t0
		OS.delay_msec(8)
	_check("8. a new socket that will not open for 9.5 s: it gave way to a fresh one %d times (2 wanted: at 4 s and 8 s); when the server answers again the page is connected %.2f s later and says one hello" % [tries, open_ms / 1000.0],
		tries == 2 and state8 == WebSocketPeer.STATE_CONNECTING and open_ms >= 0 and open_ms <= 1000 and hellos == hellos0 + 1, "state while waiting %d, hellos %d" % [state8, hellos - hellos0])

	# 9. a page's very first socket is left alone
	answering = false
	var first = Net.new()
	first.open("ws://127.0.0.1:%d" % port, "First", "firsttoken")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9500:
		_step(true)
		first.poll()
		OS.delay_msec(8)
	_check("9. a page's very first socket, not open after 9.5 s: left alone as before (fresh tries: %d, 0 wanted; it is still connecting)" % first.connect_retries,
		first.connect_retries == 0 and first.state == WebSocketPeer.STATE_CONNECTING and net.state == WebSocketPeer.STATE_OPEN and net.watchdog_closes == 3, "state %d" % first.state)

	if fails == 0:
		print("✅ watchdog_probe: %d of %d checks passed" % [checks, checks])
		quit(0)
	else:
		printerr("❌ watchdog_probe: %d of %d checks failed" % [fails, checks])
		quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	fails += 0 if ok else 1
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, "" if ok or detail == "" else ": " + detail])

# ms of real time: the fake server works all the while; the page's side polls every
# poll_ms (0: not at all, it sleeps).
func _run(ms: float, poll_ms: float) -> void:
	var t0 := Time.get_ticks_msec()
	var next_poll := 0.0
	while Time.get_ticks_msec() - t0 < ms:
		var now := float(Time.get_ticks_msec() - t0)
		var poll_now: bool = poll_ms > 0.0 and now >= next_poll
		if poll_now:
			next_poll = now + poll_ms
		_step(poll_now)
		OS.delay_msec(4)

# One turn: the fake server takes new sockets, reads what came (and throws it away),
# sends its packet when one is due; then the page's side polls, if it is awake.
func _step(page_polls: bool) -> void:
	while listener.is_connection_available():
		held.append(listener.take_connection())
	while answering and not held.is_empty():
		var ws := WebSocketPeer.new()
		ws.accept_stream(held.pop_front())
		peers.append(ws)
	var t := Time.get_ticks_usec() / 1000.0
	var send_now: bool = sending and t >= next_send_ms
	if send_now:
		next_send_ms = t + 1000.0 / 30.0
	for i in range(peers.size() - 1, -1, -1):
		var ws: WebSocketPeer = peers[i]
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			peers.remove_at(i)
			continue
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		while ws.get_available_packet_count() > 0:
			ws.get_packet()
			if ws.was_string_packet():
				hellos += 1
		if send_now:
			ws.put_packet(PackedByteArray([99, 0]))    # a kind net.gd does not know: it only counts as "something came"
	if page_polls:
		net.poll()
