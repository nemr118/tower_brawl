with open("scripts/global.gd", "r") as f:
    code = f.read()

bad_hello2 = """			_load_saved_player_name() # Ensure name is loaded
			send_net_data({"type": "hello", "reclaim_id": saved_id, "name": my_player_name})"""

good_hello2 = """			if my_player_name == "":
				my_player_name = _load_saved_player_name()
			send_net_data({"type": "hello", "reclaim_id": saved_id, "name": my_player_name})"""

code = code.replace(bad_hello2, good_hello2)

with open("scripts/global.gd", "w") as f:
    f.write(code)
