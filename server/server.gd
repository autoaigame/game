## Dedicated server: `godot --headless --path . -- --server --port 9000 --db game.db [--bind 127.0.0.1]`.
## Server-authoritative positions, broadcast at Protocol.TICK_HZ, persisted in SQLite.
extends Node

## A look was sent to peer `to`: what player `who` wears.
signal look_sent(to: int, who: int, look: Array)

const SAVE_INTERVAL_S := 10.0
const CARCASS_S := 120.0  ## how long a caught animal lies on the ground
## Raw meat a caught animal gives, by mark kind: when the dog brings it back, or when picked up off the
## ground (where the dog drops it if its owner's bag has no room).
const MEAT := {"carcass_rabbit": 2, "carcass_pheasant": 1}
const DOG := preload("res://server/dog.gd")
const MARKS := preload("res://server/marks.gd")
const HUNGER := preload("res://server/hunger.gd")
const INV := preload("res://server/inventory.gd")
const GATHER := preload("res://server/gather.gd")
const WILD := preload("res://server/wildlife.gd")
## Looks kept for peers that have not joined yet, at most (each is dropped on join or disconnect).
const MAX_EARLY_LOOKS := 64

var _db: RefCounted
var _net: Node
## peer_id -> {name, pos: Vector2, target: Vector2i, stopped: bool, dog: server/dog.gd record,
## hunger: float, sent: what the client was last told of its status, inventory: item id -> count,
## look: Array (CharacterParts)}; the dog record's "skin" is the dog the player chose (DogSkins)
var _players := {}
## peer_id -> look sent before joining (the client sends it first, so others never see a default look)
var _early_looks := {}
## peer_id -> dog (DogSkins id) sent before joining, for the same reason; bounded like _early_looks
var _early_dogs := {}
var _marks: Dictionary = MARKS.new_marks()
var _marks_changed := false
var _wild: Dictionary = WILD.new_wild()
var _picked := {}  ## gathered object cell -> seconds until it regrows
var _rng := RandomNumberGenerator.new()
var _tick_acc := 0.0
var _save_acc := 0.0


func _ready() -> void:
	_rng.randomize()
	_wild = WILD.new_wild(_rng.randi())
	var args := _parse_args()
	_db = load("res://server/db.gd").new()
	if not _db.open(args.get("db", "user://game.db")):
		get_tree().quit(1)
		return
	_net = get_parent().get_node("Net")
	_net.set_handler(self)
	var peer := WebSocketMultiplayerPeer.new()
	var port := int(args.get("port", Protocol.DEFAULT_PORT))
	var err := peer.create_server(port, args.get("bind", "127.0.0.1"))
	if err != OK:
		push_error("server: cannot listen on %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("server: listening on %d" % port)


func _process(delta: float) -> void:
	_tick_acc += delta
	var tick := 1.0 / Protocol.TICK_HZ
	if _tick_acc >= tick:
		_step(_tick_acc)
		_tick_acc = 0.0
	_save_acc += delta
	if _save_acc >= SAVE_INTERVAL_S:
		_save_acc = 0.0
		for p in _players.values():
			_save(p)


func on_join(peer_id: int, player_name: String) -> void:
	if _players.has(peer_id):
		return
	var problem := Protocol.validate_name(player_name)
	if problem == "" and _players.values().any(func(p): return p["name"] == player_name):
		problem = "Someone named %s is already playing." % player_name
	if problem != "":
		_net.rejected.rpc_id(peer_id, problem)
		return
	var cell := join_cell(_db.load_player(player_name))
	_players[peer_id] = _joining_player(peer_id, player_name, cell, _db.load_stats(player_name),
			_db.load_inventory(player_name))
	_net.welcome.rpc_id(peer_id, peer_id, cell)
	_net.marks.rpc_id(peer_id, MARKS.snapshot(_marks))
	_net.status.rpc_id(peer_id, _status_to_send(_players[peer_id]))
	_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	# Before the next snapshot: everyone learns what the newcomer wears, the newcomer what the others wear.
	for id in _players:
		if id != peer_id:
			_send_look(peer_id, id)
		_send_look(id, peer_id)
	print("server: %s joined at %s" % [player_name, cell])


## The record of peer `peer_id` joining: wearing the look and with the dog it sent before joining, which
## are no longer kept apart.
func _joining_player(peer_id: int, player_name: String, cell: Vector2i, stats: Dictionary, inventory: Dictionary) -> Dictionary:
	var p := _new_player(player_name, cell, stats, inventory, _early_looks.get(peer_id, []),
			_early_dogs.get(peer_id, DogSkins.DEFAULT))
	_early_looks.erase(peer_id)
	_early_dogs.erase(peer_id)
	return p


## The client is back from a pause (its browser tab ran no frames, so it dropped updates): sends it
## again everything that is only sent on a change.
func on_resync(peer_id: int) -> void:
	if _net == null:
		return
	for m in _resync_messages(peer_id):
		var args: Array = m[1]
		match m[0]:
			"resynced":
				_net.resynced.rpc_id(peer_id)
			"marks":
				_net.marks.rpc_id(peer_id, args[0])
			"status":
				_net.status.rpc_id(peer_id, args[0])
			"inventory":
				_net.inventory.rpc_id(peer_id, args[0])
			"look":
				_net.look.rpc_id(peer_id, args[0], args[1])


## What a resync sends a player, in order, as [rpc name, args]: first the "resynced" marker (the
## client drops what came before it, sent before its request, as stale), then the marks, their status
## (even if unchanged), their inventory and what everyone wears. [] if not joined.
func _resync_messages(peer_id: int) -> Array:
	if not _players.has(peer_id):
		return []
	var p: Dictionary = _players[peer_id]
	p["sent"] = {}
	var out := [["resynced", []], ["marks", [MARKS.snapshot(_marks)]], ["status", [_status_to_send(p)]],
			["inventory", [p["inventory"]]]]
	for id in _players:
		out.append(["look", [id, _players[id]["look"]]])
	return out


## A joined player's record at `cell`, with their dog and their saved stats (hunger: full if none),
## wearing `look` if it is valid, the default look otherwise, and with the dog `dog_skin` (DogSkins.valid).
func _new_player(player_name: String, cell: Vector2i, stats: Dictionary, inventory := {}, look: Variant = [],
		dog_skin: Variant = DogSkins.DEFAULT) -> Dictionary:
	var dog_pos := Vector2(DOG.spot_near(cell, cell + Vector2i(1, 1)))
	var dog: Dictionary = DOG.new_dog(dog_pos, hash(player_name))
	dog["skin"] = DogSkins.valid(dog_skin)
	return {"name": player_name, "pos": Vector2(cell), "target": Vector2(cell), "stopped": false, "sprint": false,
			"dog": dog, "hunger": float(stats.get("hunger", HUNGER.MAX)),
			"sent": {}, "inventory": inventory.duplicate(), "look": wearable(look)}


## `look` if it is a valid look (CharacterParts.validate), a copy; the default look otherwise.
static func wearable(look: Variant) -> Array:
	return (look if CharacterParts.validate(look) == "" else CharacterParts.default_look()).duplicate(true)


func _save(p: Dictionary) -> void:
	_db.save_player(p["name"], Protocol.cell_of(p["pos"]))
	_db.save_stats(p["name"], {"hunger": p["hunger"]})
	_db.save_inventory(p["name"], p.get("inventory", {}))


## The player asks to gather from the object on `cell` (a bush).
func on_gather(peer_id: int, cell: Vector2i) -> void:
	var r := _gather(peer_id, cell)
	if r.is_empty():
		return
	if r["notice"] == "gathered":
		_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	var args := r.duplicate()
	args.erase("notice")
	_net.notice.rpc_id(peer_id, r["notice"], args)


## Gathers for a player from the object on `cell`: {notice: gathered (with item, count), the rule's
## empty notice or too_far}, or {} for a request to ignore (unknown player, nothing gatherable there).
func _gather(peer_id: int, cell: Vector2i) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var rule: Dictionary = GATHER.RULES.get(MapData.object_at(cell), {})
	if rule.is_empty():
		return {}
	var p: Dictionary = _players[peer_id]
	if (p["pos"] as Vector2).distance_to(Vector2(cell)) > GATHER.REACH:
		return {"notice": "too_far"}
	if _picked.has(cell):
		return {"notice": rule["empty"]}
	var n := INV.add(p["inventory"], rule["item"], _rng.randi_range(rule["min"], rule["max"]))
	_picked[cell] = rule["regrow_s"]
	return {"notice": "gathered", "item": rule["item"], "count": n}


## The player eats one of an item from their bag.
func on_eat(peer_id: int, item: String) -> void:
	var r := _eat(peer_id, item)
	if r.is_empty():
		return
	_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	_net.notice.rpc_id(peer_id, "ate", {"item": item})


## Eats one `item` (food the player has): {notice: ate, item}, or {} for a request to ignore.
func _eat(peer_id: int, item: String) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var food: int = ItemData.item(item).get("food", 0)
	var p: Dictionary = _players[peer_id]
	if food <= 0 or not INV.remove(p["inventory"], item, 1):
		return {}
	p["hunger"] = HUNGER.fed(p["hunger"], food)
	return {"notice": "ate", "item": item}


## The player builds a campfire where they stand.
func on_build_fire(peer_id: int) -> void:
	var r := _build_fire(peer_id)
	if r.is_empty():
		return
	if r["notice"] == "fire_built":
		_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	_net.notice.rpc_id(peer_id, r["notice"], {})


## Builds a campfire (a "fire" mark lasting Protocol.FIRE_S) on the player's cell for FIRE_STICKS
## sticks: {notice: fire_built, need_sticks or fire_here (a fire is already there)}, or {}.
func _build_fire(peer_id: int) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var p: Dictionary = _players[peer_id]
	var cell := Protocol.cell_of(p["pos"])
	if not _fires_near(Vector2(cell), 1.0).is_empty():
		return {"notice": "fire_here"}
	if not INV.remove(p["inventory"], "sticks", Protocol.FIRE_STICKS):
		return {"notice": "need_sticks"}
	MARKS.add(_marks, "fire", Vector2(cell), Protocol.FIRE_S)
	_marks_changed = true
	return {"notice": "fire_built"}


## Burning campfires within `radius` cells of `pos`: their positions.
func _fires_near(pos: Vector2, radius: float) -> Array:
	var out := []
	for m in MARKS.snapshot(_marks):
		if m["kind"] == "fire" and (m["pos"] as Vector2).distance_to(pos) <= radius:
			out.append(m["pos"])
	return out


## The player picks up a caught animal (the mark `mark_id`).
func on_pick_up(peer_id: int, mark_id: int) -> void:
	var r := _pick_up(peer_id, mark_id)
	if r.is_empty():
		return
	if r["notice"] == "gathered":
		_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	var args := r.duplicate()
	args.erase("notice")
	_net.notice.rpc_id(peer_id, r["notice"], args)


## Picks up a carcass within reach for its raw meat: {notice: gathered (item, count) or too_far},
## or {} for a request to ignore (unknown player, no such carcass).
func _pick_up(peer_id: int, mark_id: int) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var mark := MARKS.find(_marks, mark_id)
	if not MEAT.has(mark.get("kind", "")):
		return {}
	var p: Dictionary = _players[peer_id]
	if (p["pos"] as Vector2).distance_to(mark["pos"]) > Protocol.GATHER_REACH:
		return {"notice": "too_far"}
	var n := INV.add(p["inventory"], "raw_meat", MEAT[mark["kind"]])
	MARKS.remove(_marks, mark_id)
	_marks_changed = true
	return {"notice": "gathered", "item": "raw_meat", "count": n}


## The player cooks one of an item on a campfire near them.
func on_cook(peer_id: int, item: String) -> void:
	var r := _cook(peer_id, item)
	if r.is_empty():
		return
	if r["notice"] == "cooked":
		_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	var args := r.duplicate()
	args.erase("notice")
	_net.notice.rpc_id(peer_id, r["notice"], args)


## Cooks one `item` (one that cooks, that the player has) on a fire within Protocol.COOK_REACH:
## {notice: cooked (item: what it became), no_fire or bag_full}, or {} for a request to ignore.
func _cook(peer_id: int, item: String) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var into: String = ItemData.item(item).get("cooks_into", "")
	var p: Dictionary = _players[peer_id]
	if into == "" or INV.count(p["inventory"], item) < 1:
		return {}
	if _fires_near(p["pos"], Protocol.COOK_REACH).is_empty():
		return {"notice": "no_fire"}
	if INV.count(p["inventory"], into) >= INV.MAX_STACK:
		return {"notice": "bag_full"}
	INV.remove(p["inventory"], item, 1)
	INV.add(p["inventory"], into, 1)
	return {"notice": "cooked", "item": into}


## Picked objects regrow.
func _tick_gathering(dt: float) -> void:
	for cell in _picked.keys():
		_picked[cell] -= dt
		if _picked[cell] <= 0.0:
			_picked.erase(cell)


## Where a joining player appears: its saved cell, or the walkable cell nearest to it if the map
## changed under it (old saves), or the spawn for a new player.
static func join_cell(saved: Variant) -> Vector2i:
	if saved == null:
		return MapData.spawn_cell()
	if MapData.is_walkable(saved):
		return saved
	var near: Variant = MapData.nearest_walkable(saved)
	return near if near != null else MapData.spawn_cell()


## target is any point in cell units. Refused unless it is a real number on a walkable cell.
func on_move_to(peer_id: int, target: Vector2) -> void:
	if _players.has(peer_id) and target.is_finite() and MapData.is_walkable(Protocol.cell_of(target)):
		_players[peer_id]["target"] = target
		_players[peer_id]["stopped"] = false


## Sprint or walk from now on (the client holds Shift or lets go). Anything but a bool is refused.
func on_sprint(peer_id: int, on: Variant) -> void:
	if _players.has(peer_id) and on is bool:
		_players[peer_id]["sprint"] = on


## The player stays where it is until its next move_to.
func on_stop(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id]["stopped"] = true


## The parts a player wears. Refused (the old look stays) unless every id exists in data/character and
## fits its slot and colours (CharacterParts.validate). A change is sent to everyone at once.
func on_set_look(peer_id: int, look: Variant) -> void:
	var problem := CharacterParts.validate(look)
	if problem != "":
		print("server: look from peer %d refused: %s" % [peer_id, problem])
		return
	if not _players.has(peer_id):
		if _early_looks.has(peer_id) or _early_looks.size() < MAX_EARLY_LOOKS:
			_early_looks[peer_id] = look.duplicate(true)
		return
	if look == _players[peer_id]["look"]:
		return
	_players[peer_id]["look"] = look.duplicate(true)
	for id in _players:
		_send_look(id, peer_id)


## The dog a player chose (DogSkins id): an unknown one gives the default dog. Everyone near sees it
## with the next creatures update (_creatures_for), so nothing is sent here.
func on_set_dog(peer_id: int, skin: Variant) -> void:
	var id := DogSkins.valid(skin)
	if not _players.has(peer_id):
		if _early_dogs.has(peer_id) or _early_dogs.size() < MAX_EARLY_LOOKS:
			_early_dogs[peer_id] = id
		return
	_players[peer_id]["dog"]["skin"] = id


## Tells peer `to` what player `who` wears.
func _send_look(to: int, who: int) -> void:
	look_sent.emit(to, who, _players[who]["look"])
	if _net != null:
		_net.look.rpc_id(to, who, _players[who]["look"])


func _on_peer_disconnected(peer_id: int) -> void:
	_early_looks.erase(peer_id)
	_early_dogs.erase(peer_id)
	if not _players.has(peer_id):
		return
	var p: Dictionary = _players[peer_id]
	_save(p)
	_players.erase(peer_id)
	print("server: %s left" % p["name"])


func _step(dt: float) -> void:
	_tick_hunger(dt)
	_tick_gathering(dt)
	_move_players(dt)
	for told in _move_dogs(dt):
		_net.inventory.rpc_id(told[0], _players[told[0]]["inventory"])
		var args: Dictionary = told[1].duplicate()
		args.erase("notice")
		_net.notice.rpc_id(told[0], told[1]["notice"], args)
	_move_wildlife(dt)
	if MARKS.tick(_marks, dt):
		_marks_changed = true
	for id in _players:
		_net.snapshot.rpc_id(id, _snapshot_for(id))
		_net.creatures.rpc_id(id, _creatures_for(id))
		var status := _status_to_send(_players[id])
		if not status.is_empty():
			_net.status.rpc_id(id, status)
	if _marks_changed:
		_marks_changed = false
		var marks := MARKS.snapshot(_marks)
		for id in _players:
			_net.marks.rpc_id(id, marks)


func _move_wildlife(dt: float) -> void:
	WILD.populate(_wild, _players.values().map(func(p): return p["pos"]), dt)
	WILD.update(_wild, _threats(), dt)


## What wild animals flee from: every player and every dog.
func _threats() -> Array:
	var out := []
	for p in _players.values():
		out.append(p["pos"])
		out.append(p["dog"]["pos"])
	return out


## Moves every dog. Returns what to tell players whose dog brought back a catch: [peer id,
## {notice: gathered (item, count) or bag_full}].
func _move_dogs(dt: float) -> Array:
	var told := []
	for id in _players:
		var p: Dictionary = _players[id]
		var dog: Dictionary = p["dog"]
		var events: Array
		if dog["state"] == "hunt":
			var prey: Dictionary = _wild["animals"].get(dog["prey"], {})
			events = DOG.hunt(dog, p["pos"], prey.get("pos"), dt)
		else:
			events = DOG.update(dog, p["pos"], dt)
		for e in events:
			match e["kind"]:
				"catch":
					_dog_catches(dog, e["prey"])
				"deliver":
					told.append([id, _deliver(p, "carcass_" + String(e["carry"]))])
				_:
					_add_events([e])
	return told


## The dog caught wild animal `prey_id`: it is gone from the wild, and the dog carries it.
func _dog_catches(dog: Dictionary, prey_id: int) -> void:
	var prey: Dictionary = _wild["animals"].get(prey_id, {})
	if prey.is_empty():
		return
	_wild["animals"].erase(prey_id)
	dog["carry"] = String(prey["kind"])


## The dog hands its catch (mark kind `carcass`) to player `p`: its raw meat goes into their bag, or,
## with no room for any, the catch is dropped at the dog's feet to pick up later.
func _deliver(p: Dictionary, carcass: String) -> Dictionary:
	var n := INV.add(p["inventory"], "raw_meat", MEAT.get(carcass, 0))
	if n > 0:
		return {"notice": "gathered", "item": "raw_meat", "count": n}
	MARKS.add(_marks, carcass, p["dog"]["pos"], CARCASS_S)
	_marks_changed = true
	return {"notice": "bag_full"}


## The player whistles: their dog runs after the nearest wild animal within DOG.HUNT_RADIUS of them, and
## the players near them hear it.
func on_whistle(peer_id: int) -> void:
	for m in _whistle_messages(peer_id):
		match m[0]:
			"notice":
				_net.notice.rpc_id(m[1], m[2][0], {})
			"whistled":
				_net.whistled.rpc_id(m[1], m[2][0])


## What a whistle sends, in order, as [rpc name, to, args]: the whistler's notice, then "whistled" to every
## other player within Protocol.INTEREST_RADIUS (who see it), whatever the dog does. [] if not joined.
func _whistle_messages(peer_id: int) -> Array:
	var r := _whistle(peer_id)
	if r.is_empty():
		return []
	var out := [["notice", peer_id, [r["notice"]]]]
	var at: Vector2 = _players[peer_id]["pos"]
	for id in _players:
		if id != peer_id and at.distance_to(_players[id]["pos"]) <= Protocol.INTEREST_RADIUS:
			out.append(["whistled", id, [peer_id]])
	return out


## {notice: hunt, no_prey, or dog_busy while it is bringing back a catch}, or {} for an unknown player.
func _whistle(peer_id: int) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var p: Dictionary = _players[peer_id]
	if p["dog"].has("carry"):
		return {"notice": "dog_busy"}
	var best: Variant = null
	var best_d := DOG.HUNT_RADIUS
	for id in _wild["animals"]:
		var d: float = (p["pos"] as Vector2).distance_to(_wild["animals"][id]["pos"])
		if d <= best_d:
			best = id
			best_d = d
	if best == null:
		return {"notice": "no_prey"}
	DOG.start_hunt(p["dog"], best)
	return {"notice": "hunt"}


## Turns creature events into marks on the ground.
func _add_events(events: Array) -> void:
	for e in events:
		match e["kind"]:
			"pee":
				MARKS.add(_marks, "pee", e["pos"], DOG.PEE_MARK_S)
			"hole":
				MARKS.add(_marks, "hole", e["pos"], DOG.HOLE_MARK_S)
			_:
				continue
		_marks_changed = true


## The players a player is sent: {id, name, pos}, those within Protocol.INTEREST_RADIUS (and itself).
func _snapshot_for(viewer: int) -> Array:
	var at: Vector2 = _players[viewer]["pos"]
	var out: Array = []
	for id in _players:
		var p: Dictionary = _players[id]
		if id == viewer or at.distance_to(p["pos"]) <= Protocol.INTEREST_RADIUS:
			out.append({"id": id, "name": p["name"], "pos": p["pos"]})
	return out


## The creatures a player is sent: {id, kind, owner (peer id or 0), pos, state, for a dog carrying
## a catch, carry: its kind, and for a dog other than DogSkins.DEFAULT, skin: its DogSkins id}, those within
## Protocol.INTEREST_RADIUS (and its own dog). A dog's id is its owner's peer id; wild animals have
## negative ids (server/wildlife.gd).
func _creatures_for(viewer: int) -> Array:
	var at: Vector2 = _players[viewer]["pos"]
	var out: Array = []
	for id in _players:
		var dog: Dictionary = _players[id]["dog"]
		if id == viewer or at.distance_to(dog["pos"]) <= Protocol.INTEREST_RADIUS:
			var c := {"id": id, "kind": "dog", "owner": id, "pos": dog["pos"], "state": dog["state"]}
			if dog.has("carry"):
				c["carry"] = dog["carry"]
			if dog.get("skin", DogSkins.DEFAULT) != DogSkins.DEFAULT:
				c["skin"] = dog["skin"]
			out.append(c)
	out.append_array(WILD.snapshot_near(_wild, at, Protocol.INTEREST_RADIUS))
	return out


func _move_players(dt: float) -> void:
	for p in _players.values():
		if not p["stopped"]:
			var factor: float = HUNGER.speed_factor(p.get("hunger", HUNGER.MAX))
			if p.get("sprint", false):
				factor *= Protocol.SPRINT_FACTOR
			p["pos"] = Protocol.step_towards(p["pos"], p["target"], dt * factor)


func _tick_hunger(dt: float) -> void:
	for p in _players.values():
		p["hunger"] = HUNGER.tick(p.get("hunger", HUNGER.MAX), dt)


## What the player's client should be told of their own status ({hunger: int}), or {} if it already
## shows it. Remembers what was sent.
func _status_to_send(p: Dictionary) -> Dictionary:
	var now := {"hunger": roundi(p["hunger"])}
	if now == p["sent"]:
		return {}
	p["sent"] = now
	return now


func _exit_tree() -> void:
	if _db != null:
		for p in _players.values():
			_save(p)
		_db.close()


func _parse_args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size() and not a[i + 1].begins_with("--"):
			out[a[i].substr(2)] = a[i + 1]
	return out
