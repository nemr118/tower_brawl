import re

with open("project.godot", "r") as f:
    text = f.read()

# Replace p1_attack
p1_attack_new = """p1_attack={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}"""
text = re.sub(r'p1_attack=\{[^}]+\}', p1_attack_new, text)

# Replace p1_special
p1_special_new = """p1_special={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":2,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}"""
text = re.sub(r'p1_special=\{[^}]+\}', p1_special_new, text)

# Replace p1_dash
p1_dash_new = """p1_dash={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":32,"physical_keycode":0,"key_label":0,"unicode":32,"location":0,"echo":false,"script":null)
]
}"""
text = re.sub(r'p1_dash=\{[^}]+\}', p1_dash_new, text)

with open("project.godot", "w") as f:
    f.write(text)

