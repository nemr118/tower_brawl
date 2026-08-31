import os

with open("scripts/character_select.gd", "r") as f:
    code = f.read()

bad2 = """	if force_start_btn:
	force_start_btn.visible = false"""
good2 = """	if force_start_btn:
		force_start_btn.visible = false"""
code = code.replace(bad2, good2)

with open("scripts/character_select.gd", "w") as f:
    f.write(code)

