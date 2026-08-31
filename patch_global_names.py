with open("scripts/global.gd", "r") as f:
    code = f.read()

bad_hello = """			var saved_id = _load_saved_player_id()
			send_net_data({"type": "hello", "reclaim_id": saved_id})"""

good_hello = """			var saved_id = _load_saved_player_id()
			_load_saved_player_name() # Ensure name is loaded
			send_net_data({"type": "hello", "reclaim_id": saved_id, "name": my_player_name})"""

code = code.replace(bad_hello, good_hello)

with open("scripts/global.gd", "w") as f:
    f.write(code)
