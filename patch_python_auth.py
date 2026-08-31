import os

with open("serve_game.py", "r") as f:
    code = f.read()

# Add state variables
state_vars = """
# Authoritative Game State
global_current_round = 1
global_player_scores = {1: 0, 2: 0, 3: 0, 4: 0}
global_player_stocks = {1: 3, 2: 3, 3: 3, 4: 3}
global_alive_players = set()
global_is_round_over = False
"""
code = code.replace("player_names  = {}\n", "player_names  = {}\n" + state_vars)

# Inject logic into message processing
inject = """
                if data.get("type") == "force_start":
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
                    continue
                    
                if data.get("type") == "player_died":
                    victim = int(data.get("victim", 0))
                    killer = int(data.get("killer", 0))
                    
                    with lobby_lock:
                        if victim in global_alive_players:
                            global_player_stocks[victim] -= 1
                            if global_player_stocks[victim] <= 0:
                                global_alive_players.remove(victim)
                                
                        # broadcast death
                        broadcast(json.dumps({
                            "type": "player_died",
                            "victim": victim,
                            "killer": killer,
                            "stock": global_player_stocks[victim]
                        }))
                        
                        if len(global_alive_players) <= 1 and not global_is_round_over and len(active) > 1:
                            global_is_round_over = True
                            winner = list(global_alive_players)[0] if len(global_alive_players) == 1 else 0
                            if winner > 0:
                                global_player_scores[winner] += 1
                                
                            broadcast(json.dumps({
                                "type": "round_end",
                                "winner": winner,
                                "scores": global_player_scores,
                                "round": global_current_round
                            }))
                            
                            def next_round():
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
                                    }))
                                    
                            import threading
                            threading.Thread(target=next_round, daemon=True).start()
                    continue
"""

code = code.replace('if data.get("type") == "lock_in":', inject + '\n                if data.get("type") == "lock_in":')

with open("serve_game.py", "w") as f:
    f.write(code)

