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

## ws(s):// URL of the server. On the web it defaults to the page's own host + /ws.
var server_url := ""
## Join automatically with this name once connected ("" = wait for join_with()).
var player_name := ""
var my_peer_id := 0

var _net: Node


func _ready() -> void:
	_net = get_parent().get_node("Net")
	_net.set_handler(self)
	if server_url == "":
		server_url = _default_url()
	var peer := WebSocketMultiplayerPeer.new()
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
	var ui: CanvasLayer = load("res://client/login_ui.gd").new()
	ui.client = self
	ui.sounds = sounds
	ui.settings = settings
	add_child(ui)
	add_child(settings)


func join_with(new_name: String) -> void:
	player_name = new_name
	if multiplayer.multiplayer_peer != null \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_net.join.rpc_id(1, player_name)


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


func on_welcome(peer_id: int, cell: Vector2i) -> void:
	my_peer_id = peer_id
	welcomed.emit(cell)


func on_rejected(reason: String) -> void:
	join_rejected.emit(reason)


func on_snapshot(players: Array) -> void:
	snapshot_received.emit(players)


func on_creatures(creatures: Array) -> void:
	creatures_received.emit(creatures)


func on_marks(marks: Array) -> void:
	marks_received.emit(marks)


func on_status(status: Dictionary) -> void:
	status_received.emit(status)


func on_inventory(items: Dictionary) -> void:
	inventory_received.emit(items)


func on_notice(key: String, args: Dictionary) -> void:
	notice_received.emit(key, args)


func _on_connected() -> void:
	if player_name != "":
		_net.join.rpc_id(1, player_name)


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
