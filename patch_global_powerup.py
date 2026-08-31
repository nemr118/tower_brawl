with open("scripts/global.gd", "r") as f:
    code = f.read()

# Add signals
if "signal net_spawn_powerup" not in code:
    code = code.replace("signal net_names_updated()", "signal net_names_updated()\nsignal net_spawn_powerup(x, y)\nsignal net_activate_powerup(powerup_id)")

if 'elif type == "spawn_powerup":' not in code:
    handler = """	elif type == "spawn_powerup":
		emit_signal("net_spawn_powerup", data.get("x", 0.0), data.get("y", 0.0))
	elif type == "activate_powerup":
		emit_signal("net_activate_powerup", data.get("powerup_id", 0))"""
    
    code = code.replace('	if type == "force_start":', handler + '\n	if type == "force_start":')

with open("scripts/global.gd", "w") as f:
    f.write(code)
