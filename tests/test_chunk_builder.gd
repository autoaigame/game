extends TestCase

## Runs chunk jobs under a time budget per frame (client/chunk_builder.gd). The clock is fake.


class FakeClock:
	var now := 0
	var tick := 0  ## microseconds added at each read

	func read() -> int:
		now += tick
		return now


func _builder(load_r := 0) -> ChunkBuilder:
	var s := ChunkStreamer.new(load_r, load_r + 1, 1)
	s.update(Vector2i(0, 0))
	return ChunkBuilder.new(s, null)


func test_stops_when_the_budget_is_spent() -> void:
	var b := _builder()
	var clock := FakeClock.new()
	clock.tick = 1000
	b.run(4000, clock.read)
	assert_true(b.steps_last_run >= 3 and b.steps_last_run <= 4, "about 4 ms of 1 ms steps: %d" % b.steps_last_run)
	b.drop([Vector2i(0, 0)] as Array[Vector2i])


## Even when one step takes longer than the budget, every frame moves on by one step.
func test_always_one_step_per_frame() -> void:
	var b := _builder()
	var clock := FakeClock.new()
	clock.tick = 1_000_000
	b.run(4000, clock.read)
	assert_eq(b.steps_last_run, 1)
	b.drop([Vector2i(0, 0)] as Array[Vector2i])


## With time to spare, it builds every queued chunk, and gives each node with its chunk.
func test_builds_all_queued_chunks() -> void:
	var b := _builder(1)
	var clock := FakeClock.new()
	var built := {}
	for frame in 2000:
		for pair in b.run(4000, clock.read):
			built[pair[0]] = pair[1]
		if b.pending() == 0:
			break
	assert_eq(built.size(), 9)
	for c in built:
		assert_eq(String(built[c].name), "Chunk_%d_%d" % [c.x, c.y])
		built[c].free()
	assert_eq(b.run(4000, clock.read), [])


## A chunk freed while its job runs is dropped: its job stops and gives no node.
func test_dropped_chunk_gives_no_node() -> void:
	var b := _builder()
	var clock := FakeClock.new()
	clock.tick = 1_000_000
	b.run(4000, clock.read)
	assert_eq(b.pending(), 1)
	b.drop([Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(b.pending(), 0)
	clock.tick = 0
	assert_eq(b.run(4000, clock.read), [])
