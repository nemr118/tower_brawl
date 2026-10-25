# THE BOILER ROOM's hazards (theme "nightmare"): furnaces that blast fire, pressure
# pipes that bulge and vent steam, and the rest of the arena's moving parts. The sim
# makes one for an arena whose theme is "nightmare" (sim.gd hazards) and calls it each
# tick of play; the snapshot carries its state (write / read) for the page's look
# (client/boiler_view.gd); the bots ask it which way to step away (flee).
# (A stub until the arena is built: no hazards yet.)
extends RefCounted

const P = preload("res://sim/proto.gd")

func _init(_level) -> void:
	pass

# A new round.
func reset() -> void:
	pass

# One tick of play (not while the round's first moment holds everyone still).
func step(_sim) -> void:
	pass

# The state for the page (sim.gd write_snapshot calls it after the ghosts).
func write(buf: StreamPeerBuffer) -> void:
	buf.put_u8(0)

# The page's side of write (client/net.gd).
static func read(buf: StreamPeerBuffer) -> Dictionary:
	buf.get_u8()
	return {}

# Which way a bot should step to get out of a hazard about to go off: 1 right, -1 left, 0 none.
func flee(_sim, _f) -> int:
	return 0
