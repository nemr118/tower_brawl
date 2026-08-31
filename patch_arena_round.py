import os

with open("scripts/arena.gd", "r") as f:
    code = f.read()

old_check = """func _check_round_end():
	var alive_players = []"""
new_check = """func _check_round_end():
	if not Global.is_host():
		return # Let the host evaluate round end to prevent desyncs!
		
	var alive_players = []"""
code = code.replace(old_check, new_check)

old_sync = """func _on_round_end_sync(winner_id: int, s1: int, s2: int, round_num: int):
	is_round_over = true
	current_round = round_num
	_update_hud()
	_display_round_winner(winner_id)"""
new_sync = """func _on_round_end_sync(winner_id: int, scores: Dictionary, round_num: int):
	if is_round_over:
		return # Ignore duplicate network triggers
		
	is_round_over = true
	current_round = round_num
	
	# Sync the scores from the host
	for p_id in scores:
		Global.player_scores[int(p_id)] = int(scores[p_id])
		
	_update_hud()
	_display_round_winner(winner_id)"""
code = code.replace(old_sync, new_sync)

with open("scripts/arena.gd", "w") as f:
    f.write(code)

