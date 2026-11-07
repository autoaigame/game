## Player persistence in SQLite (server only: the web build never loads this file).
extends RefCounted

var _db: SQLite


func open(path: String) -> bool:
	_db = SQLite.new()
	_db.path = path
	_db.verbosity_level = SQLite.QUIET
	if not _db.open_db():
		push_error("db: cannot open %s: %s" % [path, _db.error_message])
		return false
	return _db.query("CREATE TABLE IF NOT EXISTS players (name TEXT PRIMARY KEY, x INTEGER NOT NULL, y INTEGER NOT NULL, updated_at INTEGER NOT NULL);") \
			and _db.query("CREATE TABLE IF NOT EXISTS stats (name TEXT NOT NULL, key TEXT NOT NULL, value REAL NOT NULL, PRIMARY KEY (name, key));")


## Returns the saved cell (Vector2i) or null if the player is unknown.
func load_player(player_name: String) -> Variant:
	_db.query_with_bindings("SELECT x, y FROM players WHERE name = ?;", [player_name])
	if _db.query_result.is_empty():
		return null
	var row: Dictionary = _db.query_result[0]
	return Vector2i(int(row["x"]), int(row["y"]))


func save_player(player_name: String, cell: Vector2i) -> void:
	var ok := _db.query_with_bindings(
		"INSERT INTO players (name, x, y, updated_at) VALUES (?, ?, ?, ?) "
		+ "ON CONFLICT(name) DO UPDATE SET x = excluded.x, y = excluded.y, updated_at = excluded.updated_at;",
		[player_name, cell.x, cell.y, int(Time.get_unix_time_from_system())])
	if not ok:
		push_error("db: save failed: %s" % _db.error_message)


## A player's saved numbers (hunger, ...): key -> float. {} if none.
func load_stats(player_name: String) -> Dictionary:
	_db.query_with_bindings("SELECT key, value FROM stats WHERE name = ?;", [player_name])
	var out := {}
	for row in _db.query_result:
		out[String(row["key"])] = float(row["value"])
	return out


func save_stats(player_name: String, stats: Dictionary) -> void:
	for key in stats:
		var ok := _db.query_with_bindings(
			"INSERT INTO stats (name, key, value) VALUES (?, ?, ?) "
			+ "ON CONFLICT(name, key) DO UPDATE SET value = excluded.value;",
			[player_name, String(key), float(stats[key])])
		if not ok:
			push_error("db: save stats failed: %s" % _db.error_message)


func close() -> void:
	if _db != null:
		_db.close_db()
		_db = null
