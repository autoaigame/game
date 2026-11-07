## `make art` entry point. Most of the game's art comes from the PixelLab kit (see docs/art-guide.md
## and ASSETS.toml) and is copied as it is. The dog sheet (assets/dog.png) is drawn here by
## art/dog_sheet.gd. Usage: godot --headless --path . -s res://art/gen_art.gd   (or: make art)
extends SceneTree

const DOG_SHEET := preload("res://art/dog_sheet.gd")


func _initialize() -> void:
	var err := DOG_SHEET.sheet().save_png("res://assets/dog.png")
	if err != OK:
		push_error("art: cannot write assets/dog.png (%s)" % error_string(err))
		quit(1)
		return
	print("art: wrote assets/dog.png; the rest of assets/ comes from the PixelLab kit (docs/art-guide.md)")
	quit()
