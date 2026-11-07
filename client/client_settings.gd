## Player settings kept in the browser (IndexedDB on the web) or user:// on desktop.
## Storage may be missing or not persistent (private browsing): reading then gives defaults.
class_name ClientSettings
extends RefCounted

const PATH := "user://settings.cfg"


## The last name the server accepted, or "" if none or unusable.
static func load_name(path := PATH) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var value: Variant = cfg.get_value("player", "name", "")
	if typeof(value) != TYPE_STRING or Protocol.validate_name(value) != "":
		return ""
	return value


static func save_name(player_name: String, path := PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep other settings; a missing file is fine
	cfg.set_value("player", "name", player_name)
	cfg.save(path)  # failure (no storage) is silent: the name is just not remembered
