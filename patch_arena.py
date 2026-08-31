import re

with open("scenes/arena.tscn", "r") as f:
    text = f.read()

# Replace the sub_resource for ground
text = text.replace('size = Vector2(640, 50)', 'size = Vector2(160, 50)')

platforms_str = """[node name="Platforms" type="Node2D" parent="."]
position = Vector2(320, 180)

[node name="GroundLeft" type="StaticBody2D" parent="Platforms"]
position = Vector2(-140, 155)
collision_mask = 0

[node name="VisualBase" type="ColorRect" parent="Platforms/GroundLeft"]
offset_left = -80.0
offset_top = -25.0
offset_right = 80.0
offset_bottom = 25.0
color = Color(0.2, 0.22, 0.28, 1)

[node name="GrassTrim" type="ColorRect" parent="Platforms/GroundLeft"]
offset_left = -80.0
offset_top = -25.0
offset_right = 80.0
offset_bottom = -21.0
color = Color(0.4, 0.75, 0.4, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Platforms/GroundLeft"]
shape = SubResource("RectangleShape2D_ground")

[node name="GroundRight" type="StaticBody2D" parent="Platforms"]
position = Vector2(140, 155)
collision_mask = 0

[node name="VisualBase" type="ColorRect" parent="Platforms/GroundRight"]
offset_left = -80.0
offset_top = -25.0
offset_right = 80.0
offset_bottom = 25.0
color = Color(0.2, 0.22, 0.28, 1)

[node name="GrassTrim" type="ColorRect" parent="Platforms/GroundRight"]
offset_left = -80.0
offset_top = -25.0
offset_right = 80.0
offset_bottom = -21.0
color = Color(0.4, 0.75, 0.4, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Platforms/GroundRight"]
shape = SubResource("RectangleShape2D_ground")

[node name="LedgeLeft" type="StaticBody2D" parent="Platforms"]
position = Vector2(-210, 50)
collision_mask = 0

[node name="VisualBase" type="ColorRect" parent="Platforms/LedgeLeft"]
offset_left = -55.0
offset_top = -6.0
offset_right = 55.0
offset_bottom = 6.0
color = Color(0.35, 0.25, 0.2, 1)

[node name="WoodTrim" type="ColorRect" parent="Platforms/LedgeLeft"]
offset_left = -55.0
offset_top = -6.0
offset_right = 55.0
offset_bottom = -4.0
color = Color(0.65, 0.5, 0.35, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Platforms/LedgeLeft"]
shape = SubResource("RectangleShape2D_ledge")

[node name="LedgeRight" type="StaticBody2D" parent="Platforms"]
position = Vector2(210, 50)
collision_mask = 0

[node name="VisualBase" type="ColorRect" parent="Platforms/LedgeRight"]
offset_left = -55.0
offset_top = -6.0
offset_right = 55.0
offset_bottom = 6.0
color = Color(0.35, 0.25, 0.2, 1)

[node name="WoodTrim" type="ColorRect" parent="Platforms/LedgeRight"]
offset_left = -55.0
offset_top = -6.0
offset_right = 55.0
offset_bottom = -4.0
color = Color(0.65, 0.5, 0.35, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Platforms/LedgeRight"]
shape = SubResource("RectangleShape2D_ledge")

[node name="LedgeHighLeft" type="StaticBody2D" parent="Platforms"]
position = Vector2(-150, -40)
collision_mask = 0

[node name="VisualBase" type="ColorRect" parent="Platforms/LedgeHighLeft"]
offset_left = -45.0
offset_top = -6.0
offset_right = 45.0
offset_bottom = 6.0
color = Color(0.35, 0.25, 0.2, 1)

[node name="WoodTrim" type="ColorRect" parent="Platforms/LedgeHighLeft"]
offset_left = -45.0
offset_top = -6.0
offset_right = 45.0
offset_bottom = -4.0
color = Color(0.65, 0.5, 0.35, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Platforms/LedgeHighLeft"]
shape = SubResource("RectangleShape2D_high_ledge")

[node name="LedgeHighRight" type="StaticBody2D" parent="Platforms"]
position = Vector2(150, -40)
collision_mask = 0

[node name="VisualBase" type="ColorRect" parent="Platforms/LedgeHighRight"]
offset_left = -45.0
offset_top = -6.0
offset_right = 45.0
offset_bottom = 6.0
color = Color(0.35, 0.25, 0.2, 1)

[node name="WoodTrim" type="ColorRect" parent="Platforms/LedgeHighRight"]
offset_left = -45.0
offset_top = -6.0
offset_right = 45.0
offset_bottom = -4.0
color = Color(0.65, 0.5, 0.35, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Platforms/LedgeHighRight"]
shape = SubResource("RectangleShape2D_high_ledge")

[node name="CenterTower" type="StaticBody2D" parent="Platforms"]
position = Vector2(0, 5)
collision_mask = 0

[node name="VisualBase" type="ColorRect" parent="Platforms/CenterTower"]
offset_left = -65.0
offset_top = -7.0
offset_right = 65.0
offset_bottom = 7.0
color = Color(0.35, 0.25, 0.2, 1)

[node name="WoodTrim" type="ColorRect" parent="Platforms/CenterTower"]
offset_left = -65.0
offset_top = -7.0
offset_right = 65.0
offset_bottom = -5.0
color = Color(0.65, 0.5, 0.35, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Platforms/CenterTower"]
shape = SubResource("RectangleShape2D_center")

[node name="CenterApex" type="StaticBody2D" parent="Platforms"]
position = Vector2(0, -85)
collision_mask = 0

[node name="VisualBase" type="ColorRect" parent="Platforms/CenterApex"]
offset_left = -40.0
offset_top = -5.0
offset_right = 40.0
offset_bottom = 5.0
color = Color(0.35, 0.25, 0.2, 1)

[node name="WoodTrim" type="ColorRect" parent="Platforms/CenterApex"]
offset_left = -40.0
offset_top = -5.0
offset_right = 40.0
offset_bottom = -3.0
color = Color(0.65, 0.5, 0.35, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Platforms/CenterApex"]
shape = SubResource("RectangleShape2D_apex")
"""

start_idx = text.find('[node name="Platforms" type="Node2D" parent="."]')
end_idx = text.find('[node name="HUD" type="CanvasLayer" parent="."]')

if start_idx != -1 and end_idx != -1:
    text = text[:start_idx] + platforms_str + "\n" + text[end_idx:]
    with open("scenes/arena.tscn", "w") as f:
        f.write(text)
    print("Patch applied")
else:
    print("Could not find start/end")

