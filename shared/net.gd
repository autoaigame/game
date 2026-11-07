## RPC endpoint at /root/Main/Net on both client and server.
## Forwards calls to a handler set at runtime, so this file never names server or client code.
extends Node

var _handler: Object


func set_handler(handler: Object) -> void:
	_handler = handler


func _forward(method: String, args: Array) -> void:
	if _handler != null and _handler.has_method(method):
		_handler.callv(method, args)


# client -> server
@rpc("any_peer", "call_remote", "reliable")
func join(player_name: String) -> void:
	_forward("on_join", [multiplayer.get_remote_sender_id(), player_name])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func move_to(target: Vector2) -> void:
	_forward("on_move_to", [multiplayer.get_remote_sender_id(), target])


@rpc("any_peer", "call_remote", "reliable")
func stop() -> void:
	_forward("on_stop", [multiplayer.get_remote_sender_id()])


# server -> client
@rpc("authority", "call_remote", "reliable")
func welcome(peer_id: int, cell: Vector2i) -> void:
	_forward("on_welcome", [peer_id, cell])


@rpc("authority", "call_remote", "reliable")
func rejected(reason: String) -> void:
	_forward("on_rejected", [reason])


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(players: Array) -> void:
	_forward("on_snapshot", [players])


## Creatures (dogs, animals) for clients to draw: [{id, kind, owner, pos}, ...]. Separate from
## snapshot so clients that do not draw creatures can ignore it.
@rpc("authority", "call_remote", "unreliable_ordered")
func creatures(list: Array) -> void:
	_forward("on_creatures", [list])


## Marks on the ground (pee spots, holes): [{id, kind, pos, left (seconds)}, ...]. Sent on join and
## when the list changes; clients age them locally.
@rpc("authority", "call_remote", "reliable")
func marks(list: Array) -> void:
	_forward("on_marks", [list])


## The player's own status ({hunger: int}): sent on join and when it changes.
@rpc("authority", "call_remote", "reliable")
func status(values: Dictionary) -> void:
	_forward("on_status", [values])
