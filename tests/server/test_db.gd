extends TestCase

const DB_SCRIPT := "res://server/db.gd"


func _tmp_path() -> String:
	return OS.get_cache_dir().path_join("autoaigame_test_%d.db" % Time.get_ticks_usec())


func _db() -> Object:
	return load(DB_SCRIPT).new()


func test_unknown_player_is_null() -> void:
	var db := _db()
	assert_true(db.open(_tmp_path()))
	assert_eq(db.load_player("ann"), null)
	db.close()


func test_save_then_load() -> void:
	var db := _db()
	db.open(_tmp_path())
	db.save_player("ann", Vector2i(3, 4))
	assert_eq(db.load_player("ann"), Vector2i(3, 4))
	db.save_player("ann", Vector2i(5, 6))
	assert_eq(db.load_player("ann"), Vector2i(5, 6))
	db.close()


func test_survives_reopen() -> void:
	var path := _tmp_path()
	var db := _db()
	db.open(path)
	db.save_player("ann", Vector2i(5, 6))
	db.close()
	var db2 := _db()
	assert_true(db2.open(path))
	assert_eq(db2.load_player("ann"), Vector2i(5, 6))
	db2.close()


func test_injection_name_round_trips() -> void:
	var db := _db()
	db.open(_tmp_path())
	var evil := "x'); DROP TABLE players;--"
	db.save_player(evil, Vector2i(1, 2))
	db.save_player("bob", Vector2i(7, 7))
	assert_eq(db.load_player(evil), Vector2i(1, 2))
	assert_eq(db.load_player("bob"), Vector2i(7, 7))
	db.close()
