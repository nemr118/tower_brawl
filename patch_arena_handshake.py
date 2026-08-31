import os

with open("scripts/arena.gd", "r") as f:
    code = f.read()

old_display = """		else:
			var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
			var txt = "👑 " + ("YOU WON ROUND " + str(current_round) + "!" if is_me else w_name + " (" + winner_class + ") WINS ROUND " + str(current_round) + "!") + " 👑"
			_show_banner(txt, 2.2)
			await get_tree().create_timer(2.6).timeout
			current_round += 1
			_start_round()"""
			
new_display = """		else:
			var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
			var txt = "👑 " + ("YOU WON ROUND " + str(current_round) + "!" if is_me else w_name + " (" + winner_class + ") WINS ROUND " + str(current_round) + "!") + " 👑"
			_show_banner(txt, 2.2)
			
			if Global.is_host():
				await get_tree().create_timer(2.6).timeout
				current_round += 1
				Global.send_net_data({
					"type": "new_round",
					"round": current_round
				})
				_start_round()"""
				
code = code.replace(old_display, new_display)

with open("scripts/arena.gd", "w") as f:
    f.write(code)

