# Your own fighter, at once (P2, the feel). A copy of the simulation (sim.gd,
# the same rules the server runs, with `predicting` on) runs your fighter tick
# by tick from your buttons, so the page draws you on the tick you pressed, not
# a round trip later. Each T_OWN (proto.gd) brings the server's whole state of
# your fighter for its tick: the copy takes it and runs your inputs since that
# tick again (reconciliation). A small correction fades out (CORRECT_S); a big
# one (a new round, a death far away) jumps. Your jumps, landings, dodges, ledge
# grabs and shots give their events at once (PREDICTED; the page drops the
# server's copies of those). Your arrows shot since the server's tick fly in the
# copy too. Used by client/game_client.gd and tools/play_probe.gd --predict.
extends RefCounted

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const KEEP := 240                 # inputs and positions kept: 4 s
const SNAP_PX := 120.0            # a correction this big jumps instead of fading
const CORRECT_S := 0.06           # a small correction fades with this time constant
# your events the prediction gives at once; the server's copies are dropped
# (a stomp's jump, E_JUMP with b = 1, is the server's: the copy has nobody to stomp)
const PREDICTED := [P.E_JUMP, P.E_LAND, P.E_DODGE, P.E_WALLJUMP, P.E_LEDGE, P.E_SHOOT, P.E_DRYFIRE]

var sim
var me = null                     # your Fighter in the copy; null: no prediction (no fighter, or the brain plays it)
var seat := -1
var tick := 0                     # the tick `me` is at
var shown_tick := 0               # the newest tick whose events went to the page
var inputs := {}                  # tick -> [buttons, aim]
var last_input := [0, 0]
var placed := {}                  # tick -> Vector2i: where the prediction had you on that tick
var moves_from := 0               # the first tick the fighters move after ROUND START (0: not ahead)
var offset := Vector2.ZERO        # the correction still fading, px
var server_tick := 0              # the newest T_OWN's tick
var out_events: Array = []
# the numbers (tools/play_probe.gd --predict reads them)
var errors := PackedFloat32Array()   # each T_OWN: how far the prediction for its tick was off, px
var jumps := 0                    # corrections over SNAP_PX
var replayed := 0                 # ticks run again in all

func _init() -> void:
	sim = SimScript.new(0, 24, 7)
	sim.respawn = false
	sim.power_arrows = false      # the server picks a power arrow's kind; the copy flies a plain one
	sim.predicting = true

# One tick the client runs (net.ticks_now), with its buttons. The copy steps
# your fighter to it; its events go to the page once.
func on_tick(t: int, buttons: int, aim: int) -> void:
	inputs[t] = [buttons, aim]
	if inputs.size() > KEEP + 30 or placed.size() > KEEP + 30:
		for d in [inputs, placed]:
			for k in d.keys():
				if k < t - KEEP:
					d.erase(k)
	if me == null:
		tick = t
		return
	while tick < t:
		tick += 1
		_run(tick, true)

# The clock jumped (the first sync, a tab that slept): the copy waits at the new
# tick for the next T_OWN.
func jump_to(t: int) -> void:
	tick = t
	shown_tick = maxi(shown_tick, t)
	offset = Vector2.ZERO

# A T_OWN from net.gd (take_owns): the server's state of your fighter on its tick.
func reconcile(o: Dictionary) -> void:
	var s: int = o["tick"]
	if s < server_tick:
		return
	server_tick = s
	sim.set_arena(int(o.get("arena", sim.level.id)))   # G5: the copy runs on the round's arena
	moves_from = int(o["moves_from"])
	var flags: int = o["flags"]
	if (flags & P.OWN_FIGHTER) == 0 or (flags & P.OWN_BRAIN) != 0:
		me = null
		sim.fighters.clear()
		sim.arrows.clear()
		return
	var fresh: bool = me == null
	var before := drawn_pos()
	if fresh:
		me = SimScript.Fighter.new()
		me.id = seat
		me.bot = false
		sim.fighters = [me]
	var buf := StreamPeerBuffer.new()
	buf.data_array = o["pkt"]
	buf.seek(int(o["at"]))
	sim.read_fighter_state(buf, me)
	if not fresh and placed.has(s) and moves_from == 0:   # (a new round's first T_OWN is no correction)
		var at: Vector2i = placed[s]
		errors.append(Vector2(SimScript.wrap_d(at.x, me.x, 1920.0), SimScript.wrap_d(at.y, me.y, 1080.0)).length())
	placed[s] = Vector2i(me.x, me.y)
	# your arrows shot after tick s come back when the inputs run again; the earlier ones are the server's
	sim.arrows.clear()
	var target := maxi(tick, s)
	tick = s
	sim.tick = s
	while tick < target:
		tick += 1
		_run(tick, false)
		replayed += 1
	if fresh:
		offset = Vector2.ZERO
		shown_tick = maxi(shown_tick, tick)
		return
	var after := Vector2(me.x, me.y)
	var d := Vector2(SimScript.wrap_d(after.x, before.x, 1920.0), SimScript.wrap_d(after.y, before.y, 1080.0))
	if d.length() > SNAP_PX:
		jumps += 1
		offset = Vector2.ZERO
	else:
		offset = d

func _run(t: int, live: bool) -> void:
	sim.frozen = t < moves_from
	var inp: Array = inputs.get(t, last_input)
	last_input = inp
	sim.apply_input(me, inp[0], inp[1])
	sim.step()
	var evs: Array = sim.take_events()
	placed[t] = Vector2i(me.x, me.y)
	if live and t > shown_tick:
		shown_tick = t
		for e in evs:
			if PREDICTED.has(e[0]) and e[3] == seat:
				out_events.append(e)

func take_events() -> Array:
	var e := out_events
	out_events = []
	return e

# Once a frame: the correction fades.
func fade(delta: float) -> void:
	offset *= exp(-delta / CORRECT_S)
	if offset.length() < 0.2:
		offset = Vector2.ZERO

# Where the page draws you (top-left of the body box), with the fading correction.
func drawn_pos() -> Vector2:
	if me == null:
		return Vector2.ZERO
	return Vector2(fposmod(me.x + offset.x, 1920.0), fposmod(me.y + offset.y, 1080.0))

# Your fighter for the page, in a snapshot fighter's shape (net.gd). From the
# server's newest record (rec): points, and the burning, poisoned and smoke
# flags (the copy has no fire, poison or smoke).
func fighter_dict(rec: Dictionary) -> Dictionary:
	if me == null:
		return {}
	var pos := drawn_pos()
	var flags: int = (sim.fighter_flags(me) & ~(8 | 16 | 128)) | (int(rec.get("flags", 0)) & (8 | 16 | 128))
	var f2: int = (int(rec.get("flags2", 0)) & ~P.F2_AIMING) | (P.F2_AIMING if me.aiming else 0)
	return {"id": seat, "state": me.state, "x": pos.x, "y": pos.y,
		"vx": clampi(roundi(me.vx), -127, 127), "vy": clampi(roundi(me.vy), -127, 127),
		"flags": flags, "aim": me.aim, "arrows": me.arrows, "st": mini(me.state_t, 255),
		"points": int(rec.get("points", 0)), "flags2": f2}
