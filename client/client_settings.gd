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


## {muted: bool, volume: 0..1}: sound settings, defaults when missing or unusable.
static func load_audio(path := PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {"muted": false, "volume": DEFAULT_VOLUME}
	if cfg.load(path) != OK:
		return out
	var muted: Variant = cfg.get_value("audio", "muted", false)
	if typeof(muted) == TYPE_BOOL:
		out["muted"] = muted
	var volume: Variant = cfg.get_value("audio", "volume", DEFAULT_VOLUME)
	if typeof(volume) == TYPE_FLOAT or typeof(volume) == TYPE_INT:
		out["volume"] = clampf(float(volume), 0.0, 1.0)
	return out


static func save_audio(muted: bool, volume: float, path := PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "volume", clampf(volume, 0.0, 1.0))
	cfg.save(path)
