## `make art` entry point. Most of the game's art comes from the PixelLab kit (see docs/art-guide.md
## and ASSETS.toml) and is copied as it is. The dog sheet (assets/dog.png) is drawn here by
## art/dog_sheet.gd, the bag's icons by art/ui_icons.gd, the menu art by art/ui_menu.gd. Usage: godot --headless --path . -s res://art/gen_art.gd   (or: make art)
extends SceneTree

const DOG_SHEET := preload("res://art/dog_sheet.gd")
const UI_ICONS := preload("res://art/ui_icons.gd")
const UI_MENU := preload("res://art/ui_menu.gd")


func _initialize() -> void:
	var err := DOG_SHEET.sheet().save_png("res://assets/dog.png")
	if err != OK:
		push_error("art: cannot write assets/dog.png (%s)" % error_string(err))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/items"))
	var icons: Dictionary = UI_ICONS.all()
	icons.merge(UI_MENU.all())
	for path in icons:
		err = (icons[path] as Image).save_png(path)
		if err != OK:
			push_error("art: cannot write %s (%s)" % [path, error_string(err)])
			quit(1)
			return
	print("art: wrote assets/dog.png, the bag's icons and the menu art (art/ui_menu.gd); the rest of assets/ comes from the PixelLab kit (docs/art-guide.md)")
	quit()
