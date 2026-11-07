## Player settings kept in the browser (IndexedDB on the web) or user:// on desktop.
## Storage may be missing or not persistent (private browsing): reading then gives defaults.
class_name ClientSettings
extends RefCounted

const PATH := "user://settings.cfg"
## Master volume (0..1) before the player sets one.
const DEFAULT_VOLUME := 0.8


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


## The sound settings (client/audio_settings.gd), defaults when missing or unusable. An older file's
## [audio] volume is read as the master level.
static func load_audio(path := PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return AudioSettings.defaults()
	return AudioSettings.read(cfg)


static func save_audio(settings: Dictionary, path := PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	AudioSettings.write(cfg, settings)
	cfg.save(path)
