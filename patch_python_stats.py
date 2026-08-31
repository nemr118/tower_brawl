import os

with open("serve_game.py", "r") as f:
    code = f.read()

old_assign = """    ws_send(sock, json.dumps({
        "type":           "assign_id",
        "id":             assigned_id,
        "active_players": active,
        "playing_players": global_playing_players,
        "match_state": global_match_state,
        "locked_players": locked,
        "player_names": names,
    }))"""
    
new_assign = """    ws_send(sock, json.dumps({
        "type":           "assign_id",
        "id":             assigned_id,
        "active_players": active,
        "playing_players": global_playing_players,
        "match_state": global_match_state,
        "locked_players": locked,
        "player_names": names,
        "current_round": global_current_round,
        "scores": global_player_scores,
        "stocks": global_player_stocks
    }))"""
code = code.replace(old_assign, new_assign)

with open("serve_game.py", "w") as f:
    f.write(code)

