## `make art` entry point. All of the game's art now comes from the PixelLab kit (see docs/art-guide.md
## and ASSETS.toml): the ground atlas, objects, decals and the player sheet are copied as they are, so
## there is nothing left to generate. The generators of the earlier provisional art are in the git
## history of this file. Usage: godot --headless --path . -s res://art/gen_art.gd   (or: make art)
extends SceneTree


func _initialize() -> void:
	print("art: nothing to generate; assets/ comes from the PixelLab kit (docs/art-guide.md)")
	quit()
