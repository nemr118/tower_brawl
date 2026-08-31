import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

druid_info = """	ClassType.DRUID: {
		"name": "Druid",
		"title": "Shape Shifter",
		"icon": "🐻",
		"color": Color(0.6, 0.4, 0.1),
		"desc": "Throws thorns. Bear Form. Dash turns into a Storm Crow. Shield is Phoenix Egg."
	}"""
	
old_rogue = """	ClassType.ROGUE: {
		"name": "Rogue",
		"title": "Shadow Assassin",
		"icon": "🗡️",
		"color": Color(0.75, 0.3, 0.95),
		"desc": "Rapid throwing kunais, shadow dash ambushes through enemies."
	}"""

code = code.replace(old_rogue, old_rogue + ",\n" + druid_info)

with open("scripts/global.gd", "w") as f:
    f.write(code)

