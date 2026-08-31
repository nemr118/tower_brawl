import os

def replace_first(text, search, replacement):
    return text.replace(search, replacement, 1)

def document_player():
    path = "scripts/player.gd"
    with open(path, "r") as f:
        code = f.read()

    header = """# ==============================================================================
# WELCOME TO PLAYER.GD! (The Character Script)
# ==============================================================================
# Hey there! This script acts as the "brain" for the characters on screen.
# Every time you move, jump, or attack, this file is doing the math.
# In programming, we use "variables" (think of them like labeled boxes) 
# to store information like how fast we can run or how many lives we have left.
# ==============================================================================

extends CharacterBody2D"""
    code = replace_first(code, "extends CharacterBody2D", header)

    physics = """
	# ------------------------------------------------------------------------------
	# THE GAME LOOP: _physics_process(delta)
	# This function is the heartbeat of the game! It runs 60 times every second.
	# "delta" is the tiny fraction of a second between frames. We use delta 
	# to make sure the game runs at the same speed on fast and slow computers.
	# ------------------------------------------------------------------------------
func _physics_process(delta: float):"""
    code = replace_first(code, "func _physics_process(delta: float):", physics)

    get_input = """
	# ------------------------------------------------------------------------------
	# CHECKING FOR BUTTON PRESSES
	# This recipe (or 'function') checks if you are pressing buttons on the 
	# keyboard, controller, or phone screen, and sets the character's speed.
	# ------------------------------------------------------------------------------
func _get_input(delta: float):"""
    code = replace_first(code, "func _get_input(delta: float):", get_input)

    attack = """
	# ------------------------------------------------------------------------------
	# ATTACKING
	# This function spawns arrows, fireballs, or sword slashes. 
	# It uses "if" statements (which ask a Yes/No question) to figure out 
	# which class you are playing before spawning the right weapon!
	# ------------------------------------------------------------------------------
func _perform_attack(aim_dir: Vector2):"""
    code = replace_first(code, "func _perform_attack(aim_dir: Vector2):", attack)

    draw = """
	# ------------------------------------------------------------------------------
	# DRAWING THE CHARACTER
	# We don't use 3D models here! Instead, we tell the computer to draw 
	# simple shapes (circles, lines, and rectangles) to build our pixel heroes.
	# ------------------------------------------------------------------------------
func _draw():"""
    code = replace_first(code, "func _draw():", draw)

    with open(path, "w") as f:
        f.write(code)

def document_arena():
    path = "scripts/arena.gd"
    with open(path, "r") as f:
        code = f.read()

    header = """# ==============================================================================
# WELCOME TO ARENA.GD! (The Game World Script)
# ==============================================================================
# This script is like the "Game Master" or Referee.
# It doesn't control a single player. Instead, it builds the arena, decides 
# where everyone spawns, keeps score, and drops power-ups from the sky.
# ==============================================================================

extends Node2D"""
    code = replace_first(code, "extends Node2D", header)

    ready = """
# ------------------------------------------------------------------------------
# SETUP TIME!
# _ready() is a special Godot function that runs exactly ONCE when the 
# level first loads. It's like setting up a board game before you start playing.
# ------------------------------------------------------------------------------
func _ready():"""
    code = replace_first(code, "func _ready():", ready)

    start = """
# ------------------------------------------------------------------------------
# ROUND START
# We use this function to clear out old projectiles, put players on their
# starting platforms, and reset everyone's health.
# ------------------------------------------------------------------------------
func _start_round():"""
    code = replace_first(code, "func _start_round():", start)

    with open(path, "w") as f:
        f.write(code)

def document_global():
    path = "scripts/global.gd"
    with open(path, "r") as f:
        code = f.read()

    header = """# ==============================================================================
# WELCOME TO GLOBAL.GD! (The Networking Script)
# ==============================================================================
# This script is an "Autoload". That means it stays awake in the background
# forever while the game runs. 
# Its main job is sending invisible text messages (called JSON) over the 
# internet so that phones and PCs can talk to each other in real-time!
# ==============================================================================

extends Node"""
    code = replace_first(code, "extends Node", header)

    with open(path, "w") as f:
        f.write(code)

try:
    document_player()
    document_arena()
    document_global()
    print("Documentation injected successfully!")
except Exception as e:
    print("Error:", e)

