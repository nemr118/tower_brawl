# Fix global.gd missing signal
with open("scripts/global.gd", "r") as f:
    g_code = f.read()
if "signal net_force_start" not in g_code:
    g_code = g_code.replace("signal net_names_updated()", "signal net_names_updated()\nsignal net_force_start()")
with open("scripts/global.gd", "w") as f:
    f.write(g_code)

# Fix character_select.gd LineEdit bug
with open("scripts/character_select.gd", "r") as f:
    c_code = f.read()

c_code = c_code.replace("""func _on_name_submit_text(t: String):
	_on_name_submit(name_input_ui.get_node("VBoxContainer/LineEdit"))

func _on_name_submit(edit: LineEdit):
	var n = edit.text.strip_edges()""", """func _on_name_submit_text(t: String):
	_confirm_name_and_close(t)

func _on_name_submit(edit: LineEdit):
	_confirm_name_and_close(edit.text)
	
func _confirm_name_and_close(text_val: String):
	var n = text_val.strip_edges()""")
with open("scripts/character_select.gd", "w") as f:
    f.write(c_code)
