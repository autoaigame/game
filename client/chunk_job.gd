## Builds the node of one map chunk (the same as ChunkView.build) in small steps of a few milliseconds
## each, so a frame can stop between them: the web build has no threads, and a whole chunk at once
## (world generation, then its ground, objects and decals) takes longer than a frame.
class_name ChunkJob
extends RefCounted

var chunk: Vector2i
var node: Node2D  ## complete once is_done(); not in the tree until then

var _tiles: Texture2D
var _steps: Array[Callable] = []  ## each returns true when finished, false to be called again
var _next := 0
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
	var seen := {}
	for r in WorldPlaces.regions_in(near):
		for q in WorldPlaces.neighbourhood(r):
			if not seen.has(q):
				seen[q] = true
				_steps.append(func() -> bool: WorldPlaces.candidate(q); return true)
		_steps.append(func() -> bool: WorldPlaces.is_accepted(r); return true)
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := c + Vector2i(dx, dy)
			_steps.append(func() -> bool: return MapData.generate_step(n))
	for y in MapData.CHUNK:
		_steps.append(func() -> bool: ChunkView.ground_row(c, y, _ground); return true)
	_steps.append(func() -> bool: ChunkView.add_objects(node, c); return true)
	_steps.append(_start_decals)
	for y in MapData.CHUNK:
		_steps.append(func() -> bool:
			for d in Decals.in_row(c, y):
				_decals.add_child(ChunkView.decal_sprite(d[0], d[1]))
			return true)
	_steps.append(_add_layer)


## Runs the next step; true once the node is complete.
func step() -> bool:
	if not is_done() and _steps[_next].call():
		_next += 1
		if _next >= _steps.size():
			_steps.clear()  # the steps hold this job: let it be freed
	return is_done()


func is_done() -> bool:
	return _steps.is_empty()


## Stops the job and frees its unfinished node.
func cancel() -> void:
	_steps.clear()
	if is_instance_valid(node):
		node.free()


## Runs every step now and returns the node.
func run_all() -> Node2D:
	while not step():
		pass
	return node


func _start_decals() -> bool:
	_decals = ChunkView.new_decals_node()
	node.add_child(_decals)
	_layer_order = _ground.keys()
	_layer_order.sort()
	return true


## One ground layer per call, lowest priority first.
func _add_layer() -> bool:
	if _layer_order.is_empty():
		return true
	var t: int = _layer_order.pop_front()
	node.add_child(ChunkView.ground_layer(t, _ground[t], _tiles))
	return _layer_order.is_empty()
