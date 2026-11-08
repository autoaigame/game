extends TestCase

## The whistle's sound (client/sound_director.gd whistle): one of several variants, never the same twice
## in a row for a player; mine plays flat, another player's from where it stands and fades with distance.

const SoundDirector := "res://client/sound_director.gd"


class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal snapshot_received(players: Array)
	signal creatures_received(creatures: Array)
	signal marks_received(marks: Array)
	signal whistled(peer_id: int)
	var my_peer_id := 1

	func request_move(_cell: Vector2i) -> void:
		pass

	func request_stop() -> void:
		pass


class FakeSounds:
	extends Node
	var heard: Array = []

	func whistle(peer_id: int, is_me: bool, at: Node2D) -> void:
		heard.append([peer_id, is_me, at])

	func footstep(_peer_id: int, _tile: int, _is_me: bool, _at: Node2D) -> void:
		pass

	func set_listener_cell(_cell: Vector2i) -> void:
		pass


func _director() -> Node:
	var d: Node = load(SoundDirector).new()
	d._sounds_cfg = Footsteps.read_data()
	d.started = true
	return d


## Frees the director and its debug overlay (only parented in _ready, which these tests skip).
func _free(d: Node) -> void:
	d._debug_label.free()
	d._debug.free()
	d.free()


## data/sounds.json lists several whistles, and every one exists.
func test_whistles_are_in_the_data() -> void:
	var paths: Array = (load(SoundDirector) as GDScript).whistle_paths(Footsteps.read_data())
	assert_true(paths.size() >= 3, "%d whistles" % paths.size())
	for p in paths:
		assert_true(ResourceLoader.exists(p), p)


## Mine plays on the Effets bus, not placed in the world.
func test_my_whistle_plays_flat() -> void:
	var d := _director()
	var p: Node = d.whistle(1, true, null)
	assert_true(p is AudioStreamPlayer, "a flat player")
	assert_eq(p.get_parent(), d)
	assert_eq(p.bus, &"Effets")
	assert_true(p.autoplay and p.stream != null)
	_free(d)


## Another player's plays from where it stands, and fades out with distance.
func test_others_whistle_comes_from_them() -> void:
	var d := _director()
	var them := Node2D.new()
	var p: Node = d.whistle(2, false, them)
	assert_true(p is AudioStreamPlayer2D, "a positional player")
	assert_eq(p.get_parent(), them)
	assert_eq(p.bus, &"Effets")
	assert_almost(p.max_distance, d.OTHERS_WHISTLE_RANGE_PX)
	them.free()
	_free(d)


## The same player never whistles the same variant twice in a row, and every variant comes up.
func test_whistle_never_repeats_twice_in_a_row() -> void:
	var d := _director()
	d._rng.seed = 7
	var n: int = d.whistle_paths(Footsteps.read_data()).size()
	var seen := {}
	var last: AudioStream = null
	for i in 60:
		var p: Node = d.whistle(1, true, null)
		assert_true(p.stream != last, "repeat at %d" % i)
		last = p.stream
		seen[p.stream] = true
	assert_eq(seen.size(), n)
	_free(d)


## Before the sound starts (the browser waits for a click), a whistle plays nothing.
func test_silent_before_start() -> void:
	var d := _director()
	d.started = false
	assert_eq(d.whistle(1, true, null), null)
	assert_eq(d.get_child_count(), 0)
	_free(d)


## The client whistles at once for me (no wait for the server), and passes on the others' whistles
## unless they are stale (client/client.gd).
func test_client_signals_whistles() -> void:
	var c: Node = load("res://client/client.gd").new()
	c.my_peer_id = 5
	var got := []
	c.whistled.connect(func(id): got.append(id))
	c.request_whistle()
	c.on_whistled(8)
	c.begin_resync()
	c.on_whistled(9)
	assert_eq(got, [5, 8])
	c.free()


## The world view plays a whistle from the player who whistled, if it is drawn.
func test_world_view_plays_the_whistle_from_the_player() -> void:
	var view: Node2D = load("res://client/world_view.gd").new()
	view.client = FakeClient.new()
	view.add_child(view.client)
	var sounds := FakeSounds.new()
	view.sounds = sounds
	view._ready()
	for id in [1, 2]:  # drawn players (plain nodes: a snapshot would build their 3D models)
		view._actors[id] = Node2D.new()
		view.add_child(view._actors[id])
	view.client.whistled.emit(1)
	view.client.whistled.emit(2)
	view.client.whistled.emit(3)  # not drawn: not heard
	assert_eq(sounds.heard.size(), 2)
	assert_eq(sounds.heard[0][0], 1)
	assert_true(sounds.heard[0][1], "mine")
	assert_eq(sounds.heard[1][0], 2)
	assert_false(sounds.heard[1][1])
	assert_eq(sounds.heard[1][2], view._actors[2])
	sounds.free()
	view.free()
