import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

host_func = """
func is_host() -> bool:
	var lowest = 999
	for p_id in active_players:
		if p_id < lowest:
			lowest = p_id
	if active_players.size() == 0:
		return true
	return my_player_id == lowest
"""

if "func is_host" not in code:
    code = code.replace("func reset_scores():", host_func + "\nfunc reset_scores():")

with open("scripts/global.gd", "w") as f:
    f.write(code)

