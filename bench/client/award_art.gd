# p4.13 a picture for each award (made with ComfyUI, Z-Image Turbo, cut off its background),
# drawn on the winner's award cards (client/winner_view.gd; polish "award_art"). ORDER is
# the sheet's order: assets/award_art.png, PER_ROW pictures a row, CELL px each.
extends RefCounted

const SHEET := preload("res://assets/award_art.png")
const CELL := 80
const PER_ROW := 8
const ORDER := ["SHARPSHOOTER", "STOMP CHAMP", "BOOM BOOM", "CAT WHISPERER", "CATCH OF THE DAY", "TREASURE HUNTER",
	"PARTY ANIMAL", "PIN MASTER", "WALL DECORATION", "LIGHTNING ROD", "EXTRA CRISPY", "STINKY", "PANCAKE", "PINCUSHION",
	"CAT FOOD", "OOPS!", "BUTTERFINGERS", "TRIGGER HAPPY", "PEACEMAKER", "BOUNCY CASTLE", "NINJA ROLL", "SPEED DEMON",
	"COUCH POTATO", "THE FLOOR IS LAVA", "FREQUENT FLYER", "SURVIVOR", "NAP TIME", "SPOOKY", "FRIENDLY GHOST",
	"NOW YOU SEE ME", "ARROW COLLECTOR", "ROUND WINNER", "GOOD KITTY", "TRICKED!", "SLASHER", "SWEET TOOTH",
	"SCARY MOVIE STAR", "GHOST BUSTER", "GOOD SPORT", "BEST WIGGLE", "MAIN CHARACTER", "WILL WIN NEXT TIME",
	"FASHION ICON", "CERTIFIED SILLY", "FAN FAVORITE", "NEVER GAVE UP"]

# The award's picture in r; false when it has none (a new award with no picture yet).
static func draw(ci: CanvasItem, title: String, r: Rect2, a: float = 1.0) -> bool:
	var i := ORDER.find(title)
	if i < 0:
		return false
	ci.draw_texture_rect_region(SHEET, r, Rect2((i % PER_ROW) * CELL, (i / PER_ROW) * CELL, CELL, CELL), Color(1, 1, 1, a))
	return true
