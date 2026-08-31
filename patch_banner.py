with open("scripts/arena.gd", "r") as f:
    code = f.read()

code = code.replace("""	var banner = banner_label
	banner.text = "🌀 ARENA SHIFT! 🌀"
	banner.visible = true
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(platforms_node, "rotation", platforms_node.rotation + PI, 2.5)
	
	await get_tree().create_timer(2.5).timeout
	banner.visible = false
	is_arena_rotating = false""", """	_show_banner("🌀 ARENA SHIFT! 🌀", 2.5)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(platforms_node, "rotation", platforms_node.rotation + PI, 2.5)
	
	await get_tree().create_timer(2.5).timeout
	is_arena_rotating = false""")

with open("scripts/arena.gd", "w") as f:
    f.write(code)
