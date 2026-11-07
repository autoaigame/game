extends TestCase

## Hunger (server/hunger.gd, server/server.gd): drops slowly; at 0 the player walks slower.

const HUNGER := preload("res://server/hunger.gd")
const SERVER_SCRIPT := "res://server/server.gd"


func test_drops_one_point_per_period() -> void:
	assert_almost(HUNGER.tick(100.0, HUNGER.SECONDS_PER_POINT), 99.0)
	assert_almost(HUNGER.tick(100.0, HUNGER.SECONDS_PER_POINT * 10.0), 90.0)


func test_never_below_zero() -> void:
	assert_eq(HUNGER.tick(0.5, HUNGER.SECONDS_PER_POINT * 5.0), 0.0)


func test_starving_walks_slower() -> void:
	assert_eq(HUNGER.speed_factor(50.0), 1.0)
	assert_eq(HUNGER.speed_factor(0.01), 1.0)
	assert_eq(HUNGER.speed_factor(0.0), HUNGER.STARVING_SPEED)
	assert_true(HUNGER.STARVING_SPEED > 0.0 and HUNGER.STARVING_SPEED < 1.0)


func _server_with(hunger: float) -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	var at := MapData.spawn_cell()
	server._players[1] = server._new_player("ann", at, {"hunger": hunger})
	server._players[1]["target"] = at + Vector2i(10, 0)
	return server


## A starving player covers less ground in the same time (invariant 3 still holds: never faster).
func test_server_moves_starving_players_slower() -> void:
	var fed := _server_with(80.0)
	var starving := _server_with(0.0)
	fed._move_players(0.5)
	starving._move_players(0.5)
	var start := Vector2(MapData.spawn_cell())
	var a: float = fed._players[1]["pos"].distance_to(start)
	var b: float = starving._players[1]["pos"].distance_to(start)
	assert_almost(b, a * HUNGER.STARVING_SPEED, 0.05)
	fed.free()
	starving.free()


func test_server_hunger_drops_each_tick() -> void:
	var server := _server_with(50.0)
	server._tick_hunger(HUNGER.SECONDS_PER_POINT)
	assert_almost(server._players[1]["hunger"], 49.0)
	server.free()


## A new player starts full; a returning one keeps their saved hunger.
func test_new_player_starts_full_and_saved_hunger_is_kept() -> void:
	var server: Node = load(SERVER_SCRIPT).new()
	assert_eq(server._new_player("ann", Vector2i.ZERO, {})["hunger"], HUNGER.MAX)
	assert_eq(server._new_player("bob", Vector2i.ZERO, {"hunger": 12.5})["hunger"], 12.5)
	server.free()


## Clients get their own hunger as a whole number, only when it changes.
func test_status_sent_when_the_shown_value_changes() -> void:
	var server := _server_with(50.0)
	var p: Dictionary = server._players[1]
	assert_eq(server._status_to_send(p), {"hunger": 50})
	assert_eq(server._status_to_send(p), {}, "unchanged: nothing to send")
	p["hunger"] = 49.7
	assert_eq(server._status_to_send(p), {}, "still shows 50")
	p["hunger"] = 49.2
	assert_eq(server._status_to_send(p), {"hunger": 49})
	server.free()
