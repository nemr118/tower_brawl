import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

# Add signal
code = code.replace("signal net_round_end", "signal net_player_died(killer_id, victim_id, stock)\nsignal net_round_end")

# Parse player_died packet
new_parse = """	elif type == "player_died":
		var victim = int(data.get("victim", 0))
		var killer = int(data.get("killer", 0))
		var stock = int(data.get("stock", 0))
		emit_signal("net_player_died", killer, victim, stock)
		
	elif type == "round_end":"""
	
code = code.replace('	elif type == "round_end":', new_parse)

with open("scripts/global.gd", "w") as f:
    f.write(code)

