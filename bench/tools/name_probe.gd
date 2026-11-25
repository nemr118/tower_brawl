# The names people type (server/game_server.gd clean_name), tried with a list of
# nasty ones. A name shows on every screen and in the logs, so it may hold letters of
# any language, digits, single spaces and the marks - _ . ' ! ? and nothing else, 12
# characters at most, and it starts with a letter or a digit.
#   godot --headless --path bench --script res://tools/name_probe.gd
# Three kinds of check:
#   1. each nasty name comes out as the list says (the table it prints);
#   2. every result obeys the rules, judged by this file's own list of bad characters
#      (not by the server's code);
#   3. 20 000 random strings made of the nastiest characters obey them too, and a clean
#      name cleaned again does not change.
# (tools/v2_seat_check.py S13 sends the same kind of names to a running server and
# judges what comes back with Python's own Unicode tables.)
# Prints a PASS/FAIL line per check and exits 1 on a fail.
extends SceneTree

const Server = preload("res://server/game_server.gd")

var fails := 0
var checks := 0

# [what it is, the name as typed, what must come out ("" = nothing stays: the server
# then says "Player" or "Player 3")]
func _cases() -> Array:
	var rlo := String.chr(0x202E)      # "read from right to left from here on"
	var zalgo := "Z"
	for i in 10:
		zalgo += String.chr(0x0300 + i)
	var thai := String.chr(0x0E01) + String.chr(0x0E34)
	for i in 8:
		thai += String.chr(0x0E49)
	var tags := "A"
	for ch in "evil":
		tags += String.chr(0xE0000 + ch.unicode_at(0))   # the invisible "tag" letters
	return [
		["a plain name", "Ava", "Ava"],
		["spaces around it", "   Ava  ", "Ava"],
		["U+202E in front (the review's case)", rlo + "evA", "evA"],
		["U+202D and U+202C inside", "A" + String.chr(0x202D) + "v" + String.chr(0x202C) + "a", "Ava"],
		["the isolates U+2066 to U+2069", String.chr(0x2066) + "A" + String.chr(0x2067) + "v" + String.chr(0x2068) + "a" + String.chr(0x2069), "Ava"],
		["U+200E, U+200F, U+061C", "A" + String.chr(0x200E) + "v" + String.chr(0x200F) + "a" + String.chr(0x061C), "Ava"],
		["only direction characters", rlo + rlo + String.chr(0x202B), ""],
		["an HTML tag", "<b>Bob</b>", "bBobb"],
		["a script tag", "<script>alert(1)</script>", "scriptalert1"],
		["an image tag", "<img src=x onerror=1>", "img srcx one"],
		["HTML entities", "&lt;Bob&gt;", "ltBobgt"],
		["an entity for U+202E", "&#x202e;Bob", "x202eBob"],
		["BBCode", "[b]Bob[/b]", "bBobb"],
		["BBCode with a colour", "[color=red]X", "colorredX"],
		["a template", "{{7*7}}", "77"],
		["format marks", "%s%d%n", "sdn"],
		["Markdown", "**Bob** `x`", "Bob x"],
		["a link", "http://x.io", "httpx.io"],
		["a spreadsheet formula", "=1+1", "11"],
		["a command's option", "--help", "help"],
		["a shell line", "-rf / ; ls", "rf ls"],
		["SQL", "'; DROP TABLE", "DROP TABLE"],
		["quotes", "A'B\"C`D", "A'BCD"],
		["a backslash", "a\\nb\\t", "anbt"],
		["a line break", "Bob\nEve", "Bob Eve"],
		["a tab", "Bob\tEve", "Bob Eve"],
		["control characters", "Bob" + String.chr(7) + String.chr(27) + String.chr(127) + "Eve", "BobEve"],
		["zero-width characters", "A" + String.chr(0x200B) + String.chr(0x200C) + String.chr(0x200D) + String.chr(0xFEFF) + String.chr(0x2060) + "B", "AB"],
		["a soft hyphen", "A" + String.chr(0xAD) + "B", "AB"],
		["Korean's empty letters only", String.chr(0x3164) + String.chr(0x3164) + String.chr(0x115F) + String.chr(0xFFA0), ""],
		["an empty letter inside", "A" + String.chr(0x3164) + "B", "AB"],
		["variation selectors", "a" + String.chr(0xFE0F) + String.chr(0xFE0E) + "b", "ab"],
		["invisible tag letters", tags, "A"],
		["an accent with no letter", String.chr(0x0301) + String.chr(0x0301) + "a", "a"],
		["10 accents on one letter (Zalgo)", zalgo + "a", "Z" + String.chr(0x0300) + String.chr(0x0301) + String.chr(0x0302) + "a"],
		["8 Thai marks on one letter", thai, String.chr(0x0E01) + String.chr(0x0E34) + String.chr(0x0E49) + String.chr(0x0E49)],
		["the widest character there is (U+FDFD)", String.chr(0xFDFD) + "Bob", "Bob"],
		["an emoji", String.chr(0x1F983) + "Tom" + String.chr(0x1F983), "Tom"],
		["a heart", "Tom" + String.chr(0x2764) + String.chr(0xFE0F), "Tom"],
		["only marks", "!!!", ""],
		["only spaces", "      ", ""],
		["nothing", "", ""],
		["many spaces inside", "A     B", "A B"],
		["odd spaces (U+00A0, U+3000)", "A" + String.chr(0xA0) + String.chr(0x3000) + "B", "A B"],
		["too long", "ABCDEFGHIJKLMNOP", "ABCDEFGHIJKL"],
		["too long at a space", "ABCDEFGHIJK LM", "ABCDEFGHIJK"],
		["5 000 letters", "A".repeat(5000), "AAAAAAAAAAAA"],
		["100 spaces, then a name", " ".repeat(100) + "Ava", ""],
		# what must stay
		["Spanish", "José", "José"],
		["German", "Zoë Müller", "Zoë Müller"],
		["Greek", "Ελένη", "Ελένη"],
		["Russian", "Иван", "Иван"],
		["Chinese", "李小龙", "李小龙"],
		["Japanese", "さくら", "さくら"],
		["Korean", "한글", "한글"],
		["Arabic", "محمد", "محمد"],
		["Hebrew", "דוד", "דוד"],
		["Hindi (letters with marks)", "हिन्दी", "हिन्दी"],
		["Vietnamese, accents apart", "Vie" + String.chr(0x0323) + String.chr(0x0302) + "t", "Vie" + String.chr(0x0323) + String.chr(0x0302) + "t"],
		["Arabic digits", "١٢٣٤٥", "١٢٣٤٥"],
		["a curly apostrophe", "O" + String.chr(0x2019) + "Neil", "O'Neil"],
		["a hyphen", "Mary-Jane", "Mary-Jane"],
		["a dot and a bang", "Mr. T!", "Mr. T!"],
		["a question", "who?", "who?"],
		["an underscore", "xX_Ava_Xx", "xX_Ava_Xx"],
		["digits first", "007 Bond", "007 Bond"],
		["marks between words", "a  -  b", "a - b"],
	]

func _init() -> void:
	print("== the nasty names (as typed -> as kept; code points in brackets where they do not print)")
	var wrong: Array = []
	var broken: Array = []
	for c in _cases():
		var got: String = Server.clean_name(c[1])
		print("   %-38s %-34s -> %s" % [c[0], _show(c[1]), _show(got)])
		if got != c[2]:
			wrong.append("%s: got %s, wanted %s" % [c[0], _show(got), _show(c[2])])
		var why := _broken(got)
		if why != "":
			broken.append("%s: %s" % [c[0], why])
	_check("each of the %d nasty names comes out as the list says" % _cases().size(), wrong.is_empty(), "; ".join(wrong.slice(0, 3)))
	_check("each result obeys the rules (this file's own list of bad characters)", broken.is_empty(), "; ".join(broken.slice(0, 3)))
	# 3. random strings of the nastiest characters
	var pool: Array = []
	for code in [1, 7, 9, 10, 13, 27, 32, 32, 32, 34, 37, 38, 39, 45, 46, 47, 58, 60, 62, 91, 92, 93, 95, 96, 123, 125, 127, 0x85, 0xA0, 0xAD,
			0x0301, 0x0302, 0x034F, 0x061C, 0x0627, 0x0663, 0x0E01, 0x0E49, 0x115F, 0x17B4, 0x180B, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F,
			0x2019, 0x2028, 0x2029, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0x3000, 0x3164, 0x4E2D,
			0xFDFD, 0xFE0F, 0xFEFF, 0xFFA0, 0xFFF9, 0x1F983, 0xE0041, 0xE0100, 65, 66, 97, 98, 48, 49, 33, 63]:
		pool.append(String.chr(code))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var bad: Array = []
	var changed: Array = []
	var kept := 0
	for i in 20000:
		var raw := ""
		for k in rng.randi_range(0, 40):
			raw += pool[rng.randi() % pool.size()]
		var got: String = Server.clean_name(raw)
		if got != "":
			kept += 1
		var why := _broken(got)
		if why != "":
			bad.append("%s -> %s: %s" % [_show(raw), _show(got), why])
		if Server.clean_name(got) != got:
			changed.append("%s -> %s -> %s" % [_show(raw), _show(got), _show(Server.clean_name(got))])
	_check("20 000 random strings of the nastiest characters: every result obeys the rules (%d kept something)" % kept, bad.is_empty(), "; ".join(bad.slice(0, 2)))
	_check("a clean name cleaned again does not change (20 000 random strings)", changed.is_empty(), "; ".join(changed.slice(0, 2)))
	if fails == 0:
		print("✅ name_probe: %d of %d checks passed" % [checks, checks])
		quit(0)
	else:
		printerr("❌ name_probe: %d of %d checks failed" % [fails, checks])
		quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	fails += 0 if ok else 1
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, "" if ok or detail == "" else ": " + detail])

# What is wrong with a cleaned name, or "". This is the probe's own judge: a list of
# the characters that must never be in a name, written out here by hand.
func _broken(n: String) -> String:
	if n.length() > 12:
		return "%d characters" % n.length()
	if n == "":
		return ""
	if n != n.strip_edges() or n.contains("  "):
		return "a space at an end, or two in a row"
	var first := n.unicode_at(0)
	if first < 128 and not ((first >= 48 and first <= 57) or (first >= 65 and first <= 90) or (first >= 97 and first <= 122)):
		return "it starts with a mark"
	if first >= 0x0300 and first <= 0x036F:
		return "it starts with an accent"
	var run := 0
	for i in n.length():
		var code := n.unicode_at(i)
		if code < 32 or (code >= 127 and code <= 159):
			return "a control character U+%04X" % code
		if code < 128 and not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or " -_.'!?".contains(n[i])):
			return "the mark %s" % n[i]
		for r in [[0xA0, 0xA0], [0xAD, 0xAD], [0x034F, 0x034F], [0x061C, 0x061C], [0x115F, 0x1160], [0x1680, 0x1680], [0x17B4, 0x17B5], [0x180B, 0x180F],
				[0x2000, 0x200F], [0x2028, 0x202F], [0x205F, 0x206F], [0x3000, 0x3000], [0x3164, 0x3164], [0xFDFD, 0xFDFD], [0xFE00, 0xFE0F],
				[0xFEFF, 0xFEFF], [0xFFA0, 0xFFA0], [0xFFF0, 0xFFFF], [0x1F000, 0x1FAFF], [0xE0000, 0xE0FFF]]:
			if code >= r[0] and code <= r[1]:
				return "U+%04X (it draws nothing, turns the line, or is no letter)" % code
		# the accents this probe throws: the combining block, and Thai's marks
		if (code >= 0x0300 and code <= 0x036F) or (code >= 0x0E31 and code <= 0x0E4E and code != 0x0E32 and code != 0x0E33 and code != 0x0E40):
			run += 1
			if run > 3:
				return "more than 3 accents on one letter"
		else:
			run = 0
	return ""

# A name for the table: what prints as it is, the rest as [U+XXXX]; long ones cut.
func _show(s: String) -> String:
	var out := "\""
	for i in mini(s.length(), 22):
		var code := s.unicode_at(i)
		var plain: bool = code >= 32 and code < 127
		for r in [[0xC0, 0x2FF], [0x370, 0x3FF], [0x400, 0x4FF], [0x5D0, 0x5EA], [0x620, 0x64A], [0x660, 0x669], [0x900, 0x97F], [0x3040, 0x30FF], [0x4E00, 0x9FFF], [0xAC00, 0xD7A3]]:
			if code >= r[0] and code <= r[1]:
				plain = true
		out += s[i] if plain else "[U+%04X]" % code
	return out + ("\"" if s.length() <= 22 else "… (%d)\"" % s.length())
