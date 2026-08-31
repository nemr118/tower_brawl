with open("serve_game.py", "r") as f:
    code = f.read()

bad = "def ws_client_thread(sock, addr, label, skip_handshake=False):"
good = "def ws_client_thread(sock, addr, label, skip_handshake=False):\n    global global_match_state, global_playing_players, global_waiting_players, global_current_round, global_player_scores, global_player_stocks, global_alive_players, global_is_round_over"

code = code.replace(bad, good)

with open("serve_game.py", "w") as f:
    f.write(code)

