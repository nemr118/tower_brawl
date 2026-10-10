# The compile check for the new game's project (bench/): loads every .gd under
# sim/, server/, client/ and tools/, and loads and instantiates every .tscn under
# client/ and server/. tools/v2_build.sh runs it before an export.
#   godot --headless --path bench --script res://tools/check_scripts.gd
# Exit 0 = everything compiled and loaded. Exit 1 = at least one failed (stderr).
extends SceneTree

const SCRIPT_DIRS := ["res://sim", "res://server", "res://client", "res://tools"]
const SCENE_DIRS := ["res://client", "res://server"]

func _init() -> void:
	var failed: Array[String] = []
	var checked := 0
	for dir_path in SCRIPT_DIRS:
		for path in _list_files(dir_path, ".gd"):
			checked += 1
			var script = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
			if script == null or not (script is GDScript) or not script.can_instantiate():
				failed.append(path)
	var scenes := 0
	for dir_path in SCENE_DIRS:
		for path in _list_files(dir_path, ".tscn"):
			scenes += 1
			var packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
			if packed == null or not (packed is PackedScene) or not packed.can_instantiate():
				failed.append(path)
				continue
			var inst = packed.instantiate()
			if inst == null:
				failed.append(path)
			else:
				inst.free()
	if failed.is_empty():
		print("✅ check_scripts (bench): %d scripts compiled OK, %d scenes load OK" % [checked, scenes])
		quit(0)
	else:
		printerr("❌ check_scripts (bench): %d of %d scripts or scenes FAILED:" % [failed.size(), checked + scenes])
		for f in failed:
			printerr("   " + f)
		quit(1)

func _list_files(dir_path: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(ext) and name != "check_scripts.gd":
			out.append(dir_path + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
