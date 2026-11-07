extends TestCase

const PATH := "user://test_audio_settings.cfg"


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_every_channel_has_a_bus_a_default_and_a_label() -> void:
	assert_eq(AudioSettings.CHANNELS, ["master", "music", "ambience", "effects", "ui"])
	var d := AudioSettings.defaults()
	assert_eq(d["muted"], false)
	for c in AudioSettings.CHANNELS:
		assert_true(AudioSettings.BUS.has(c), c)
		assert_true(d[c] >= 0.0 and d[c] <= 1.0, c)
		assert_true(AudioSettings.label(c) != "", c)
	assert_almost(d["master"], ClientSettings.DEFAULT_VOLUME, 0.0001)
	assert_eq(AudioSettings.BUS["master"], "Master")
	assert_eq(AudioSettings.BUS["music"], "Musique")


## 100 % is 0 dB, 50 % about -6 dB, 0 % silent (not -inf).
func test_level_to_db() -> void:
	assert_almost(AudioSettings.level_db(1.0), 0.0, 0.001)
	assert_almost(AudioSettings.level_db(0.5), -6.02, 0.01)
	assert_almost(AudioSettings.level_db(0.0), AudioSettings.SILENT_DB, 0.001)
	assert_almost(AudioSettings.level_db(0.00001), AudioSettings.SILENT_DB, 0.001, "never below silent")
	assert_almost(AudioSettings.level_db(1.7), 0.0, 0.001, "clamped")


func test_percent_round_trip() -> void:
	assert_eq(AudioSettings.to_percent(0.8), 80)
	assert_eq(AudioSettings.to_percent(0.333), 33)
	assert_almost(AudioSettings.from_percent(45), 0.45, 0.0001)
	assert_almost(AudioSettings.from_percent(130), 1.0, 0.0001)
	assert_almost(AudioSettings.from_percent(-5), 0.0, 0.0001)


## The keys - and + step the master level, snapped and clamped like the menu shows it.
func test_step_snaps_and_clamps() -> void:
	assert_almost(AudioSettings.stepped(0.8, 0.1), 0.9, 0.0001)
	assert_almost(AudioSettings.stepped(0.95, 0.1), 1.0, 0.0001)
	assert_almost(AudioSettings.stepped(0.04, -0.1), 0.0, 0.0001)
	assert_almost(AudioSettings.stepped(0.33, 0.1), 0.43, 0.0001)


func test_missing_file_gives_defaults() -> void:
	_clean()
	assert_eq(ClientSettings.load_audio(PATH), AudioSettings.defaults())


func test_every_channel_is_read_back_and_the_name_kept() -> void:
	_clean()
	ClientSettings.save_name("ann", PATH)
	var s := AudioSettings.defaults()
	s["muted"] = true
	s["master"] = 0.3
	s["music"] = 0.0
	s["ambience"] = 0.55
	s["effects"] = 0.2
	s["ui"] = 0.9
	ClientSettings.save_audio(s, PATH)
	var back := ClientSettings.load_audio(PATH)
	assert_eq(back["muted"], true)
	for c in AudioSettings.CHANNELS:
		assert_almost(back[c], s[c], 0.0001, c)
	assert_eq(ClientSettings.load_name(PATH), "ann")
	_clean()


## A file from before the menu has [audio] volume for the master level: it becomes "master", the old
## key goes on the next save, and the new channels start at their defaults.
func test_old_volume_key_is_migrated() -> void:
	_clean()
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "muted", true)
	cfg.set_value("audio", "volume", 0.4)
	cfg.save(PATH)
	var s := ClientSettings.load_audio(PATH)
	assert_almost(s["master"], 0.4, 0.0001)
	assert_eq(s["muted"], true)
	assert_almost(s["ambience"], AudioSettings.defaults()["ambience"], 0.0001)
	ClientSettings.save_audio(s, PATH)
	var after := ConfigFile.new()
	after.load(PATH)
	assert_false(after.has_section_key("audio", "volume"), "old key removed")
	assert_almost(after.get_value("audio", "master"), 0.4, 0.0001)
	_clean()


## When both exist (an old client saved after a new one), "master" wins.
func test_master_key_wins_over_the_old_one() -> void:
	_clean()
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", 0.4)
	cfg.set_value("audio", "master", 0.7)
	cfg.save(PATH)
	assert_almost(ClientSettings.load_audio(PATH)["master"], 0.7, 0.0001)
	_clean()


func test_bad_stored_levels_are_fixed() -> void:
	_clean()
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", 7.0)
	cfg.set_value("audio", "music", "loud")
	cfg.set_value("audio", "effects", -1)
	cfg.set_value("audio", "ui", 1)
	cfg.set_value("audio", "muted", "yes")
	cfg.save(PATH)
	var s := ClientSettings.load_audio(PATH)
	assert_almost(s["master"], 1.0, 0.0001)
	assert_almost(s["music"], AudioSettings.defaults()["music"], 0.0001)
	assert_almost(s["effects"], 0.0, 0.0001)
	assert_almost(s["ui"], 1.0, 0.0001)
	assert_eq(s["muted"], false)
	_clean()


## Each channel drives its own bus; mute only the master one.
func test_apply_sets_every_bus() -> void:
	(load("res://client/sound_director.gd") as GDScript).ensure_buses()
	var s := AudioSettings.defaults()
	s["master"] = 0.5
	s["music"] = 0.0
	s["ambience"] = 0.25
	s["effects"] = 1.0
	s["ui"] = 0.5
	s["muted"] = true
	AudioSettings.apply(s)
	for c in AudioSettings.CHANNELS:
		var i := AudioServer.get_bus_index(AudioSettings.BUS[c])
		assert_true(i >= 0, c)
		assert_almost(AudioServer.get_bus_volume_db(i), AudioSettings.level_db(s[c]), 0.01, c)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambiance")))
	AudioSettings.apply(AudioSettings.defaults())
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))


func test_music_bus_exists_under_master() -> void:
	(load("res://client/sound_director.gd") as GDScript).ensure_buses()
	var i := AudioServer.get_bus_index("Musique")
	assert_true(i > 0)
	assert_eq(AudioServer.get_bus_send(i), &"Master")
