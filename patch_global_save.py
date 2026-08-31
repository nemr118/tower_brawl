import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

old_save_id = """func _save_player_id():
	# Persist our slot number so we can reclaim it after a page reload / reconnect
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('towerbrawl_pid', '" + str(my_player_id) + "')", true)

func _load_saved_player_id() -> int:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("localStorage.getItem('towerbrawl_pid')", true)
		if val != null and str(val) != "null" and str(val) != "":
			return int(str(val))
	return 0  # 0 = no saved ID"""

new_save_id = """func _save_player_id():
	# Persist our slot number so we can reclaim it after a page reload / reconnect
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('towerbrawl_pid', '" + str(my_player_id) + "')", true)
	else:
		var f = FileAccess.open("user://towerbrawl_pid.sav", FileAccess.WRITE)
		if f:
			f.store_string(str(my_player_id))
			f.close()

func _load_saved_player_id() -> int:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("localStorage.getItem('towerbrawl_pid')", true)
		if val != null and str(val) != "null" and str(val) != "":
			return int(str(val))
	else:
		if FileAccess.file_exists("user://towerbrawl_pid.sav"):
			var f = FileAccess.open("user://towerbrawl_pid.sav", FileAccess.READ)
			if f:
				var val = f.get_as_text()
				f.close()
				if val != "":
					return int(val)
	return 0  # 0 = no saved ID"""

code = code.replace(old_save_id, new_save_id)

old_save_name = """func _save_player_name(n: String):
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('towerbrawl_name', '" + n + "')", true)

func _load_saved_player_name() -> String:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("localStorage.getItem('towerbrawl_name')", true)
		if val != null and str(val) != "null" and str(val) != "":
			return str(val)
	return "" """

new_save_name = """func _save_player_name(n: String):
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('towerbrawl_name', '" + n + "')", true)
	else:
		var f = FileAccess.open("user://towerbrawl_name.sav", FileAccess.WRITE)
		if f:
			f.store_string(n)
			f.close()

func _load_saved_player_name() -> String:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("localStorage.getItem('towerbrawl_name')", true)
		if val != null and str(val) != "null" and str(val) != "":
			return str(val)
	else:
		if FileAccess.file_exists("user://towerbrawl_name.sav"):
			var f = FileAccess.open("user://towerbrawl_name.sav", FileAccess.READ)
			if f:
				var val = f.get_as_text()
				f.close()
				return val
	return "" """

code = code.replace(old_save_name, new_save_name)

with open("scripts/global.gd", "w") as f:
    f.write(code)

