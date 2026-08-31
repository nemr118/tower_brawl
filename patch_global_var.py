import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

code = code.replace("extends Node", "extends Node\n\nvar is_mobile: bool = false")

with open("scripts/global.gd", "w") as f:
    f.write(code)

