# ==============================================================================
# HISTORY_RING.GD (The Tape)
# ==============================================================================
# This is a tape of the last six seconds of the fight, as THIS screen drew it.
# arena.gd records one frame every physics tick (60 a second). When the server
# says somebody died, arena.gd stamps the newest frame with who killed whom.
# When the round ends, the tape records one more second (the fall, the banner)
# and then freezes. The v0.1.0 replay will play the frozen tape back.
#
# Phase 3c (v0.0.25): recording, stamping and freezing only. No playback yet.
#
# The 360 frame slots are made once and reused, so recording does not make
# new memory every tick. A frame slot looks like this:
#   {"seq": 812, "msec": 91234, "round": 3, "rot": 0.0, "flips": 1,
#    "present": 0b0011,                       # bit (pid - 1) set = fighter pid is on this frame
#    "fighters": {1: [x, y, aim_x, aim_y, flags], 2: [...], 3: [...], 4: [...]},
#    "n_proj": 2, "projectiles": [[weapon_id, x, y, rot, stuck, shooter], ...],
#    "powerup": [x, y, present]}
# The fighter arrays and the projectile arrays are PackedFloat32Array and are
# reused too. flags = the sync_pos bits (Global.FLAG_*) plus FLAG_BUBBLE and
# FLAG_DEAD, which live only on the tape.
# ==============================================================================
extends RefCounted

const FPS := 60                                 # physics ticks per second (the project default)
const BEFORE_S := 5.0                           # seconds kept before a kill
const TAIL_S := 1.0                             # seconds recorded after the closing kill, then freeze
const CAPACITY := int((BEFORE_S + TAIL_S) * FPS)   # 360 frames
const TAIL_FRAMES := int(TAIL_S * FPS)          # 60 frames
const MAX_STAMPS := 32                          # stamps kept; older ones fall off with their frames
const FLAG_BUBBLE := 64                         # inside the spawn bubble
const FLAG_DEAD := 128                          # dead or hidden on this frame

var frames: Array = []          # CAPACITY slots, reused
var head: int = 0               # the slot the next frame goes into
var count: int = 0              # slots holding a frame (up to CAPACITY)
var seq: int = 0                # frames recorded since clear(); the newest frame is seq - 1
var recording: bool = true
var frozen: bool = false
var round_num: int = 0
var stamps: Array = []          # [{seq, round, killer, victim, weapon, closing, fighters}]
var stamps_total: int = 0       # stamps since clear(), dropped ones included
var closing_seq: int = -1       # the frame of the kill that ended the round, -1 = none
var _tail_left: int = -1        # frames still to record after round_end, -1 = no freeze pending


func _init() -> void:
	frames.resize(CAPACITY)
	for i in range(CAPACITY):
		var f := {"seq": -1, "msec": 0, "round": 0, "rot": 0.0, "flips": 0, "present": 0,
			"fighters": {}, "n_proj": 0, "projectiles": [], "powerup": PackedFloat32Array([0.0, 0.0, 0.0])}
		for pid in range(1, 5):
			f["fighters"][pid] = PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0])
		frames[i] = f


func clear(new_round: int) -> void:
	# A new round: forget the tape (the slots stay allocated) and record again.
	head = 0
	count = 0
	seq = 0
	recording = true
	frozen = false
	round_num = new_round
	stamps.clear()
	stamps_total = 0
	closing_seq = -1
	_tail_left = -1


# The slot for the next frame. The caller fills it in, then calls commit().
func next_frame() -> Dictionary:
	return frames[head]


# A reused projectile array inside frame f, number i (0-based). Grows the list when needed.
func projectile_slot(f: Dictionary, i: int) -> PackedFloat32Array:
	var list: Array = f["projectiles"]
	while list.size() <= i:
		list.append(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	return list[i]


# Seal the frame in the head slot. Returns true when this frame froze the tape.
func commit(msec: int) -> bool:
	if not recording:
		return false
	var f: Dictionary = frames[head]
	f["seq"] = seq
	f["msec"] = msec
	f["round"] = round_num
	seq += 1
	head = (head + 1) % CAPACITY
	count = mini(count + 1, CAPACITY)
	_drop_old_stamps()
	if _tail_left > 0:
		_tail_left -= 1
		if _tail_left == 0:
			_freeze()
			return true
	return false


# The server said somebody died: stamp the newest frame. Returns the stamp (empty when frozen).
func stamp(killer: int, victim: int, weapon: String) -> Dictionary:
	if frozen or count == 0:
		return {}
	stamps_total += 1
	var s := {"seq": seq - 1, "round": round_num, "killer": killer, "victim": victim,
		"weapon": weapon, "closing": false, "fighters": _fighters_at(seq - 1)}
	stamps.append(s)
	while stamps.size() > MAX_STAMPS:
		stamps.pop_front()
	return s


# The round ended: the newest stamp is the closing kill. Record the tail, then freeze.
func close_round() -> void:
	if frozen or _tail_left >= 0:
		return
	if not stamps.is_empty() and int(stamps[-1]["round"]) == round_num:
		stamps[-1]["closing"] = true
		closing_seq = int(stamps[-1]["seq"])
	_tail_left = TAIL_FRAMES
	if count == 0:
		_freeze()   # nothing recorded (a round that ended before the first tick)


func _freeze() -> void:
	recording = false
	frozen = true
	_tail_left = -1


func oldest_seq() -> int:
	return seq - count


func newest_seq() -> int:
	return seq - 1


# The frame with this seq, or an empty dictionary when it is gone or not yet recorded.
func frame_at(s: int) -> Dictionary:
	if s < oldest_seq() or s > newest_seq():
		return {}
	return frames[s % CAPACITY]


# Frames on the tape up to and including the stamped frame, and frames after it.
func frames_before(s: int) -> int:
	return maxi(s - oldest_seq() + 1, 0)


func frames_after(s: int) -> int:
	return maxi(newest_seq() - s, 0)


func span_ms() -> int:
	if count < 2:
		return 0
	return int(frames[(head - 1 + CAPACITY) % CAPACITY]["msec"]) - int(frames[(head - count + CAPACITY) % CAPACITY]["msec"])


func fps() -> float:
	var ms := span_ms()
	if ms <= 0 or count < 2:
		return 0.0
	return (count - 1) * 1000.0 / ms


func last_stamp() -> Dictionary:
	return stamps[-1] if not stamps.is_empty() else {}


func _drop_old_stamps() -> void:
	var oldest := oldest_seq()
	while not stamps.is_empty() and int(stamps[0]["seq"]) < oldest:
		stamps.pop_front()


# Where every fighter on frame s stood: {pid: [x, y]}. A small new dictionary, made
# only when a kill is stamped.
func _fighters_at(s: int) -> Dictionary:
	var out := {}
	var f := frame_at(s)
	if f.is_empty():
		return out
	var present: int = f["present"]
	for pid in range(1, 5):
		if present & (1 << (pid - 1)):
			var a: PackedFloat32Array = f["fighters"][pid]
			out[pid] = [snappedf(a[0], 0.1), snappedf(a[1], 0.1)]
	return out


# One card with the tape's state: sent to the server as history_status and printed
# as the 📼 [Tape] line. The server keeps it in status.json as seats[].tape.
func status_card() -> Dictionary:
	var last := last_stamp()
	var card := {"type": "history_status", "schema": 1, "frames": count, "span_ms": span_ms(),
		"fps": snappedf(fps(), 0.1), "recording": recording, "frozen": frozen, "round": round_num,
		"stamps": stamps_total, "closing_seq": closing_seq, "last": null}
	if not last.is_empty():
		var s: int = last["seq"]
		card["last"] = {"seq": s, "round": last["round"], "killer": last["killer"],
			"victim": last["victim"], "weapon": last["weapon"], "closing": last["closing"],
			"before": frames_before(s), "after": frames_after(s), "fighters": last["fighters"]}
	return card


# The log line the harness reads. One line per stamp and one per freeze.
func status_line() -> String:
	var last := last_stamp()
	var s: int = int(last["seq"]) if not last.is_empty() else -1
	var weapon: String = str(last.get("weapon", "-")).replace(" ", "_") if not last.is_empty() else "-"
	return "📼 [Tape] round=%d frozen=%d closing=%d killer=%d victim=%d weapon=%s seq=%d before=%d after=%d span_ms=%d fps=%.1f stamps=%d frames=%d" % [
		round_num, 1 if frozen else 0, 1 if (not last.is_empty() and last["closing"]) else 0,
		int(last.get("killer", 0)), int(last.get("victim", 0)), weapon, s,
		frames_before(s) if s >= 0 else 0, frames_after(s) if s >= 0 else 0,
		span_ms(), fps(), stamps_total, count]
