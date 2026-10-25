# The arrows in the present (P2, the feel). The page draws every arrow in the
# air where it is on your own predicted tick, not 50 ms in the past: the newest
# snapshot's arrows (their exact place, speed and age, proto.gd) flown on with
# the sim's own arrow code (sim.fly_arrows). The fighters stand in the copy as
# stoppers: an arrow that reaches one waits there for the server's word (a hit,
# a catch, or on it flies). So the arrow you dodge is where the server will have
# it on the tick your dodge lands ([[sim-server-design]] section 3). Your own
# shots since the newest snapshot come from the prediction (client/predict.gd).
# Someone else's new arrow slides out of their bow (SLIDE_S), because they are
# drawn in the past. The others move on at their snapshot speed while the arrows
# fly (input_probe rule 30: 95.7% of arrows exact after 6 ticks; standing still
# 93.8%, left out 96.6% but an arrow flies through the one it hit).
# Used by client/game_client.gd and tools/play_probe.gd.
extends RefCounted

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const MAX_AHEAD := 20          # an arrow is never flown more than this many ticks on
const SLIDE_S := 0.04          # a new arrow's slide from its bow fades with this time constant
const SLIDE_AGE := 10          # only an arrow younger than this (ticks) when first seen slides
const OWN_ID := 70000          # your predicted arrows' ids on the page: OWN_ID + the tick shot (mod 30000)

var sim
var base_tick := -1            # the snapshot the flown arrows come from
var at_tick := 0               # the tick they are flown to
var me_stop                    # your stopper (a Fighter: your predicted place)
var stuck := {}                # the snapshot's stuck arrows, id -> dict, drawn as they are
var owners := {}               # id -> the seat that shot it
var offsets := {}              # id -> Vector2: the slide still to go
var seen := {}                 # ids drawn last frame
var flown := 0                 # arrow ticks flown in all (the probes' cost line)
var stop_v: Array = []         # the other stoppers' speed (px a tick, from the snapshot)
var me_in := false             # you are the first stopper (set at the last rebuild)

func _init() -> void:
	sim = SimScript.new(0, 64, 7)
	sim.respawn = false
	sim.power_arrows = false
	sim.predicting = true
	me_stop = SimScript.Fighter.new()
	me_stop.bot = false

# The arrows to draw on tick `tick` (your predicted tick), from the newest
# snapshot `snap`: {id: {kind, state, x, y, ang}}. me: your predicted Fighter
# (client/predict.gd) or null. shown: the fighters as the page draws them (for
# the bows new arrows slide from). own_arrows: your arrows in the prediction.
func arrows_at(snap: Dictionary, tick: int, me, my_seat: int, shown: Array, own_arrows: Array, delta: float) -> Dictionary:
	if snap.is_empty():
		return {}
	sim.set_arena(int(snap.get("arena", sim.level.id)))   # G5: the arrows fly in the round's arena
	var s: int = snap["tick"]
	if s != base_tick:
		_rebuild(snap, me, my_seat)
	if me_in and me != null:
		me_stop.x = me.x
		me_stop.y = me.y
		me_stop.state = me.state
	var k := clampi(tick - at_tick, 0, MAX_AHEAD - (at_tick - base_tick))
	for i in k:
		# the others move on at their snapshot speed (a guess: the server knows); you stay where predicted
		for j in stop_v.size():
			var o = sim.fighters[j + (1 if me_in else 0)]
			o.x = posmod(o.x + stop_v[j].x, 1920)
			o.y = posmod(o.y + stop_v[j].y, 1080)
		sim.fly_arrows(1)
		at_tick += 1
		flown += sim.arrows.size()
	if k > 0:
		sim.take_events()
		sim.zones.clear()
	var out := {}
	var ages := {}
	for a in sim.arrows:
		out[a.id] = {"kind": a.kind, "state": a.state, "x": a.x, "y": a.y, "ang": a.ang, "owner": a.owner, "big": a.big}
		ages[a.id] = a.t
	for id in stuck:
		out[id] = stuck[id]
	_ride_bodies(out, snap, shown)
	for a in own_arrows:   # shot after the snapshot's tick: not in it yet
		var shot_at: int = tick - a.t
		if shot_at > s:
			out[OWN_ID + posmod(shot_at, 30000)] = {"kind": a.kind, "state": a.state, "x": a.x, "y": a.y, "ang": a.ang, "big": a.big}
	_slide(out, ages, shown, my_seat, delta)
	return out

func _rebuild(snap: Dictionary, me, my_seat: int) -> void:
	base_tick = snap["tick"]
	at_tick = base_tick
	sim.arrows.clear()
	sim.zones.clear()
	stuck.clear()
	owners.clear()
	var al: Dictionary = snap["arrows"]
	for id in al:
		var d: Dictionary = al[id]
		if int(d["state"]) == P.S_STUCK or not d.has("vx"):
			stuck[id] = d
			continue
		var a := SimScript.Arrow.new()
		a.id = id
		a.kind = d["kind"]
		a.state = d["state"]
		a.x = d["x"]
		a.y = d["y"]
		a.vx = d["vx"]
		a.vy = d["vy"]
		a.ang = d["ang"]
		a.t = d["age"]
		a.owner = d["owner"]
		a.big = d.get("big", false)
		owners[id] = a.owner
		sim.arrows.append(a)
	# the stoppers: you where the prediction has you, the others where the snapshot has them
	var stops: Array = []
	stop_v.clear()
	me_in = me != null
	if me_in:
		me_stop.id = my_seat
		me_stop.x = me.x
		me_stop.y = me.y
		me_stop.state = me.state
		stops.append(me_stop)
	for f in snap["fighters"]:
		if int(f["id"]) == my_seat and me != null:
			continue
		var o := SimScript.Fighter.new()
		o.id = f["id"]
		o.x = int(f["x"])
		o.y = int(f["y"])
		o.state = f["state"]
		stops.append(o)
		stop_v.append(Vector2i(int(f["vx"]), int(f["vy"])))
	sim.fighters = stops

# p4.10: an arrow in a body rides on that body as the page draws it (the snapshot's
# fighters are newer than the ones drawn): the dead fighter nearest the arrow in the
# snapshot is its body, and the arrow keeps its place on it.
func _ride_bodies(out: Dictionary, snap: Dictionary, shown: Array) -> void:
	for id in out.keys():
		var d: Dictionary = out[id]
		if int(d["state"]) != P.S_BODY:
			continue
		var best = null
		var bd := 90.0
		for fs in snap["fighters"]:
			if int(fs["state"]) != P.F_DEAD:
				continue
			var dd := Vector2(SimScript.wrap_d(fs["x"] + 18.0, d["x"], 1920.0), SimScript.wrap_d(fs["y"] + 31.0, d["y"], 1080.0)).length()
			if dd < bd:
				bd = dd
				best = fs
		if best == null:
			continue
		for fd in shown:
			if int(fd["id"]) == int(best["id"]):
				var nd: Dictionary = d.duplicate()
				nd["x"] = fposmod(fd["x"] + SimScript.wrap_d(best["x"], d["x"], 1920.0), 1920.0)
				nd["y"] = fposmod(fd["y"] + SimScript.wrap_d(best["y"], d["y"], 1080.0), 1080.0)
				out[id] = nd
				break

# Someone else's arrow seen for the first time, still young (ages: id -> ticks):
# it starts at its shooter's bow as the page draws them, and slides to where it is.
func _slide(out: Dictionary, ages: Dictionary, shown: Array, my_seat: int, delta: float) -> void:
	var k := exp(-delta / SLIDE_S)
	for id in offsets.keys():
		if not out.has(id) or int(out[id]["state"]) == P.S_STUCK:
			offsets.erase(id)
			continue
		offsets[id] *= k
		if offsets[id].length() < 0.5:
			offsets.erase(id)
	for id in out:
		if seen.has(id) or not ages.has(id):
			continue
		var owner: int = owners.get(id, -1)
		if owner < 0 or owner == my_seat or ages[id] >= SLIDE_AGE:
			continue
		for f in shown:
			if int(f["id"]) == owner:
				var a: Dictionary = out[id]
				offsets[id] = Vector2(SimScript.wrap_d(a["x"], f["x"] + 18.0, 1920.0), SimScript.wrap_d(a["y"], f["y"] + 28.0, 1080.0))
				break
	seen.clear()
	for id in out:
		seen[id] = true
		if offsets.has(id):
			var o: Vector2 = offsets[id]
			var d: Dictionary = out[id].duplicate()   # never the snapshot's own dictionary
			d["x"] = fposmod(d["x"] + o.x, 1920.0)
			d["y"] = fposmod(d["y"] + o.y, 1080.0)
			out[id] = d
