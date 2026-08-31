extends Node

## Global Game Configuration and Class Definitions for 4-Player Battle Royale

enum ClassType {
	RANGER,
	KNIGHT,
	MAGE,
	ROGUE
}

const CLASS_INFO = {
	ClassType.RANGER: {
		"name": "Ranger",
		"title": "Master Archer",
		"icon": "🏹",
		"color": Color(0.2, 0.75, 0.35), # Emerald Green
		"desc": "Precision multi-directional arrows, projectile catching, and recoil backflip shot."
	},
	ClassType.KNIGHT: {
		"name": "Knight",
		"title": "Iron Juggernaut",
		"icon": "⚔️",
		"color": Color(0.25, 0.55, 0.95), # Azure Blue
		"desc": "Broadsword slash deflects projectiles, shield guard parries arrows and spells."
	},
	ClassType.MAGE: {
		"name": "Mage",
		"title": "Pyromancer",
		"icon": "🔮",
		"color": Color(0.95, 0.55, 0.15), # Amber Flame
		"desc": "Explosive firebolts that regenerate over time, and instantaneous void blink teleport."
	},
	ClassType.ROGUE: {
		"name": "Rogue",
		"title": "Shadow Assassin",
		"icon": "🗡️",
		"color": Color(0.75, 0.3, 0.95), # Amethyst Purple
		"desc": "Rapid throwing kunais, shadow dash ambushes through enemies."
	}
}

var player_configs = {
	1: {"class": ClassType.RANGER, "active": true},
	2: {"class": ClassType.KNIGHT, "active": true},
	3: {"class": ClassType.MAGE, "active": true},
	4: {"class": ClassType.ROGUE, "active": true}
}

var player_scores = {
	1: 0,
	2: 0,
	3: 0,
	4: 0
}

var max_stocks: int = 3
var match_score_limit: int = 5

func reset_scores():
	player_scores = {1: 0, 2: 0, 3: 0, 4: 0}
