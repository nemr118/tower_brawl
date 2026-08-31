extends Node

## Global Game Manager for TowerBrawl
## Tracks players, scores, stock counts, and class selection.

enum ClassType { RANGER, KNIGHT, MAGE, ROGUE }

const CLASS_INFO = {
	ClassType.RANGER: {
		"name": "Ranger",
		"title": "Master Archer",
		"desc": "Precision arrows, catches incoming projectiles, and backflip shot.",
		"color": Color(0.25, 0.85, 0.45), # Emerald
		"icon": "🏹"
	},
	ClassType.KNIGHT: {
		"name": "Knight",
		"title": "Iron Champion",
		"desc": "Heavy broadsword slash and shield that parries/reflects arrows.",
		"color": Color(0.35, 0.65, 0.95), # Royal Blue
		"icon": "⚔️"
	},
	ClassType.MAGE: {
		"name": "Mage",
		"title": "Arcane Pyromancer",
		"desc": "Explosive firebolts and instantaneous teleport blink.",
		"color": Color(0.95, 0.45, 0.25), # Pyre Orange
		"icon": "🔮"
	},
	ClassType.ROGUE: {
		"name": "Rogue",
		"title": "Shadowblade",
		"desc": "Dual dagger dash through foes and thrown kunai blades.",
		"color": Color(0.85, 0.35, 0.95), # Shadow Purple
		"icon": "🗡️"
	}
}

var max_stocks: int = 3
var match_score_limit: int = 5
var player_scores = {1: 0, 2: 0, 3: 0, 4: 0}

var player_configs = {
	1: {"active": true, "class": ClassType.RANGER, "name": "Player 1", "device": 0},
	2: {"active": true, "class": ClassType.KNIGHT, "name": "Player 2", "device": 1},
	3: {"active": false, "class": ClassType.MAGE, "name": "Player 3", "device": 2},
	4: {"active": false, "class": ClassType.ROGUE, "name": "Player 4", "device": 3}
}

func reset_scores():
	player_scores = {1: 0, 2: 0, 3: 0, 4: 0}
