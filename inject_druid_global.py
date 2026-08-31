import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

code = code.replace("ROGUE\n}", "ROGUE,\n\tDRUID\n}")

druid_info = """	ClassType.DRUID: {
		"name": "Druid",
		"title": "Shape Shifter",
		"icon": "🐻",
		"color": Color(0.6, 0.4, 0.1),
		"desc": "Throws thorns. Bear Form. Dash turns into a Storm Crow. Shield is Phoenix Egg."
	}"""
code = code.replace('		"desc": "Rapid-fire 4-hit kunai, shadow dash slice, infinite stamina recharge."\n	}',
                    '		"desc": "Rapid-fire 4-hit kunai, shadow dash slice, infinite stamina recharge."\n	},\n' + druid_info)

with open("scripts/global.gd", "w") as f:
    f.write(code)

