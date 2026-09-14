# ==============================================================================
# The phone page of the 8-player benchmark. Joins bench_server.gd, draws the
# 8 bots' match it receives, and climbs the tier ladder by itself: T0..T5 at the
# screen's full resolution, again drawn at 1920 x 1080 and scaled up, then T3
# with CPU particles. Each step: 20 s, the first 3 s not counted. One bench card
# per step goes to the server (bench_results/<date>/cards.jsonl).
# Options (desktop: --key=value after --; web: ?key=value in the URL):
#   server=wss://host:8091  name=S25  auto  quit  seconds=20  tiers=0,1,2,3,4,5
#   res=native,1080  no-cpu  tier=3 (look only: no ladder)  view-res=1080  nopost
#   level=5 (the look of a limit-test level)  levels=10  level-seconds=5
# ==============================================================================
extends Node

const Net = preload("res://client/net.gd")
const World = preload("res://client/world.gd")
const TIER_NAMES := ["T0 plain", "T1 lights", "T2 effects", "T3 shaders", "T4 live 3D", "T5 stress", "T6 max", "T7 limit"]
const BOOST := 2.5      # particle amounts in the max tiers (T6, T7)

var opts := {}
var net
var world
var sub: SubViewport
var display := TextureRect.new()
var hud := CanvasLayer.new()
var title := Label.new()
var info := Label.new()
var start_btn := Button.new()
var overlay := Label.new()
var results := Label.new()
var segments: Array = []
var seg_i := -1
var seg_t := 0.0
var seg_len := 20.0
var warm := 3.0
var measuring := false
var frame_ms := PackedFloat32Array()
var last_usec := 0
var hitches := 0
var proc_sum := 0.0
var phys_sum := 0.0
var mon_n := 0
var draw_max := 0
var obj_max := 0
var arrows_sum := 0
var zones_sum := 0
var running := false
var built_key := ""
var device := {}
var device_name := ""
var run_id := ""
var result_lines: Array = []
var overlay_t := 0.0
var fps_frames := 0
var fps_t := 0.0
var fps_now := 0.0
var aim := 0
var ramp_level := 0
var ramp_t := 0.0
var ramp_levels: Array = []
var ramp_limit := 0
var ramp_info := {}
var levels_max := 10
var level_len := 5.0
var server_url := ""
var info_base := ""
var retry_t := 0.0
var lost_cards := 0

func _ready() -> void:
	opts = _read_opts()
	run_id = str(int(Time.get_unix_time_from_system()))
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.035))
	display.set_anchors_preset(Control.PRESET_FULL_RECT)
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(display)
	_build_ui()
	device = _device_info()
	device_name = str(opts.get("name", device.get("guess", "device")))
	seg_len = float(opts.get("seconds", 20))
	warm = minf(3.0, seg_len * 0.3)
	levels_max = int(opts.get("levels", 10))
	level_len = float(opts.get("level-seconds", 5))
	var url := str(opts.get("server", ""))
	if url == "":
		if OS.has_feature("web"):
			url = "wss://%s:8091" % str(JavaScriptBridge.eval("window.location.hostname", true))
		else:
			url = "wss://127.0.0.1:8091"
	net = Net.new()
	server_url = url
	net.open(url, device_name)
	segments = _plan()
	var total := 0.0
	for sg in segments:
		total += levels_max * level_len if sg["tier"] == 7 else seg_len
	info_base = "%s\n%s\nserver %s\n%d steps, about %.0f minutes. Lay the phone down and keep the screen on." % [
		device_name, str(device.get("gpu", "")), url, segments.size(), total / 60.0]
	if opts.has("tier"):
		var vt := int(opts["tier"])
		_build_world(str(opts.get("view-res", "1080")), opts.has("cpu"), BOOST if vt >= 6 else 1.0)
		world.set_tier(vt)
		if vt == 7:
			world.set_level(int(opts.get("level", 5)))
		if opts.has("nopost"):
			world.post.visible = false
			world.shake_on = false
		title.visible = false
		info.visible = false
		start_btn.visible = false
	elif opts.has("auto"):
		get_tree().create_timer(1.5).timeout.connect(_start)

func _read_opts() -> Dictionary:
	var o := {}
	var parts: Array = []
	for a in OS.get_cmdline_user_args():
		parts.append(a.trim_prefix("--"))
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
		for p in q.split("&", false):
			parts.append(p.uri_decode())
	for p in parts:
		if "=" in p:
			o[p.get_slice("=", 0)] = p.substr(p.find("=") + 1)
		elif p != "":
			o[p] = true
	return o

func _plan() -> Array:
	var tiers: Array = []
	for t in str(opts.get("tiers", "0,1,2,3,4,5,6,7")).split(",", false):
		tiers.append(int(t))
	var out: Array = []
	for res in str(opts.get("res", "native,1080")).split(",", false):
		for t in tiers:
			out.append({"tier": t, "res": res, "cpu": false, "boost": BOOST if t >= 6 else 1.0})
	if not opts.has("no-cpu"):
		out.append({"tier": 3, "res": "1080", "cpu": true, "boost": 1.0})
	return out

func _build_ui() -> void:
	hud.layer = 10
	add_child(hud)
	for l in [[title, 64, Vector2(80, 70)], [info, 30, Vector2(80, 190)], [overlay, 30, Vector2(24, 16)], [results, 26, Vector2(80, 150)]]:
		var lab: Label = l[0]
		lab.add_theme_font_size_override("font_size", l[1])
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		lab.add_theme_constant_override("outline_size", 10)
		lab.position = l[2]
		lab.size = Vector2(1760, 60)
		hud.add_child(lab)
	title.text = "TOWER BRAWL · 8-PLAYER BENCH"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.size = Vector2(1760, 300)
	results.visible = false
	start_btn.text = "START"
	start_btn.add_theme_font_size_override("font_size", 72)
	start_btn.position = Vector2(710, 620)
	start_btn.size = Vector2(500, 190)
	start_btn.pressed.connect(_start)
	hud.add_child(start_btn)
	_fit_hud()

func _fit_hud() -> void:
	var win := DisplayServer.window_get_size()
	if win.y > 16:
		hud.scale = Vector2.ONE * (win.y / 1080.0)

func _start() -> void:
	if running:
		return
	# No server means no cards saved and no fighters to draw: don't start.
	if net.state != WebSocketPeer.STATE_OPEN:
		if opts.has("auto"):
			get_tree().create_timer(1.0).timeout.connect(_start)
		return
	running = true
	start_btn.visible = false
	title.visible = false
	info.visible = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""(function(){try{document.documentElement.requestFullscreen().then(function(){
			try{screen.orientation.lock('landscape')}catch(e){}}).catch(function(){});}catch(e){}
			try{if(navigator.wakeLock){navigator.wakeLock.request('screen').catch(function(){});}}catch(e){}})()""", true)
	get_tree().create_timer(1.2).timeout.connect(_next_segment)

func _device_info() -> Dictionary:
	var d := {"os": OS.get_name(), "adapter": RenderingServer.get_video_adapter_name(),
		"cores_godot": OS.get_processor_count(), "refresh": DisplayServer.screen_get_refresh_rate()}
	if OS.has_feature("web"):
		var js := """JSON.stringify({ua: navigator.userAgent, dpr: window.devicePixelRatio, sw: screen.width,
			sh: screen.height, iw: window.innerWidth, ih: window.innerHeight, cores: navigator.hardwareConcurrency || 0,
			mem: navigator.deviceMemory || 0, gpu: (function(){try{var c=document.createElement('canvas');
			var g=c.getContext('webgl2');var e=g&&g.getExtension('WEBGL_debug_renderer_info');
			return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):(g?g.getParameter(g.RENDERER):'none')}catch(x){return 'err'}})()})"""
		var parsed = JSON.parse_string(str(JavaScriptBridge.eval(js, true)))
		if typeof(parsed) == TYPE_DICTIONARY:
			d.merge(parsed)
		var ua := str(d.get("ua", ""))
		var guess := "web"
		for key in ["iPad", "iPhone", "Pixel", "SM-", "Android", "Windows", "Linux", "Mac"]:
			if key in ua:
				guess = key.trim_suffix("-")
				break
		d["guess"] = guess
	else:
		d["gpu"] = d["adapter"]
		d["guess"] = OS.get_name()
	return d

func _build_world(res: String, cpu: bool, boost: float = 1.0) -> void:
	_fit_hud()
	var win := DisplayServer.window_get_size()
	var size := Vector2i(1920, 1080)
	if res == "native" and win.x > 16 and win.y > 16:
		var w := mini(win.x, int(win.y * 16.0 / 9.0))
		size = Vector2i(w, int(w * 9.0 / 16.0))
	var old := sub
	sub = SubViewport.new()
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(sub)
	world = World.new()
	sub.add_child(world)
	world.setup(size, cpu, boost)
	display.texture = sub.get_texture()
	if old != null:
		old.queue_free()

func _next_segment() -> void:
	seg_i += 1
	if seg_i >= segments.size():
		_finish_run()
		return
	var sg: Dictionary = segments[seg_i]
	var key := "%s:%s:%s" % [sg["res"], sg["cpu"], sg["boost"]]
	if key != built_key:
		_build_world(sg["res"], sg["cpu"], sg["boost"])
		built_key = key
	if not world.set_tier(sg["tier"]):
		_send_card(sg, {"skipped": "tier not available (no untracked 3D model)"})
		_next_segment()
		return
	seg_t = 0.0
	measuring = false
	if sg["tier"] == 7:
		ramp_level = 1
		ramp_t = 0.0
		ramp_levels = []
		ramp_limit = 0
		ramp_info = world.set_level(1)
	_reset_metrics()

func _reset_metrics() -> void:
	frame_ms.clear()
	hitches = 0
	proc_sum = 0.0
	phys_sum = 0.0
	mon_n = 0
	draw_max = 0
	obj_max = 0
	arrows_sum = 0
	zones_sum = 0

func _process(delta: float) -> void:
	net.poll()
	if not running and info.visible:
		_wait_for_server(delta)
	if world != null:
		var rt: float = net.render_tick()
		for e in net.take_events(rt):
			world.fx.on_event(e)
		world.render(net.sample(rt), delta)
	var now := Time.get_ticks_usec()
	fps_frames += 1
	fps_t += delta
	if fps_t >= 0.5:
		fps_now = fps_frames / fps_t
		fps_frames = 0
		fps_t = 0.0
	if running and seg_i >= 0 and seg_i < segments.size():
		seg_t += delta
		if segments[seg_i]["tier"] == 7:
			_ramp_step(now, delta)
		else:
			if seg_t >= warm:
				if not measuring:
					measuring = true
					net.take_window()
				else:
					_collect(now)
			if seg_t >= seg_len:
				_finish_segment()
				_next_segment()
	last_usec = now
	overlay_t += delta
	if overlay_t >= 0.5:
		overlay_t = 0.0
		var lv_txt := (" level %d" % ramp_level) if running and seg_i >= 0 and seg_i < segments.size() and segments[seg_i]["tier"] == 7 else ""
		var sg_txt := "look only" if not running else ("%s · %s%s · %d/%d · %.0f s" % [TIER_NAMES[segments[seg_i]["tier"]], segments[seg_i]["res"],
			" cpu" if segments[seg_i]["cpu"] else "", seg_i + 1, segments.size(), seg_len - seg_t] if seg_i >= 0 and seg_i < segments.size() else "")
		overlay.text = "%s%s   %.0f fps   rtt %d ms%s" % [sg_txt, lv_txt, fps_now, net.last_rtt,
			"" if net.state == WebSocketPeer.STATE_OPEN else "   NO SERVER: cards not saved"]
		overlay.visible = not results.visible

func _physics_process(_dt: float) -> void:
	aim = (aim + 7) % 3600
	net.send_input(int(Time.get_ticks_msec() / 300) % 256, aim)

func _collect(now: int) -> void:
	if last_usec > 0:
		var ft := (now - last_usec) / 1000.0
		frame_ms.append(ft)
		if ft > 50.0:
			hitches += 1
	proc_sum += Performance.get_monitor(Performance.TIME_PROCESS)
	phys_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	mon_n += 1
	draw_max = maxi(draw_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	obj_max = maxi(obj_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	arrows_sum += world.arrows.size()
	zones_sum += world.zones.size()

# The limit test: each level settles 1.5 s, is measured for the rest of its time,
# and the dial goes up. The first level that misses 60 fps ends it.
func _ramp_step(now: int, delta: float) -> void:
	ramp_t += delta
	var settle := minf(1.5, level_len * 0.3)
	if ramp_t >= settle:
		if not measuring:
			measuring = true
			_reset_metrics()
			if ramp_level == 1:
				net.take_window()
		else:
			_collect(now)
	if ramp_t < level_len:
		return
	var s := frame_ms.duplicate()
	s.sort()
	var secs := maxf(0.001, ramp_t - settle)
	var n := maxi(1, mon_n)
	var lv := {"level": ramp_level, "fps": frame_ms.size() / secs, "ft_p50": _pct(s, 0.5), "ft_p95": _pct(s, 0.95),
		"ft_p99": _pct(s, 0.99), "ft_max": _pct(s, 1.0), "hitches_50ms": hitches, "proc_ms": proc_sum * 1000.0 / n,
		"draw_calls_max": draw_max, "particles": ramp_info.get("particles", 0.0), "fog_layers": ramp_info.get("fog_layers", 0),
		"fighters": world.fighter_count, "lights": world.light_count(), "emitters": world.fx.count_active()}
	# At 60 Hz frame times wobble around 16.7 ms, so a p95 <= 16.7 rule fails a steady 60.
	lv["pass"] = lv["fps"] >= 58.0 and lv["ft_p99"] <= 25.0 and hitches == 0
	ramp_levels.append(lv)
	print("📱 [Bench] %s  T7 level %d: %.0f fps p95 %.1f p99 %.1f ms, %d fighters, %d fog layers, %d lights, particles x%.2f  %s" % [
		device_name, ramp_level, lv["fps"], lv["ft_p95"], lv["ft_p99"], lv["fighters"], lv["fog_layers"], lv["lights"], lv["particles"], "PASS" if lv["pass"] else "fail"])
	if lv["pass"]:
		ramp_limit = ramp_level
	if not lv["pass"] or ramp_level >= levels_max:
		var sg: Dictionary = segments[seg_i]
		var d := {"levels": ramp_levels, "limit_level": ramp_limit, "render_size": [sub.size.x, sub.size.y]}
		d.merge(net.take_window())
		_send_card(sg, d)
		_next_segment()
		return
	ramp_level += 1
	ramp_info = world.set_level(ramp_level)
	ramp_t = 0.0
	measuring = false

static func _pct(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return -1.0
	return sorted[mini(sorted.size() - 1, int(sorted.size() * p))]

func _finish_segment() -> void:
	var sg: Dictionary = segments[seg_i]
	var s := frame_ms.duplicate()
	s.sort()
	var secs := maxf(0.001, seg_t - warm)
	var n := maxi(1, mon_n)
	var d := {
		"frames": frame_ms.size(), "fps": frame_ms.size() / secs,
		"ft_p50": _pct(s, 0.5), "ft_p95": _pct(s, 0.95), "ft_p99": _pct(s, 0.99), "ft_max": _pct(s, 1.0),
		"hitches_50ms": hitches, "proc_ms": proc_sum * 1000.0 / n, "phys_ms": phys_sum * 1000.0 / n,
		"draw_calls_max": draw_max, "objects_max": obj_max,
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"vid_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"lights_now": world.light_count(), "emitters_now": world.fx.count_active(),
		"arrows_mean": float(arrows_sum) / n, "zones_mean": float(zones_sum) / n, "fighters": world.fighter_count,
		"render_size": [sub.size.x, sub.size.y], "window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
	}
	d.merge(net.take_window())
	d["pass"] = d["fps"] >= 58.0 and d["ft_p99"] <= 25.0 and hitches == 0
	_send_card(sg, d)

func _send_card(sg: Dictionary, d: Dictionary) -> void:
	var card := {"kind": "bench_card", "run": run_id, "name": device_name, "tier": TIER_NAMES[sg["tier"]],
		"tier_i": sg["tier"], "res": sg["res"], "cpu_particles": sg["cpu"], "seconds": seg_len, "device": device}
	card.merge(d)
	if not net.send_card(card):
		lost_cards += 1
	var line := ""
	if card.has("levels"):
		line = "%-12s %-6s      limit test: 60 fps held up to level %d of %d" % [card["tier"], sg["res"], card["limit_level"], levels_max]
	elif card.has("skipped"):
		line = "%-12s %-6s%s  skipped: %s" % [card["tier"], sg["res"], " cpu" if sg["cpu"] else "    ", card["skipped"]]
	else:
		line = "%-12s %-6s%s  %5.0f fps  p95 %5.1f  p99 %5.1f  max %6.1f ms  hitch %d  proc %4.1f ms  %s" % [
			card["tier"], sg["res"], " cpu" if sg["cpu"] else "    ", card["fps"], card["ft_p95"], card["ft_p99"],
			card["ft_max"], card["hitches_50ms"], card["proc_ms"], "PASS" if card["pass"] else "fail"]
	result_lines.append(line)
	print("📱 [Bench] %s  %s" % [device_name, line])

# Before START: show whether the bench server is there, and keep trying.
func _wait_for_server(delta: float) -> void:
	var ok: bool = net.state == WebSocketPeer.STATE_OPEN
	if not ok and net.state == WebSocketPeer.STATE_CLOSED:
		retry_t += delta
		if retry_t >= 2.0:
			retry_t = 0.0
			net.open(server_url, device_name)
	start_btn.disabled = not ok
	if ok:
		info.text = info_base + "\n\nServer connected. Tap START."
		info.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	else:
		info.text = info_base + "\n\nWAITING FOR THE BENCH SERVER. Start it on the PC. This page keeps trying.\n(If it never connects, open the server address once and accept the certificate.)"
		info.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))

func _finish_run() -> void:
	running = false
	if not net.send_card({"kind": "bench_card", "run": run_id, "name": device_name, "tier": "done", "device": device}):
		lost_cards += 1
	var saved := "the cards are on the server. You can close this page."
	if lost_cards > 0:
		saved = "%d cards NOT SAVED (the server was not connected). Take a photo of this screen." % lost_cards
	results.text = "DONE · %s · %s\n\n%s" % [device_name, saved, "\n".join(result_lines)]
	results.visible = true
	overlay.visible = false
	if world != null:
		world.set_tier(0)
	print("📱 [Bench] %s done, %d steps" % [device_name, result_lines.size()])
	if opts.has("quit"):
		get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit())
