extends TestCase

const PATH := "user://test_settings.cfg"


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_missing_file_gives_an_empty_name() -> void:
	_clean()
	assert_eq(ClientSettings.load_name(PATH), "")


func test_saved_name_is_read_back() -> void:
	_clean()
	ClientSettings.save_name("Corbeau_42", PATH)
	assert_eq(ClientSettings.load_name(PATH), "Corbeau_42")
	ClientSettings.save_name("ann", PATH)
	assert_eq(ClientSettings.load_name(PATH), "ann")
	_clean()


## A stored name that the server would refuse is not pre-filled.
func test_invalid_stored_name_is_ignored() -> void:
	_clean()
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", "a b")
	cfg.save(PATH)
	assert_eq(ClientSettings.load_name(PATH), "")
	cfg.set_value("player", "name", 42)
	cfg.save(PATH)
	assert_eq(ClientSettings.load_name(PATH), "")
	_clean()


func test_audio_defaults_when_missing() -> void:
	_clean()
	var a := ClientSettings.load_audio(PATH)
	assert_eq(a["muted"], false)
	assert_almost(a["volume"], ClientSettings.DEFAULT_VOLUME, 0.0001)


func test_audio_settings_are_read_back_and_keep_the_name() -> void:
	_clean()
	ClientSettings.save_name("ann", PATH)
	ClientSettings.save_audio(true, 0.3, PATH)
	var a := ClientSettings.load_audio(PATH)
	assert_eq(a["muted"], true)
	assert_almost(a["volume"], 0.3, 0.0001)
	assert_eq(ClientSettings.load_name(PATH), "ann")
	_clean()


## A volume out of range or of the wrong type is clamped or ignored.
func test_bad_stored_volume_is_fixed() -> void:
	_clean()
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", 7.0)
	cfg.set_value("audio", "muted", "yes")
	cfg.save(PATH)
	var a := ClientSettings.load_audio(PATH)
	assert_almost(a["volume"], 1.0, 0.0001)
	assert_eq(a["muted"], false)
	cfg.set_value("audio", "volume", "loud")
	cfg.save(PATH)
	assert_almost(ClientSettings.load_audio(PATH)["volume"], ClientSettings.DEFAULT_VOLUME, 0.0001)
	_clean()
