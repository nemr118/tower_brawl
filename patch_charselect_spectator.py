import os

with open("scripts/character_select.gd", "r") as f:
    code = f.read()

# Make the spectator jump immediately to arena
code = code.replace("func _ready():\n\t_update_my_slot_ui()", "func _ready():\n\tif Global.is_spectator:\n\t\tget_tree().change_scene_to_file(\"res://scenes/arena.tscn\")\n\t\treturn\n\n\t_update_my_slot_ui()")

with open("scripts/character_select.gd", "w") as f:
    f.write(code)

