import os

with open("serve_game.py", "r") as f:
    code = f.read()

# Add new globals
code = code.replace("global_is_round_over = False", "global_is_round_over = False\nglobal_match_state = 'LOBBY'\nglobal_playing_players = []\nglobal_waiting_players = []")

# Update 'force_start'
old_start = """                if data.get("type") == "force_start":
                    with lobby_lock:
                        global_current_round = 1
                        for i in range(1, 5):
                            global_player_scores[i] = 0
                            global_player_stocks[i] = 3
                        global_alive_players = set(active)
                        global_is_round_over = False
                        player_locked[assigned_id] = int(data.get("class", 0))
                    data["sender"] = assigned_id
                    msg = json.dumps(data)
                    broadcast(msg)
                    continue"""
new_start = """                if data.get("type") == "force_start":
                    with lobby_lock:
                        global_match_state = 'PLAYING'
                        global_current_round = 1
                        active_now = [i+1 for i in range(4) if player_slots[i]]
                        global_playing_players = list(active_now)
                        global_waiting_players = []
                        for i in range(1, 5):
                            global_player_scores[i] = 0
                            global_player_stocks[i] = 3
                        global_alive_players = set(active_now)
                        global_is_round_over = False
                        player_locked[assigned_id] = int(data.get("class", 0))
                    data["sender"] = assigned_id
                    msg = json.dumps(data)
                    broadcast(msg)
                    continue"""
code = code.replace(old_start, new_start)

# Update next_round logic
old_next = """                            def next_round():
                                global global_current_round, global_is_round_over, global_alive_players, global_player_stocks
                                import time
                                time.sleep(2.6)
                                with lobby_lock:
                                    global_current_round += 1
                                    global_is_round_over = False
                                    global_alive_players = set([i+1 for i in range(4) if player_slots[i]])
                                    for i in range(1, 5):
                                        global_player_stocks[i] = 3
                                    broadcast(json.dumps({
                                        "type": "new_round",
                                        "round": global_current_round
                                    }))"""
new_next = """                            def next_round():
                                global global_current_round, global_is_round_over, global_alive_players, global_player_stocks, global_match_state, global_waiting_players, global_playing_players
                                import time
                                time.sleep(2.6)
                                with lobby_lock:
                                    if len(global_waiting_players) > 0:
                                        global_match_state = 'LOBBY'
                                        global_waiting_players = []
                                        global_playing_players = []
                                        player_locked.clear()
                                        broadcast(json.dumps({"type": "return_to_lobby"}))
                                    else:
                                        global_current_round += 1
                                        global_is_round_over = False
                                        global_alive_players = set([p for p in global_playing_players if player_slots[p-1]])
                                        for i in range(1, 5):
                                            global_player_stocks[i] = 3
                                        broadcast(json.dumps({
                                            "type": "new_round",
                                            "round": global_current_round
                                        }))"""
code = code.replace(old_next, new_next)

# Update assign_id response
old_assign = """    with lobby_lock:
        active = [i+1 for i in range(4) if player_slots[i]]
        locked = {str(k): v for k, v in player_locked.items()}
        names  = {str(k): v for k, v in player_names.items()}

    print(f"[{label}] P{assigned_id} JOINED  active={active}  addr={addr}")

    ws_send(sock, json.dumps({
        "type":           "assign_id",
        "id":             assigned_id,
        "active_players": active,
        "locked_players": locked,
        "player_names": names,
    }))"""
new_assign = """    with lobby_lock:
        active = [i+1 for i in range(4) if player_slots[i]]
        if global_match_state == 'PLAYING':
            if assigned_id not in global_playing_players and assigned_id not in global_waiting_players:
                global_waiting_players.append(assigned_id)
        else:
            if assigned_id not in global_playing_players:
                global_playing_players.append(assigned_id)
                
        locked = {str(k): v for k, v in player_locked.items()}
        names  = {str(k): v for k, v in player_names.items()}

    print(f"[{label}] P{assigned_id} JOINED  active={active}  addr={addr}")

    ws_send(sock, json.dumps({
        "type":           "assign_id",
        "id":             assigned_id,
        "active_players": active,
        "playing_players": global_playing_players,
        "match_state": global_match_state,
        "locked_players": locked,
        "player_names": names,
    }))"""
code = code.replace(old_assign, new_assign)

with open("serve_game.py", "w") as f:
    f.write(code)

