# p4.22 WINTER HATS, the server's part (the Christmas update: "Pick your hat ... The server
# keeps it with your name"). Each seat wears one of COUNT hats (the looks: client/hats.gd).
# A person picks one with the HAT button on their own lobby card; the pick is kept with
# their name in <out>/known_hats.json, beside known_names.json, so the same name gets its
# hat back the next time it sits down, also after the server starts again.
# The rules:
#   - a new person starts with the hat of their seat's number (for_seat), so eight
#     fighters show a mix; bots wear their seat's hat too;
#   - a name that picked a hat gets that hat on any seat (capitals do not count: Ava = AVA);
#   - a name that never picked keeps tonight the hat it was first given (in memory only),
#     so leaving a seat and sitting down on another does not change it;
#   - "Player 3" and the like are nobody's name: they always get the seat's hat.
# game_server.gd asks hat_of() when a person sits down and calls keep() on a pick.
extends RefCounted

const COUNT := 6             # Santa hat, elf hat, antlers, earmuffs, pom beanie, top hat (client/hats.gd COUNT)
const KEEP_MAX := 400        # names kept in the file at most (a soak of fake players cannot fill the disk): the oldest go first

var path := ""               # known_hats.json ("": nothing is read or written: the probes)
var picks := {}              # a name in small letters -> the hat it picked (the file)
var worn := {}               # a name in small letters -> the hat it wears tonight (never saved)

# The hat of a seat nobody picked for: by the seat's number.
static func for_seat(seat: int) -> int:
	return posmod(seat, COUNT)

static func _key(name: String) -> String:
	var k := name.strip_edges().to_lower()
	return "" if k == "" or k.begins_with("player") else k

# root: the folder known_names.json is in.
func load_from(root: String) -> void:
	path = root.path_join("known_hats.json")
	picks.clear()
	if not FileAccess.file_exists(path):
		return
	var js := JSON.new()
	if js.parse(FileAccess.get_file_as_string(path)) != OK or typeof(js.data) != TYPE_DICTIONARY:
		return
	for k in js.data:
		var v = js.data[k]
		if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and int(v) >= 0 and int(v) < COUNT and _key(str(k)) != "":
			picks[_key(str(k))] = int(v)

# The hat a person gets as they sit down on a seat.
func hat_of(name: String, seat: int) -> int:
	var k := _key(name)
	if k == "":
		return for_seat(seat)
	if picks.has(k):
		return int(picks[k])
	if not worn.has(k):
		if worn.size() >= KEEP_MAX:
			worn.erase(worn.keys()[0])
		worn[k] = for_seat(seat)
	return int(worn[k])

# A person picked a hat: kept with the name, and written to the file.
func keep(name: String, hat: int) -> void:
	var k := _key(name)
	if k == "" or hat < 0 or hat >= COUNT:
		return
	picks.erase(k)               # (a name that picks again counts as the newest)
	while picks.size() >= KEEP_MAX:
		picks.erase(picks.keys()[0])
	picks[k] = hat
	worn.erase(k)
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(picks))
