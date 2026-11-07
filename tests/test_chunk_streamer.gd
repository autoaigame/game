extends TestCase

## Which chunks the client loads, builds and frees around the player (client/chunk_streamer.gd).


func _streamer() -> ChunkStreamer:
	return ChunkStreamer.new(2, 3, 1)


func test_wanted_chunks_cover_the_radius_nearest_first() -> void:
	var w := ChunkStreamer.wanted_chunks(Vector2i(0, 0), 2)
	assert_eq(w.size(), 25)
	assert_eq(w[0], Vector2i(0, 0), "the player's own chunk first")
	for c in w:
		assert_true(absi(c.x) <= 2 and absi(c.y) <= 2, str(c))
	for i in range(1, w.size()):
		assert_true(Vector2(w[i]).length_squared() >= Vector2(w[i - 1]).length_squared(), "not sorted at %d" % i)


func test_chunk_of_cell_negative() -> void:
	var w := ChunkStreamer.wanted_chunks(Vector2i(-1, -1), 0)
	assert_eq(w, [Vector2i(-1, -1)])


func test_update_queues_missing_chunks_once() -> void:
	var s := _streamer()
	s.update(Vector2i(5, 5))  # chunk (0, 0)
	assert_eq(s.pending_count(), 25)
	s.update(Vector2i(6, 5))  # same chunk: nothing new
	assert_eq(s.pending_count(), 25)


func test_budget_limits_builds_per_frame() -> void:
	var s := ChunkStreamer.new(2, 3, 3)
	s.update(Vector2i(0, 0))
	var first := s.take_builds()
	assert_eq(first.size(), 3)
	assert_eq(first[0], Vector2i(0, 0), "nearest first")
	assert_eq(s.pending_count(), 22)
	var built := first.size()
	for frame in 20:
		var b := s.take_builds()
		assert_true(b.size() <= 3)
		built += b.size()
	assert_eq(built, 25)
	assert_eq(s.loaded_count(), 25)
	assert_eq(s.take_builds(), [] as Array[Vector2i])


## Chunks beyond the unload radius are freed; within it they stay (no flicker at a border).
func test_far_chunks_unload_with_hysteresis() -> void:
	var s := ChunkStreamer.new(2, 3, 100)
	s.update(Vector2i(0, 0))
	s.take_builds()
	# one chunk east: the west column (x = -2) is at distance 3, still kept
	var freed := s.update(Vector2i(MapData.CHUNK, 0))
	assert_eq(freed, [] as Array[Vector2i])
	# two more east: x = -2 and x = -1 are now farther than 3
	freed = s.update(Vector2i(3 * MapData.CHUNK, 0))
	assert_eq(freed.size(), 10)
	for c in freed:
		assert_true(c.x <= -1, str(c))
		assert_false(s.is_loaded(c))


## A chunk that leaves the radius before it was built is dropped from the queue, not built.
func test_pending_far_chunks_are_dropped() -> void:
	var s := ChunkStreamer.new(1, 1, 1)
	s.update(Vector2i(0, 0))
	s.take_builds()
	s.update(Vector2i(10 * MapData.CHUNK, 0))
	for frame in 20:
		for c in s.take_builds():
			assert_true(absi(c.x - 10) <= 1, "built far chunk %s" % c)
