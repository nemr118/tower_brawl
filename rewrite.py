with open("scripts/character_select.gd", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    # Emojis in strings
    line = line.replace('✅ ', '')
    line = line.replace('💥 ', '')
    line = line.replace('⚡ ', '')
    
    # In _update_player_card
    if 'icon_lbl.text = "✖️"' in line:
        line = line.replace('icon_lbl.text = "✖️"', 'if card.has_node("IconTex"): card.get_node("IconTex").texture = load("res://assets/icons/empty.jpg")')
    elif 'icon_lbl.text = c_info["icon"]' in line:
        line = line.replace('icon_lbl.text = c_info["icon"]', 'if card.has_node("IconTex"): card.get_node("IconTex").texture = load(c_info["icon_tex"])')
    elif 'icon_lbl.text = "🔒"' in line:
        line = line.replace('icon_lbl.text = "🔒"', 'if card.has_node("IconTex"): card.get_node("IconTex").texture = load("res://assets/icons/locked.jpg")')
    elif 'icon_lbl.text = cur_c_info["icon"]' in line:
        line = line.replace('icon_lbl.text = cur_c_info["icon"]', 'if card.has_node("IconTex"): card.get_node("IconTex").texture = load(cur_c_info["icon_tex"])')
    elif 'icon_lbl.text = "⏳"' in line:
        line = line.replace('icon_lbl.text = "⏳"', 'if card.has_node("IconTex"): card.get_node("IconTex").texture = load("res://assets/icons/waiting.jpg")')
    elif 'var icon_lbl = card.get_node("Icon")' in line:
        line = line.replace('var icon_lbl = card.get_node("Icon")', 'var icon_lbl = card.get_node_or_null("Icon")')
    
    new_lines.append(line)

with open("scripts/character_select.gd", "w") as f:
    f.writelines(new_lines)
