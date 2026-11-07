## Builds the chunks the streamer asks for, in ChunkJob steps, within a time budget per frame. The
## budget keeps frames short while walking into new chunks; one step always runs, so building moves on
## even on a slow machine.
class_name ChunkBuilder
extends RefCounted

## Time spent building chunks per frame, in microseconds (a quarter of a 60 fps frame).
const BUDGET_USEC := 4000

var steps_last_run := 0  ## steps the last run() took (tests read it)


## The clock run() reads: the engine's. Tests give a fake one with the same method.
class WallClock:
	extends RefCounted

	func now_usec() -> int:
		return Time.get_ticks_usec()


var _streamer: ChunkStreamer
var _tiles: Texture2D
var _jobs: Array[ChunkJob] = []


func _init(streamer: ChunkStreamer, tiles: Texture2D) -> void:
	_streamer = streamer
	_tiles = tiles


## Runs job steps until `budget_usec` has passed on `clock` (an object with now_usec(), like WallClock).
## Returns the chunks completed: [[chunk, node], ...].
func run(budget_usec: int, clock: Object) -> Array:
	var out := []
	var start: int = clock.now_usec()
	steps_last_run = 0
	while true:
		if _jobs.is_empty():
			for c in _streamer.take_builds():
				_jobs.append(ChunkJob.new(c, _tiles))
			if _jobs.is_empty():
				break
		if steps_last_run > 0 and clock.now_usec() - start >= budget_usec:
			break
		steps_last_run += 1
		if _jobs[0].step():
			var job: ChunkJob = _jobs.pop_front()
			out.append([job.chunk, job.node])
	return out


## Stops building these chunks (the streamer freed them); their unfinished nodes are freed.
func drop(chunks: Array[Vector2i]) -> void:
	for job in _jobs.duplicate():
		if chunks.has(job.chunk):
			job.cancel()
			_jobs.erase(job)


## Chunks started but not finished.
func pending() -> int:
	return _jobs.size()
