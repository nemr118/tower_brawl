extends SceneTree
# ==============================================================================
# GDScript compile checker (used by bump_build.sh)
# ==============================================================================
# `godot --check-only` runs BEFORE autoloads are registered, so every script that
# references `Global` fails with "Identifier not found: Global" even when it is
# fine. This script instead runs as the main loop, waits until autoloads exist,
# then force-loads every .gd file under res://scripts and res://tools.
#
# Usage:   godot --headless --path . --script tools/check_scripts.gd
# Exit 0 = every script compiled.  Exit 1 = at least one failed (errors on stderr).
# ==============================================================================

const SCAN_DIRS := ["res://scripts", "res://tools"]
var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var failed: Array[String] = []
	var checked := 0
	for dir_path in SCAN_DIRS:
		for path in _list_scripts(dir_path):
			checked += 1
			var script = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
			if script == null or not (script is GDScript):
				failed.append(path)
				continue
			# Parse AND compile errors both make load() return null (seen on stderr);
			# can_instantiate() is a cheap extra guard for anything that slipped through.
			if not script.can_instantiate():
				failed.append(path)
	if failed.is_empty():
		print("✅ check_scripts: %d scripts compiled OK" % checked)
		quit(0)
	else:
		printerr("❌ check_scripts: %d of %d scripts FAILED:" % [failed.size(), checked])
		for f in failed:
			printerr("   " + f)
		quit(1)
	return true

func _list_scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".gd") and name != "check_scripts.gd":
			out.append(dir_path + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
