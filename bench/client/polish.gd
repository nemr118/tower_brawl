# The look polish of 2026-10-25 (the user: "some elements need work and are too
# plain"). Every new piece of the look has its own switch here. Each one is a
# proposal until the user says yes: set its switch to false and the old look comes
# back, nothing else changes.
# A test knob for pictures: ?polish_off=hh_moon,hh_windows (or polish_off=all) on the
# page's address turns pieces off for that visit only.
extends RefCounted

# The user approved every piece on 2026-10-25 (the HAUNTED HOUSE first, then the castle
# arenas, the arrows and the light shafts, from their BEFORE/AFTER pictures).
const SWITCHES := {
	# THE HAUNTED HOUSE (client/theme_view.gd)
	"hh_windows": true,     # glowing windows with frames, sills and curtains; a ghost or a cat passes behind one now and then
	"hh_house": true,       # boards on the house's walls, shingles on its roof, boards across the tower window
	"hh_moon": true,        # a shaded moon with craters, clouds drifting over it, a witch on a broom crossing it
	"hh_mist": true,        # the floor mist as soft drifting puffs, not one flat band
	"hh_spiders": true,     # a spider on a thread under each cobweb, going up and down
	"hh_pumpkins": true,    # jack-o'-lanterns with ribs, a shaded base, a cut lid and a glow on the wall
	"hh_yard": true,        # a dead tree's branches and gravestones in the yard, far behind the play space
	# THE KEEP, THE BRIDGES (client/dress_view.gd, new art from tools/gen_dressing.gd; world.gd's hooks)
	"castle_backdrop": true,   # a new backdrop: brick arches, red banners with a gold emblem, ivy, a night sky with a moon and far towers
	"castle_depth": true,      # a soft shade deep inside big blocks: their edges read lit, their middles recede
	"castle_moss": true,       # moss tufts on some tops, ivy hanging under ceilings and overhangs
	"castle_ledges": true,     # iron brackets under planks that meet a wall, chains from floating planks to the block above
	"castle_sconces": true,    # iron wall sconces with glowing coals instead of the plain torch stick; a flame on LOW
	# every arena (world.gd's hook)
	"arrows2": true,           # new arrow art: a pointed steel head, an outlined shaft, fletching in the kind's colour
	"shaft_motes": true,       # NORMAL and HIGH: the light shafts a little stronger, with dust drifting in them
	# every arena (client/powers_view.gd, p4.13): ComfyUI's power-up pictures (assets/pu_icons.png) in the
	# orbs, the badges and your power-up card, on darker discs (the user said yes)
	"icons2": true,
	# the winner's screen (client/winner_view.gd, p4.13): a ComfyUI picture on each award card (assets/award_art.png)
	"award_art": true,
}

static var _off := {}
static var _read := false

# Is this piece on? Its switch, unless the page's address turns it off.
static func on(name: String) -> bool:
	if not _read:
		_read = true
		if OS.has_feature("web"):
			var q := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
			for p in q.split("&", false):
				if p.begins_with("polish_off="):
					for n in p.substr(11).uri_decode().split(",", false):
						_off[n] = true
	if _off.has("all") or _off.has(name):
		return false
	return bool(SWITCHES.get(name, false))
