extends TestCase

const PATH := "user://test_settings.cfg"


func _clean() -> void:
	ClientSettings.session_name = ""  # a failed test_session_name_is_not_saved must not leak into the others
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
	assert_almost(a["master"], ClientSettings.DEFAULT_VOLUME, 0.0001)


func test_audio_settings_are_read_back_and_keep_the_name() -> void:
	_clean()
	ClientSettings.save_name("ann", PATH)
	var s := AudioSettings.defaults()
	s["muted"] = true
	s["master"] = 0.3
	ClientSettings.save_audio(s, PATH)
	var a := ClientSettings.load_audio(PATH)
	assert_eq(a["muted"], true)
	assert_almost(a["master"], 0.3, 0.0001)
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
	assert_almost(a["master"], 1.0, 0.0001)
	assert_eq(a["muted"], false)
	cfg.set_value("audio", "volume", "loud")
	cfg.save(PATH)
	assert_almost(ClientSettings.load_audio(PATH)["master"], ClientSettings.DEFAULT_VOLUME, 0.0001)
	_clean()


## The look is remembered; parts gone from the data since are repaired, a broken entry gives the default.
func test_look_is_kept_and_repaired() -> void:
	_clean()
	assert_eq(ClientSettings.load_look(PATH), CharacterParts.default_look())
	var look := [{"id": "body_standard", "color": "skin_dark"}, {"id": "face_young", "color": "hair_red"},
			{"id": "top_tshirt", "color": "olive"},
			{"id": "bottom_shorts", "color": "grey"}]
	ClientSettings.save_look(look, PATH)
	assert_eq(ClientSettings.load_look(PATH), look)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("player", "look", '[{"id":"body_standard","color":"skin_dark"},{"id":"gone_hat","color":"x"}]')
	cfg.save(PATH)
	var repaired := ClientSettings.load_look(PATH)
	assert_eq(CharacterParts.validate(repaired), "")
	assert_eq(repaired[0], {"id": "body_standard", "color": "skin_dark"})
	cfg.set_value("player", "look", "{not json")
	cfg.save(PATH)
	assert_eq(ClientSettings.load_look(PATH), CharacterParts.default_look())
	_clean()


## A name from the page's ?name= is for this session only: it never replaces the saved one.
func test_session_name_is_not_saved() -> void:
	_clean()
	ClientSettings.save_name("Corbeau_42", PATH)
	ClientSettings.session_name = "Visiteur"
	ClientSettings.save_name("Visiteur", PATH)
	assert_eq(ClientSettings.load_name(PATH), "Corbeau_42")
	# A name typed in the start menu instead (the session name was refused, say) is saved as usual.
	ClientSettings.save_name("ann", PATH)
	assert_eq(ClientSettings.load_name(PATH), "ann")
	ClientSettings.session_name = ""
	_clean()
