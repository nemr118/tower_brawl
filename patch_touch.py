import os

with open("scripts/touch_controls.gd", "r") as f:
    code = f.read()

code = code.replace("var my_input_prefix: String = \"p1_\"", "")
code = code.replace("func _ready():", "func _ready():\n\tGlobal.connect(\"net_connected\", Callable(self, \"_on_net_connected\"))")

new_func = """
var my_input_prefix: String = "p1_"

func _on_net_connected(id: int):
	my_input_prefix = "p" + str(id) + "_"
"""

code = code.replace("func _update_base_center():", new_func + "\nfunc _update_base_center():")

with open("scripts/touch_controls.gd", "w") as f:
    f.write(code)

