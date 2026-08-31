with open("serve_game.py", "r") as f:
    code = f.read()

bad_cleanup = """    # Cleanup — only free if this socket still owns the slot
    with lobby_lock:
        if player_slots[assigned_id - 1] and player_slots[assigned_id - 1]["sock"] is sock:
            player_slots[assigned_id - 1] = None
        player_locked.pop(assigned_id, None)
        player_names.pop(assigned_id, None)
        active = [i+1 for i in range(4) if player_slots[i]]"""

good_cleanup = """    # Cleanup — only free if this socket still owns the slot
    with lobby_lock:
        if player_slots[assigned_id - 1] and player_slots[assigned_id - 1]["sock"] is sock:
            player_slots[assigned_id - 1] = None
            player_locked.pop(assigned_id, None)
            player_names.pop(assigned_id, None)
        active = [i+1 for i in range(4) if player_slots[i]]"""

code = code.replace(bad_cleanup, good_cleanup)

with open("serve_game.py", "w") as f:
    f.write(code)
