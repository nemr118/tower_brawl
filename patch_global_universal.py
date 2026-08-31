import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

var_injection = """
var is_mobile: bool = false
"""
if "var is_mobile: bool = false" not in code:
    code = code.replace("var active_players: Array = []", "var active_players: Array = []\n" + var_injection)

ready_injection = """
	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()
	if OS.has_feature("web"):
		var ua = JavaScriptBridge.eval("/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);", true)
		if ua:
			is_mobile = true
"""
if "is_mobile = OS.has_feature" not in code:
    code = code.replace("func _ready():", "func _ready():\n" + ready_injection)

# Fix keyboard binding
old_rebind = """		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if not OS.has_feature("web") and my_player_id != 1:"""
new_rebind = """		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if my_player_id != 1:"""
code = code.replace(old_rebind, new_rebind)

with open("scripts/global.gd", "w") as f:
    f.write(code)

