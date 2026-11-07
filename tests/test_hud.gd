extends TestCase

## The in-game HUD (client/hud.gd): the hunger bar.


class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal status_received(status: Dictionary)
	var my_peer_id := 0


func _hud() -> CanvasLayer:
	var hud: CanvasLayer = load("res://client/hud.gd").new()
	hud.client = FakeClient.new()
	hud.add_child(hud.client)
	hud._ready()
	return hud


func test_hidden_until_joined() -> void:
	var hud := _hud()
	assert_false(hud.visible)
	hud.client.welcomed.emit(Vector2i.ZERO)
	assert_true(hud.visible)
	hud.free()


func test_hunger_bar_follows_the_status() -> void:
	var hud := _hud()
	hud.client.status_received.emit({"hunger": 64})
	assert_eq(hud.hunger_bar().value, 64.0)
	assert_eq(hud.hunger_bar().max_value, 100.0)
	hud.client.status_received.emit({"other": 1})
	assert_eq(hud.hunger_bar().value, 64.0, "other keys leave it alone")
	hud.free()


func test_warns_when_starving() -> void:
	var hud := _hud()
	hud.client.status_received.emit({"hunger": 50})
	assert_false(hud.starving_label().visible)
	hud.client.status_received.emit({"hunger": 0})
	assert_true(hud.starving_label().visible)
	hud.free()
