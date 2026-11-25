# p4.18 the season the server is in: "" none, "halloween", "harvest", "christmas" (sim/proto.gd's
# seasons). game_client.gd sets it from the seats message; the drawing code asks it. In
# the Harvest season the candies are covered dishes, their tricks, the costume, the pet
# and some power-ups have new names and pictures; the rules stay the same.
extends RefCounted

static var now := ""
static var sleeps := -1      # p4.22: the nights left to Christmas Day by the server's date (24 on 1 December, 0 on the 25th; -1: another day)

static func harvest() -> bool:
	return now == "harvest"

static func christmas() -> bool:     # p4.22
	return now == "christmas"
