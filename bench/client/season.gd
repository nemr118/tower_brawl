# p4.18 the season the server is in: "" none, "halloween", "harvest" (sim/proto.gd's
# seasons). game_client.gd sets it from the seats message; the drawing code asks it. In
# the Harvest season the candies are covered dishes, their tricks, the costume, the pet
# and some power-ups have new names and pictures; the rules stay the same.
extends RefCounted

static var now := ""

static func harvest() -> bool:
	return now == "harvest"
