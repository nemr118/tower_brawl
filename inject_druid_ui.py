import os

with open("scripts/character_select.gd", "r") as f:
    code = f.read()

code = code.replace("Global.ClassType.ROGUE\n]", "Global.ClassType.ROGUE,\n\tGlobal.ClassType.DRUID\n]")

druid_skills = """	Global.ClassType.DRUID: {
		"primary": "🌿 Nature's Thorns / Bear Swipe",
		"special": "🐻 Toggle Bear Form (Ground) / 🥚 Phoenix Shield (Air)"
	}"""
code = code.replace('	Global.ClassType.ROGUE: {\n		"primary": "🗡️ Thrown Kunai (4 Rapid throwing blades)",\n		"special": "🌑 Shadow Ambush (Hyper-dash slices through all enemies)"\n	}',
                    '	Global.ClassType.ROGUE: {\n		"primary": "🗡️ Thrown Kunai (4 Rapid throwing blades)",\n		"special": "🌑 Shadow Ambush (Hyper-dash slices through all enemies)"\n	},\n' + druid_skills)

with open("scripts/character_select.gd", "w") as f:
    f.write(code)

