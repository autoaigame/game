extends TestCase

## The dog chosen in the start menu, on the client: remembered (client/client_settings.gd), sent before
## joining (client/client.gd), chosen in the look editor (client/look_editor.gd, client/login_ui.gd), and
## each player's dog drawn as they chose it (client/world_view.gd).

const PATH := "user://test_dog_settings.cfg"
const LoginUi := preload("res://client/login_ui.gd")


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_dog_is_remembered_with_the_rest() -> void:
	_clean()
	assert_eq(ClientSettings.load_dog(PATH), DogSkins.DEFAULT, "no file: the default dog")
	ClientSettings.save_look(CharacterParts.default_look(), PATH)
	ClientSettings.save_dog("cyborg_c", PATH)
	assert_eq(ClientSettings.load_dog(PATH), "cyborg_c")
	assert_eq(ClientSettings.load_look(PATH), CharacterParts.default_look(), "the look stays")
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("player", "dog", "dragon")
	cfg.save(PATH)
	assert_eq(ClientSettings.load_dog(PATH), DogSkins.DEFAULT, "an unknown dog")
	cfg.set_value("player", "dog", 7)
	cfg.save(PATH)
	assert_eq(ClientSettings.load_dog(PATH), DogSkins.DEFAULT, "not a string")
	ClientSettings.save_dog("dragon", PATH)
	cfg = ConfigFile.new()
	cfg.load(PATH)
	assert_eq(cfg.get_value("player", "dog"), DogSkins.DEFAULT, "an unknown dog is never written")
	_clean()


## The client sends its dog with its look before joining, and a change once joined.
func test_client_sends_the_dog_before_joining_and_on_change() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var at := src.find("func _join(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("set_dog.rpc_id(1, dog)"), "the dog is sent in _join")
	assert_true(body.find("set_dog") < body.find("join.rpc_id"), "before the join itself")
	at = src.find("func set_dog(")
	body = src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("DogSkins.valid") and body.contains("save_dog") and body.contains("my_peer_id != 0"))


## A client stand-in for the start menu.
class MenuClient:
	extends Node
	var look: Array = []
	var dog := "cyborg_b"
	var dogs := []

	func set_look(_l: Array) -> void:
		pass

	func set_dog(d: String) -> void:
		dogs.append(d)


## The Chien row: the remembered dog shown, the arrows go through the four dogs and tell the client.
func test_menu_dog_row_chooses_and_tells_the_client() -> void:
	var ui: CanvasLayer = LoginUi.new()
	var c := MenuClient.new()
	ui.client = c
	var screen: Control = ui._build_play_screen()
	var editors := screen.find_children("*", "LookEditor", true, false)
	assert_eq(editors.size(), 1)
	var ed: LookEditor = editors[0]
	assert_true(ed.with_dog, "the start menu has the Chien row")
	assert_eq(ed.dog, "cyborg_b", "the remembered dog")
	ed._change_dog(DogSkins.cycle(ed.dog, 1))
	ed._change_dog(DogSkins.cycle(ed.dog, 1))
	assert_eq(c.dogs, ["cyborg_c", "classic"])
	screen.free()
	ui.free()
	c.free()


func test_editor_dog_row_names_and_preview() -> void:
	var ed := LookEditor.new([], true, true, "nope")
	assert_eq(ed.dog, DogSkins.DEFAULT, "an unknown start dog")
	ed._ready()
	assert_eq(ed._dog_name.text, UiText.DOG_NAMES["classic"])
	assert_true(ed._dog_preview is Sprite2D, "the drawn dog for the default")
	var got := []
	ed.dog_changed.connect(func(d): got.append(d))
	ed._change_dog("cyborg_a")
	assert_eq(got, ["cyborg_a"])
	assert_eq(ed._dog_name.text, UiText.DOG_NAMES["cyborg_a"])
	assert_true(ed._dog_preview is Dog3D and (ed._dog_preview as Dog3D).skin == Dog3D.skin_index("cyborg_a"))
	ed.set_dog("cyborg_c")
	assert_eq(got.size(), 1, "set_dog shows without emitting")
	ed._trot_dog(0.1)
	assert_true((ed._dog_preview as Dog3D).moving, "the preview trots in place")
	ed.free()


## Every dog has a short name in each language, and the row its title.
func test_every_dog_has_words() -> void:
	for id in DogSkins.IDS:
		assert_true(UiText.DOG_NAMES.has(id), id)
		for locale in ["en", "fr"]:
			var po := FileAccess.get_file_as_string("res://i18n/%s.po" % locale)
			assert_true(po.contains('msgid "%s"' % UiText.DOG_NAMES[id]), "%s %s" % [locale, id])
			assert_true(po.contains('msgid "%s"' % UiText.LOOK_DOG), locale)
	for i in Dog3D.SKINS.size():
		assert_true(Dog3D.SKINS[i]["id"] in DogSkins.IDS)
	assert_eq(Dog3D.skin_index(DogSkins.DEFAULT), -1, "the default is the drawn dog")


class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal snapshot_received(players: Array)
	signal creatures_received(creatures: Array)
	signal marks_received(marks: Array)
	var my_peer_id := 1

	func request_move(_cell: Vector2i) -> void:
		pass

	func request_stop() -> void:
		pass


func _view() -> Node2D:
	var view: Node2D = load("res://client/world_view.gd").new()
	view.client = FakeClient.new()
	view.add_child(view.client)
	view._ready()
	return view


func _dog(id: int, skin: Variant) -> Dictionary:
	var c := {"id": id, "kind": "dog", "owner": id, "pos": Vector2(2, 3)}
	if skin != null:
		c["skin"] = skin
	return c


## Each player's dog is drawn as its owner chose: the sprite for the default (or an unknown id), the
## 3D model of the id otherwise, changed when the owner changes it.
func test_world_draws_each_dog_as_chosen() -> void:
	var view := _view()
	view.client.creatures_received.emit([_dog(1, null), _dog(2, "cyborg_b"), _dog(3, "wolf")])
	var n1: Node2D = view._creatures[1]["node"]
	var n2: Node2D = view._creatures[2]["node"]
	var n3: Node2D = view._creatures[3]["node"]
	assert_true(n1.get_node("Sprite").visible and n1.get_node_or_null("Dog3D") == null, "default: the sprite")
	assert_false(n2.get_node("Sprite").visible)
	assert_eq((n2.get_node("Dog3D") as Dog3D).skin, Dog3D.skin_index("cyborg_b"))
	assert_true(n3.get_node("Sprite").visible and n3.get_node_or_null("Dog3D") == null, "unknown: the default")
	var model: Node = n2.get_node("Dog3D")
	view.client.creatures_received.emit([_dog(1, "cyborg_c"), _dog(2, "cyborg_b"), _dog(3, "wolf")])
	assert_eq((n1.get_node("Dog3D") as Dog3D).skin, Dog3D.skin_index("cyborg_c"), "changed by its owner")
	assert_true(n2.get_node("Dog3D") == model, "unchanged: the same model is kept")
	view.client.creatures_received.emit([_dog(1, null), _dog(2, "cyborg_b"), _dog(3, "wolf")])
	assert_true(n1.get_node("Sprite").visible, "back to the sprite")
	view.free()


## F9 no longer changes the dogs; F10 still forces a gait (a debug key, like F3 and F4).
func test_no_f9_and_f10_forces_a_gait() -> void:
	var src := FileAccess.get_file_as_string("res://client/world_view.gd")
	assert_false(src.contains("KEY_F9"))
	var view := _view()
	view.client.creatures_received.emit([_dog(2, "cyborg_a")])
	view.cycle_forced_gait()
	assert_eq((view._creatures[2]["node"].get_node("Dog3D") as Dog3D).forced, "walk")
	assert_true(view._gait_hint.visible)
	view.client.creatures_received.emit([_dog(2, "cyborg_a"), _dog(4, "cyborg_c")])
	assert_eq((view._creatures[4]["node"].get_node("Dog3D") as Dog3D).forced, "walk", "a new dog too")
	for i in 3:
		view.cycle_forced_gait()
	assert_eq((view._creatures[2]["node"].get_node("Dog3D") as Dog3D).forced, "", "back to auto")
	assert_false(view._gait_hint.visible)
	view.free()
