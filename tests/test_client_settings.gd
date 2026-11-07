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
