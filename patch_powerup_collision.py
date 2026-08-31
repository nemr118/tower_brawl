with open("scripts/arena.gd", "r") as f:
    code = f.read()

code = code.replace("powerup_node.global_position = Vector2(px, py)", "powerup_node.global_position = Vector2(px, py)\n\tpowerup_node.collision_mask = 2")

with open("scripts/arena.gd", "w") as f:
    f.write(code)
