## Entry point. Starts the dedicated server with `-- --server`, otherwise the client.
## The server script is loaded by path so the web build never references it.
extends Node

const SERVER_SCRIPT := "res://server/server.gd"
const CLIENT_SCRIPT := "res://client/client.gd"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path := SERVER_SCRIPT if "--server" in args else CLIENT_SCRIPT
	if not ResourceLoader.exists(path):
		push_error("Missing %s" % path)
		get_tree().quit(1)
		return
	var role: Node = load(path).new()
	role.name = "Role"
	add_child(role)
