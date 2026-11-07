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


@rpc("any_peer", "call_remote", "reliable")
func gather(cell: Vector2i) -> void:
	_forward("on_gather", [multiplayer.get_remote_sender_id(), cell])


@rpc("any_peer", "call_remote", "reliable")
func eat(item: String) -> void:
	_forward("on_eat", [multiplayer.get_remote_sender_id(), item])


@rpc("any_peer", "call_remote", "reliable")
func build_fire() -> void:
	_forward("on_build_fire", [multiplayer.get_remote_sender_id()])


@rpc("any_peer", "call_remote", "reliable")
func whistle() -> void:
	_forward("on_whistle", [multiplayer.get_remote_sender_id()])


@rpc("any_peer", "call_remote", "reliable")
func pick_up(mark_id: int) -> void:
	_forward("on_pick_up", [multiplayer.get_remote_sender_id(), mark_id])


@rpc("any_peer", "call_remote", "reliable")
func cook(item: String) -> void:
	_forward("on_cook", [multiplayer.get_remote_sender_id(), item])


## The parts the player wears (CharacterParts look), checked by the server. May come before join.
@rpc("any_peer", "call_remote", "reliable")
func set_look(look: Array) -> void:
	_forward("on_set_look", [multiplayer.get_remote_sender_id(), look])


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


## The player's inventory: item id -> count. Sent on join and when it changes.
@rpc("authority", "call_remote", "reliable")
func inventory(items: Dictionary) -> void:
	_forward("on_inventory", [items])


## A short message for the player (client/ui_text.gd notice): key and its values.
@rpc("authority", "call_remote", "reliable")
func notice(key: String, args: Dictionary) -> void:
	_forward("on_notice", [key, args])


## What a player wears, sent when it joins or changes (not in every snapshot).
@rpc("authority", "call_remote", "reliable")
func look(peer_id: int, parts: Array) -> void:
	_forward("on_look", [peer_id, parts])
