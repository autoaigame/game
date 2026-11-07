## The sound settings: one level 0..1 per channel and a mute, as a plain Dictionary
## {muted: bool, master, music, ambience, effects, ui: float}. Reading, checking and writing them
## (section [audio] of user://settings.cfg, through client/client_settings.gd) and applying them to the buses.
class_name AudioSettings
extends RefCounted

const SECTION := "audio"
## In the order the settings menu shows them.
const CHANNELS: Array[String] = ["master", "music", "ambience", "effects", "ui"]
## channel -> bus. Every bus but Master sends to Master (client/sound_director.gd ensure_buses()).
const BUS := {"master": "Master", "music": "Musique", "ambience": "Ambiance", "effects": "Effets", "ui": "UI"}
## Volume of a bus at level 0, in dB (silent without -inf).
const SILENT_DB := -80.0
## Before the menu, the master level was stored under this key.
const OLD_MASTER_KEY := "volume"


static func defaults() -> Dictionary:
	return {"muted": false, "master": ClientSettings.DEFAULT_VOLUME, "music": 1.0, "ambience": 1.0,
			"effects": 1.0, "ui": 1.0}


static func label(channel: String) -> String:
	return UiText.SOUND_CHANNELS.get(channel, "")


## Volume of a bus at `level` (0..1, linear amplitude): 1 is 0 dB, 0.5 about -6 dB.
static func level_db(level: float) -> float:
	level = clampf(level, 0.0, 1.0)
	return maxf(SILENT_DB, linear_to_db(level)) if level > 0.0 else SILENT_DB


static func to_percent(level: float) -> int:
	return roundi(clampf(level, 0.0, 1.0) * 100.0)


static func from_percent(percent: float) -> float:
	return clampf(percent / 100.0, 0.0, 1.0)


## `level` moved by `delta`, on whole percents and kept in 0..1.
static func stepped(level: float, delta: float) -> float:
	return clampf(snappedf(level + delta, 0.01), 0.0, 1.0)


## The settings in `cfg`, a default for each missing or unusable value.
static func read(cfg: ConfigFile) -> Dictionary:
	var out := defaults()
	var muted: Variant = cfg.get_value(SECTION, "muted", false)
	if typeof(muted) == TYPE_BOOL:
		out["muted"] = muted
	for c in CHANNELS:
		var key := c
		if c == "master" and not cfg.has_section_key(SECTION, c):
			key = OLD_MASTER_KEY
		var v: Variant = cfg.get_value(SECTION, key, out[c])
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			out[c] = clampf(float(v), 0.0, 1.0)
	return out


## Writes `s` into `cfg`, dropping the old master key.
static func write(cfg: ConfigFile, s: Dictionary) -> void:
	var d := defaults()
	cfg.set_value(SECTION, "muted", bool(s.get("muted", false)))
	for c in CHANNELS:
		cfg.set_value(SECTION, c, clampf(float(s.get(c, d[c])), 0.0, 1.0))
	if cfg.has_section_key(SECTION, OLD_MASTER_KEY):
		cfg.erase_section_key(SECTION, OLD_MASTER_KEY)


## Sets each channel's bus volume and the master mute. A bus that does not exist yet is skipped.
static func apply(s: Dictionary) -> void:
	var d := defaults()
	for c in CHANNELS:
		var i := AudioServer.get_bus_index(BUS[c])
		if i < 0:
			continue
		AudioServer.set_bus_volume_db(i, level_db(s.get(c, d[c])))
		if c == "master":
			AudioServer.set_bus_mute(i, bool(s.get("muted", false)))
