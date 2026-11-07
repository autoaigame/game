## Builds the node of one map chunk (the same as ChunkView.build) in small steps of a few milliseconds
## each, so a frame can stop between them: the web build has no threads, and a whole chunk at once
## (world generation, then its ground, objects and decals) takes longer than a frame.
class_name ChunkJob
extends RefCounted

## The phases of a build, in order. Each step does one item of the current phase.
enum Phase { PLACE_CANDIDATES, PLACE_CHECKS, GENERATE, GROUND, OBJECTS, DECALS, LAYERS, DONE }

var chunk: Vector2i
var node: Node2D  ## complete once is_done(); not in the tree until then

var _tiles: Texture2D
var _phase := Phase.PLACE_CANDIDATES
var _i := 0  ## item of the current phase
var _candidates: Array[Vector2i] = []  ## place regions whose candidates the place checks read
var _regions: Array[Vector2i] = []  ## place regions touching the chunk and its neighbours
var _neighbours: Array[Vector2i] = []  ## the chunk and its 8 neighbours, whose cells it reads
var _ground := {}  ## ChunkView.ground_tiles, filled row by row
var _decals: Node2D
var _layer_order: Array = []


func _init(c: Vector2i, tiles: Texture2D) -> void:
	chunk = c
	_tiles = tiles
	node = ChunkView.new_node(c)
	# The world data this chunk reads: hand-made places of its region and the regions around, then its
	# own cells and those of its 8 neighbours (ground corners and walls look one cell across).
	var near := Rect2i((c - Vector2i.ONE) * MapData.CHUNK, Vector2i.ONE * 3 * MapData.CHUNK)
	_regions = WorldPlaces.regions_in(near)
	var seen := {}
	for r in _regions:
		for q in WorldPlaces.neighbourhood(r):
			if not seen.has(q):
				seen[q] = true
				_candidates.append(q)
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			_neighbours.append(c + Vector2i(dx, dy))


## Runs the next step; true once the node is complete.
func step() -> bool:
	match _phase:
		Phase.PLACE_CANDIDATES:
			WorldPlaces.candidate(_candidates[_i])
			_advance(_candidates.size())
		Phase.PLACE_CHECKS:
			WorldPlaces.is_accepted(_regions[_i])
			_advance(_regions.size())
		Phase.GENERATE:
			if MapData.generate_step(_neighbours[_i]):
				_advance(_neighbours.size())
		Phase.GROUND:
			ChunkView.ground_row(chunk, _i, _ground)
			_advance(MapData.CHUNK)
		Phase.OBJECTS:
			ChunkView.add_objects(node, chunk)
			_decals = ChunkView.new_decals_node()
			node.add_child(_decals)
			_layer_order = _ground.keys()
			_layer_order.sort()
			_advance(1)
		Phase.DECALS:
			for d in Decals.in_row(chunk, _i):
				_decals.add_child(ChunkView.decal_sprite(d[0], d[1]))
			_advance(MapData.CHUNK)
		Phase.LAYERS:
			if _i < _layer_order.size():
				var t: int = _layer_order[_i]
				node.add_child(ChunkView.ground_layer(t, _ground[t], _tiles))
			_advance(_layer_order.size())
	return is_done()


func is_done() -> bool:
	return _phase == Phase.DONE


## Runs every step now and returns the node.
func run_all() -> Node2D:
	while not step():
		pass
	return node


## Stops the job and frees its unfinished node.
func cancel() -> void:
	_phase = Phase.DONE
	if is_instance_valid(node):
		node.free()


## Moves to the next item; past the last of `count` items, to the next phase with items.
func _advance(count: int) -> void:
	_i += 1
	while _phase != Phase.DONE and _i >= _count_of(_phase, count):
		_phase = (_phase + 1) as Phase
		_i = 0
		count = -1


## Items in a phase: `known` for the current one, otherwise from the job's lists.
func _count_of(phase: Phase, known: int) -> int:
	if known >= 0:
		return known
	match phase:
		Phase.PLACE_CANDIDATES:
			return _candidates.size()
		Phase.PLACE_CHECKS:
			return _regions.size()
		Phase.GENERATE:
			return _neighbours.size()
		Phase.GROUND, Phase.DECALS:
			return MapData.CHUNK
		Phase.OBJECTS:
			return 1
		Phase.LAYERS:
			return maxi(_layer_order.size(), 1)
	return 0
