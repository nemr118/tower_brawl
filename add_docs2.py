import os

def replace_first(text, search, replacement):
    return text.replace(search, replacement, 1)

def document_character_select():
    path = "scripts/character_select.gd"
    with open(path, "r") as f:
        code = f.read()

    header = """# ==============================================================================
# CHARACTER_SELECT.GD (The Waiting Room)
# ==============================================================================
# This script powers the menu screen you see before the fight starts.
# It uses UI (User Interface) elements like Labels and Buttons.
# When everyone is "locked in", it tells Godot to switch to the Arena scene!
# ==============================================================================

extends Control"""
    code = replace_first(code, "extends Control", header)
    with open(path, "w") as f:
        f.write(code)

document_character_select()
print("Character Select updated!")
