## Client role: connects to the server, joins with a name, exposes state through signals.
## Rendering and input live in separate nodes (client/world_view.gd).
extends Node

signal welcomed(cell: Vector2i)
signal join_rejected(reason: String)
signal snapshot_received(players: Array)
signal creatures_received(creatures: Array)
signal marks_received(marks: Array)
signal status_received(status: Dictionary)
signal inventory_received(items: Dictionary)
signal notice_received(key: String, args: Dictionary)
signal connection_lost
## What a player wears (CharacterParts look), when it joins or changes.
signal look_received(peer_id: int, look: Array)

## ws(s):// URL of the server. On the web it defaults to the page's own host + /ws.
var server_url := ""
## Join automatically with this name once connected ("" = wait for join_with()).
var player_name := ""
var my_peer_id := 0
## The parts this player wears (CharacterParts look), remembered between sessions, sent before joining.
var look: Array = []

## A frame this long after the previous one means the game was paused (a hidden browser tab runs no
## frames). The updates buffered meanwhile are stale, and those that did not fit were dropped.
const PAUSE_GAP_MS := 1000
## Waiting longer than this for the server's "resynced" marker, the client shows updates again anyway.
const RESYNC_TIMEOUT_S := 3.0
## The receive buffer: about a minute of updates, so a short alt-tab drops nothing.
const INBOUND_BUFFER := 1 << 21
const MAX_QUEUED_PACKETS := 8192

## Emitted to ask the server for a resync (connected to the RPC in _ready).
signal resync_requested

var _net: Node
var _resync_left := 0.0  ## > 0 while waiting for "resynced": updates received meanwhile are stale
var _last_frame_ms := 0


func _ready() -> void:
	_net = get_parent().get_node("Net")
	_net.set_handler(self)
	look = ClientSettings.load_look()
	if server_url == "":
		server_url = _default_url()
	get_tree().multiplayer_poll = false  # polled in _process, after checking for a pause
	resync_requested.connect(func(): _net.resync.rpc_id(1))
	var peer := new_peer()
	var err := peer.create_client(server_url)
	if err != OK:
		push_error("client: cannot connect to %s (%s)" % [server_url, error_string(err)])
		connection_lost.emit()
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.server_disconnected.connect(func(): connection_lost.emit())
	multiplayer.connection_failed.connect(func(): connection_lost.emit())
	if DisplayServer.get_name() != "headless":
		_add_views()


func _add_views() -> void:
	var sounds: Node = load("res://client/sound_director.gd").new()
	sounds.name = "Sounds"
	sounds.client = self
	add_child(sounds)
	var settings: CanvasLayer = load("res://client/settings_menu.gd").new()
	settings.sounds = sounds
	var view: Node2D = load("res://client/world_view.gd").new()
	view.client = self
	view.sounds = sounds
	view.menu = settings
	add_child(view)
	var hud: CanvasLayer = load("res://client/hud.gd").new()
	hud.client = self
	add_child(hud)
	settings.windows = hud
	var ui: CanvasLayer = load("res://client/login_ui.gd").new()
	ui.client = self
	ui.sounds = sounds
	ui.settings = settings
	add_child(ui)
	add_child(settings)
	var panel: CanvasLayer = load("res://client/look_panel.gd").new()
	panel.client = self
	panel.menu = settings
	add_child(panel)


## The client's connection, with a receive buffer big enough for a short pause.
static func new_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = INBOUND_BUFFER
	peer.max_queued_packets = MAX_QUEUED_PACKETS
	return peer


## Checks for a pause before reading the network, so the stale updates read after it are dropped.
func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if paused_between(_last_frame_ms, now):
		begin_resync()
	_last_frame_ms = now
	tick_resync(delta)
	if multiplayer.has_multiplayer_peer():
		multiplayer.poll()


## Whether frames at `before_ms` and `now_ms` (0: no frame yet) were a pause apart.
func paused_between(before_ms: int, now_ms: int) -> bool:
	return before_ms > 0 and now_ms - before_ms > PAUSE_GAP_MS


## Drops updates until the server's "resynced" marker (or RESYNC_TIMEOUT_S), and asks for it. The
## server sends the marker first, then everything again.
func begin_resync() -> void:
	if my_peer_id == 0:
		return
	_resync_left = RESYNC_TIMEOUT_S
	resync_requested.emit()


func tick_resync(dt: float) -> void:
	_resync_left = maxf(_resync_left - dt, 0.0)


func on_resynced() -> void:
	_resync_left = 0.0


func _stale() -> bool:
	return _resync_left > 0.0


func join_with(new_name: String) -> void:
	player_name = new_name
	if multiplayer.multiplayer_peer != null \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_join()


## target in cell units: a cell center for a click, a point on the held line for the keys.
func request_move(target: Vector2) -> void:
	_net.move_to.rpc_id(1, target)


func request_stop() -> void:
	_net.stop.rpc_id(1)


func request_gather(cell: Vector2i) -> void:
	_net.gather.rpc_id(1, cell)


func request_eat(item: String) -> void:
	_net.eat.rpc_id(1, item)


func request_build_fire() -> void:
	_net.build_fire.rpc_id(1)


func request_whistle() -> void:
	_net.whistle.rpc_id(1)


func request_pick_up(mark_id: int) -> void:
	_net.pick_up.rpc_id(1, mark_id)


func request_cook(item: String) -> void:
	_net.cook.rpc_id(1, item)


func on_welcome(peer_id: int, cell: Vector2i) -> void:
	my_peer_id = peer_id
	welcomed.emit(cell)


func on_rejected(reason: String) -> void:
	join_rejected.emit(reason)


func on_snapshot(players: Array) -> void:
	if not _stale():
		snapshot_received.emit(players)


func on_creatures(creatures: Array) -> void:
	if not _stale():
		creatures_received.emit(creatures)


func on_marks(marks: Array) -> void:
	if not _stale():
		marks_received.emit(marks)


func on_status(status: Dictionary) -> void:
	if not _stale():
		status_received.emit(status)


func on_inventory(items: Dictionary) -> void:
	if not _stale():
		inventory_received.emit(items)


func on_notice(key: String, args: Dictionary) -> void:
	if not _stale():
		notice_received.emit(key, args)


func _on_connected() -> void:
	if player_name != "":
		_join()


## The look first, so that the others see it as soon as this player appears.
func _join() -> void:
	_net.set_look.rpc_id(1, look)
	_net.join.rpc_id(1, player_name)


## Wears a new look: remembered, and sent to the server (which checks it) once joined.
func set_look(new_look: Array) -> void:
	look = new_look.duplicate(true)
	ClientSettings.save_look(look)
	if my_peer_id != 0:
		_net.set_look.rpc_id(1, look)


func on_look(peer_id: int, parts: Array) -> void:
	if not _stale():
		look_received.emit(peer_id, parts)


func _default_url() -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--connect")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	if OS.has_feature("web"):
		var proto: String = JavaScriptBridge.eval("location.protocol")
		var host: String = JavaScriptBridge.eval("location.host")
		return ("wss://" if proto == "https:" else "ws://") + host + "/ws"
	return "ws://127.0.0.1:%d" % Protocol.DEFAULT_PORT
