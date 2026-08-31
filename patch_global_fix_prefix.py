import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

code = code.replace('var my_action = prefix + action_suffix', 'var my_action = "p" + str(my_player_id) + "_" + action_suffix')

with open("scripts/global.gd", "w") as f:
    f.write(code)

