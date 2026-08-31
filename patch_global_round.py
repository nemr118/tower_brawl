import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

# Fix signal definition
code = code.replace("signal net_round_end(winner_id, p1_score, p2_score, round_num)", "signal net_round_end(winner_id, scores, round_num)")

# Fix packet reading
old_read = """	elif type == "round_end":
		var winner = int(data.get("winner", 1))
		var s1 = int(data.get("p1_score", 0))
		var s2 = int(data.get("p2_score", 0))
		var r_num = int(data.get("round", 1))
		emit_signal("net_round_end", winner, s1, s2, r_num)"""
		
new_read = """	elif type == "round_end":
		var winner = int(data.get("winner", 1))
		var scores = data.get("scores", {})
		var r_num = int(data.get("round", 1))
		emit_signal("net_round_end", winner, scores, r_num)"""
		
code = code.replace(old_read, new_read)

with open("scripts/global.gd", "w") as f:
    f.write(code)

