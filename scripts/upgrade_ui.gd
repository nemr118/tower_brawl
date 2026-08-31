extends SceneTree

func _init():
	var scene = load("res://scenes/character_select.tscn")
	var root = scene.instantiate()
	
	# 1. Update the Main Showcase
	var showcase = root.get_node("UI/MainContainer/ShowcasePanel/VBox")
	var name_lbl = showcase.get_node("NameLabel")
	
	# Add a TextureRect next to the NameLabel, or wrap them in an HBoxContainer
	var hbox = HBoxContainer.new()
	hbox.name = "TitleHBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	showcase.add_child(hbox)
	showcase.move_child(hbox, name_lbl.get_index())
	
	showcase.remove_child(name_lbl)
	
	var class_icon = TextureRect.new()
	class_icon.name = "ClassIcon"
	class_icon.custom_minimum_size = Vector2(48, 48)
	class_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	class_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(class_icon)
	hbox.add_child(name_lbl)
	
	# 2. Update the Player Cards
	var roster = root.get_node("UI/MainContainer/RosterPanel/VBox")
	for i in range(1, 5):
		var card = roster.get_node("PlayerCard" + str(i))
		if card:
			var icon_lbl = card.get_node("Icon")
			var tex_rect = TextureRect.new()
			tex_rect.name = "IconRect"
			tex_rect.custom_minimum_size = Vector2(32, 32)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			
			var parent = icon_lbl.get_parent()
			parent.add_child(tex_rect)
			parent.move_child(tex_rect, icon_lbl.get_index())
			parent.remove_child(icon_lbl)
			icon_lbl.free()

	# Pack and save
	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://scenes/character_select.tscn")
	print("Scene updated successfully!")
	quit()
