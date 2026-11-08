## Start menu, drawn over the world until the server welcomes us. Under the title band, one screen at a
## time from a stack; the title and play screens show the connection state. The title screen (client/title_screen.gd) is the root;
## Jouer opens the play screen (look, name, Entrer), Langue the languages (client/language_screen.gd),
## Crédits the credits (client/credits_screen.gd). A new screen is a Control given to add_screen(),
## opened with go(id); Escape and Retour go back. Texts are in client/ui_text.gd, looks in client/ui_theme.gd.
extends CanvasLayer

enum State { CONNECTING, READY, JOINING, LOST }
const FOCUS_FIELD := 0
const FOCUS_BUTTON := 1
const FADE_IN_S := 0.3
const FADE_OUT_S := 0.4
const SCREEN_FADE_S := 0.15
const ROOT_SCREEN := "title"
const PLAY_SCREEN := "play"
const CREDITS_SCREEN := "credits"
const LANGUAGE_SCREEN := "language"
const ESCAPE_SETTINGS := "settings"  ## Escape opens the settings menu (it does so itself)
const ESCAPE_BACK := "back"  ## Escape goes back a screen
const FOCUS_SETTINGS_BUTTON := "settings_button"  ## the title's Paramètres button
const FOCUS_FIRST := "first"  ## the first control of the screen shown
## On the title screen the column fills the view but these pixels, the logo at the top and the buttons
## at the bottom, so the colossus shows between them. Other screens are centred under a smaller logo.
const TITLE_COLUMN_MARGIN := 12

var client: Node  ## client/client.gd
var sounds: Node  ## client/sound_director.gd, or null (no sound)
var settings: Node  ## client/settings_menu.gd, or null
var state := State.CONNECTING
var _root := Control.new()
var _center := CenterContainer.new()  ## the column of the menu, over the backdrop
var _column := VBoxContainer.new()
var _logo_art: Control
var _tagline: Label
var _title_gap := Control.new()  ## pushes the title screen's buttons to the bottom
var _screen_box := VBoxContainer.new()  ## holds every screen; only the top of the stack shows
var _screens := {}  ## id -> Control
var _stack: Array = [ROOT_SCREEN]
var _screen_tween: Tween
var _title: Node  ## client/title_screen.gd
var _name_edit := LineEdit.new()
var _button := Button.new()
var _back_button := Button.new()
var _hint := Label.new()
var _hint_icon := TextureRect.new()
## What the error under the name field is about, kept so that it is built again in a new language.
enum Hint { RULE, PROBLEM, REJECTED }  ## the naming rule, a name the client refuses, a server refusal
var _hint_kind := Hint.RULE
var _hint_name := ""  ## the name refused (PROBLEM, REJECTED)
var _hint_reason := ""  ## the server's reason (REJECTED)
var _status := Label.new()  ## on the play screen
var _status_icon := TextureRect.new()
var _title_status := Label.new()  ## under the title screen's buttons
var _title_status_icon := TextureRect.new()
var _in_game := false
var _tween: Tween
var _focus_next: Control = null  ## control to focus on the next frame (once in the tree)


## Where the focus starts: on the button when a remembered name fills the field.
static func initial_focus(remembered: String) -> int:
	return FOCUS_BUTTON if remembered != "" else FOCUS_FIELD


## `stack` with screen `id` on top (not twice in a row). The stack given is not changed.
static func pushed(stack: Array, id: String) -> Array:
	var s := stack.duplicate()
	if s.is_empty() or s.back() != id:
		s.append(id)
	return s


## `stack` without its top screen; the root screen always stays.
static func popped(stack: Array) -> Array:
	var s := stack.duplicate()
	if s.size() > 1:
		s.pop_back()
	return s


## What Escape does with `stack` shown: the settings on the root screen, back anywhere else.
static func escape_action(stack: Array) -> String:
	return ESCAPE_SETTINGS if stack.size() <= 1 else ESCAPE_BACK


## Escape, a pad's B (the east button; in Godot 4.7 ui_cancel only holds Escape) or another ui_cancel
## button, pressed (not a repeat). A pad's Start is not one: it opens the settings menu.
static func is_back(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	if event is InputEventJoypadButton:
		return event.pressed and (event.button_index == JOY_BUTTON_B or event.is_action_pressed("ui_cancel"))
	return false


## Where the focus goes when the settings menu closes over `stack`.
static func focus_after_settings(stack: Array) -> String:
	return FOCUS_SETTINGS_BUTTON if stack.size() <= 1 else FOCUS_FIRST


## The stack once the connection is lost: back to the title screen when `reset` (the menu was hidden,
## in game), otherwise the screen shown stays.
static func stack_after_lost(stack: Array, reset: bool) -> Array:
	return [ROOT_SCREEN] if reset else stack.duplicate()


## The stack when the server refuses the name: the play screen shows, to say why.
static func stack_after_rejected(stack: Array) -> Array:
	return pushed([ROOT_SCREEN] if stack.is_empty() else stack, PLAY_SCREEN)


## The screen a title button opens, or "" (Paramètres opens the settings menu, Quitter quits).
static func screen_for(choice: String) -> String:
	return {"play": PLAY_SCREEN, "language": LANGUAGE_SCREEN, "credits": CREDITS_SCREEN}.get(choice, "")


## The title button that takes the focus back on the title screen, coming from screen `left`: the
## one that opened it, else Jouer.
static func title_button_after_back(left: String) -> String:
	return {CREDITS_SCREEN: "credits", LANGUAGE_SCREEN: "language"}.get(left, "play")


static func button_enabled(s: State) -> bool:
	return s == State.READY


## [icon key, text] of the status line in state `s`.
static func status_of(s: State) -> Array:
	match s:
		State.READY:
			return ["ok", UiText.READY]
		State.JOINING:
			return ["wait", UiText.JOINING]
		State.LOST:
			return ["error", UiText.LOST]
	return ["wait", UiText.CONNECTING]


func _ready() -> void:
	layer = 10
	_build()
	var remembered := ClientSettings.load_name()
	_name_edit.text = remembered
	_name_edit.caret_column = remembered.length()
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		_set_state(State.LOST)
	elif peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_set_state(State.READY)
	else:
		_set_state(State.CONNECTING)
	multiplayer.connected_to_server.connect(_on_connected)
	client.welcomed.connect(func(_c): _on_welcomed())
	client.join_rejected.connect(_on_rejected)
	client.connection_lost.connect(_on_lost)
	if settings != null:
		settings.opened.connect(_on_settings_opened)
		settings.closed.connect(_on_settings_closed)
		settings.start_menu = self
	_root.modulate.a = 0.0
	_fade_to(1.0, FADE_IN_S)
	_show_top(false)


## Opens screen `id` over the current one.
func go(id: String) -> void:
	_stack = pushed(_stack, id)
	_show_top(true)


## Back to the previous screen (never past the root).
func back() -> void:
	if _stack.size() <= 1:
		return
	var left: String = top_screen()
	_stack = popped(_stack)
	_show_top(true)
	if top_screen() == ROOT_SCREEN:
		_focus_next = _title.button(title_button_after_back(left))


func top_screen() -> String:
	return _stack.back()


func has_screen(id: String) -> bool:
	return _screens.has(id)


## Registers screen `id`, hidden until go(id). `first_focus` takes the focus when it shows.
func add_screen(id: String, screen: Control, first_focus: Control) -> void:
	screen.visible = false
	screen.set_meta("first_focus", first_focus)
	_screens[id] = screen
	_screen_box.add_child(screen)


## Escape or ui_cancel while the settings menu is closed (client/settings_menu.gd asks): back a screen
## when not on the root. True when the event was used.
func use_escape(event: InputEvent) -> bool:
	if not _menu_up() or not is_back(event) or escape_action(_stack) != ESCAPE_BACK:
		return false
	_play_ui("click")
	back()
	return true


## Whether the menu is in front: before joining, or back after the connection was lost in game.
func _menu_up() -> bool:
	return visible and (not _in_game or state == State.LOST)


func _show_top(fade: bool) -> void:
	var id: String = top_screen()
	for k in _screens:
		_screens[k].visible = k == id
	_lay_out(id == ROOT_SCREEN)
	var screen: Control = _screens[id]
	if fade and is_inside_tree():  # a tween needs the tree
		if _screen_tween != null:
			_screen_tween.kill()
		screen.modulate.a = 0.0
		_screen_tween = create_tween()
		_screen_tween.tween_property(screen, "modulate:a", 1.0, SCREEN_FADE_S)
	# focused on the next frame, once the screen is in the tree and visible
	_focus_next = _first_focus(id)


func _first_focus(id: String) -> Control:
	if id == PLAY_SCREEN:
		return _button if initial_focus(_name_edit.text) == FOCUS_BUTTON else _name_edit
	var screen: Control = _screens[id]
	if screen.has_method("first_focus"):  # it knows best when it shows (Langue: the language shown)
		return screen.first_focus()
	return screen.get_meta("first_focus")


## Gives the focus asked for once its control shows (the settings menu may hide this one meanwhile).
func _process(_delta: float) -> void:
	if _focus_next != null and _focus_next.is_visible_in_tree():
		_focus_next.grab_focus()
		_focus_next = null


func _build() -> void:
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.build()
	add_child(_root)
	_root.add_child(_backdrop())
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_center)
	var column := _column
	column.add_theme_constant_override("separation", 10)
	_center.add_child(column)

	_logo_art = _logo()
	column.add_child(_logo_art)
	_tagline = _label(UiText.TAGLINE, "TaglineLabel")
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_tagline)
	_title_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title_gap)
	_screen_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_screen_box)
	var title_page := VBoxContainer.new()
	title_page.add_theme_constant_override("separation", 10)
	_title = load("res://client/title_screen.gd").new()
	_title.sounds = sounds
	_title.chosen.connect(_on_title_chosen)
	title_page.add_child(_title)
	var status_row := _icon_row(_title_status_icon, _title_status)
	_title_status.theme_type_variation = "TaglineLabel"  # outlined, over the backdrop
	status_row.custom_minimum_size = Vector2(420, 0)
	status_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_page.add_child(status_row)
	_title_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_screen(ROOT_SCREEN, title_page, _title.first_button())
	add_screen(PLAY_SCREEN, _build_play_screen(), _button)
	var credits: Control = load("res://client/credits_screen.gd").new()
	credits.sounds = sounds
	credits.back_pressed.connect(back)
	add_screen(CREDITS_SCREEN, credits, credits.first_focus())
	var languages: Control = load("res://client/language_screen.gd").new(sounds)
	languages.back_pressed.connect(back)
	add_screen(LANGUAGE_SCREEN, languages, languages.first_focus())


## The title screen: big logo at the top, tagline, buttons at the bottom. Other screens (the play
## screen is tall): the logo at 1 px per texel above them, no tagline, centred.
func _lay_out(title: bool) -> void:
	var tex: Texture2D = _logo_art.get("texture")
	if tex != null:
		_logo_art.custom_minimum_size = tex.get_size() * (UiTheme.LOGO_SCALE if title else 1)
	_tagline.visible = title
	_title_gap.visible = title
	var view_h: float = ProjectSettings.get_setting("display/window/size/viewport_height", 540)
	_column.custom_minimum_size.y = view_h - 2 * TITLE_COLUMN_MARGIN if title else 0.0


## Behind the menu: the colossus's valley (assets/ui/title_bg.png) at UiTheme.BACKDROP_SCALE, or the
## world darkened and greyed if the picture is missing.
func _backdrop() -> Control:
	var tex := UiTheme.picture("title_bg")
	if tex == null:
		var veil := ColorRect.new()
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://client/menu_veil.gdshader")
		veil.material = mat
		return veil
	var bg := TextureRect.new()
	bg.texture = tex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return bg


## The name of the game: the logo (assets/ui/logo.png) at UiTheme.LOGO_SCALE, or the title band.
func _logo() -> Control:
	var tex := UiTheme.picture("logo")
	if tex != null:
		var logo := TextureRect.new()
		logo.texture = tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_SCALE
		logo.custom_minimum_size = tex.get_size() * UiTheme.LOGO_SCALE
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		return logo
	var band := PanelContainer.new()
	band.theme_type_variation = "TitleBand"
	band.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	band.custom_minimum_size = Vector2(300, UiTheme.TITLE_BAND_H)
	var title := _label(UiText.TITLE, "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(title)
	return band


## The look, the name and Entrer: the look is chosen before entering.
func _build_play_screen() -> Control:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 10)
	pair.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var look_panel := PanelContainer.new()
	pair.add_child(look_panel)
	var worn: Variant = client.get("look") if client != null else null
	var editor := LookEditor.new(worn if worn is Array else [])
	editor.look_changed.connect(func(l: Array): if client != null and client.has_method("set_look"): client.set_look(l))
	look_panel.add_child(editor)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_label(UiText.NAME_LABEL, ""))
	_name_edit.placeholder_text = UiText.NAME_PLACEHOLDER
	_name_edit.max_length = Protocol.NAME_MAX_LEN
	_name_edit.custom_minimum_size = Vector2(0, 36)
	_name_edit.text_submitted.connect(func(_t): _submit())
	_name_edit.text_changed.connect(func(_t): _show_hint())
	box.add_child(_name_edit)
	box.add_child(_icon_row(_hint_icon, _hint))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_show_hint()
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	box.add_child(gap)
	_button.text = UiText.ENTER
	_button.custom_minimum_size = Vector2(0, 44)
	_button.pressed.connect(_submit)
	_button.mouse_entered.connect(func(): _play("hover"))
	_button.button_down.connect(func(): _play("click"))
	box.add_child(_button)
	_back_button.text = UiText.BACK
	_back_button.custom_minimum_size = Vector2(0, 36)
	_back_button.theme_type_variation = "TabButton"
	_back_button.pressed.connect(back)
	_back_button.mouse_entered.connect(func(): _play_ui("hover"))
	_back_button.button_down.connect(func(): _play_ui("click"))
	box.add_child(_back_button)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 2)
	box.add_child(gap2)
	box.add_child(_icon_row(_status_icon, _status))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD

	var field_path := _name_edit.get_path_to(_button)
	_name_edit.focus_neighbor_bottom = field_path
	_name_edit.focus_next = field_path
	var button_path := _button.get_path_to(_name_edit)
	_button.focus_neighbor_top = button_path
	_button.focus_previous = button_path
	_button.focus_neighbor_bottom = _button.get_path_to(_back_button)
	_button.focus_next = _button.get_path_to(_back_button)
	_back_button.focus_neighbor_top = _back_button.get_path_to(_button)
	_back_button.focus_previous = _back_button.get_path_to(_button)
	_back_button.focus_neighbor_bottom = _back_button.get_path_to(_name_edit)
	_back_button.focus_next = _back_button.get_path_to(_name_edit)
	return pair


func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _icon_row(icon: TextureRect, label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(12, 12)
	row.add_child(icon)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _on_title_chosen(id: String) -> void:
	if screen_for(id) != "":
		go(screen_for(id))
		return
	match id:
		"settings":
			_open_settings()
		"quit":
			get_tree().quit()


func _open_settings() -> void:
	if settings != null:
		settings.open()


## The settings menu takes this one's place while it is open; the backdrop stays behind it.
func _on_settings_opened() -> void:
	_center.visible = false


## Back from the settings menu while this menu shows: the focus returns to the title's Paramètres
## button, or to the first control of the screen shown.
func _on_settings_closed() -> void:
	_center.visible = true
	if _menu_up():
		var to := focus_after_settings(_stack)
		_focus_next = _title.button("settings") if to == FOCUS_SETTINGS_BUTTON else _first_focus(top_screen())


func _play(kind: String) -> void:
	if not _button.disabled:
		_play_ui(kind)


func _play_ui(kind: String) -> void:
	if sounds != null:
		sounds.ui(kind)


func _set_state(s: State) -> void:
	state = s
	var st := status_of(s)
	var text: String = (UiText.LOST_IN_GAME if _in_game else UiText.LOST) if s == State.LOST else st[1]
	for row in [[_status_icon, _status], [_title_status_icon, _title_status]]:
		_set_icon(row[0], st[0])
		row[1].text = text
	_button.disabled = not button_enabled(s)
	_name_edit.editable = s != State.JOINING and s != State.LOST


func _set_icon(rect: TextureRect, key: String) -> void:
	rect.texture = UiTheme.icon(key) if key != "" else null


## The texts built here are built again in the new language; the others are keys that their Label
## or Button translates by itself.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _hint.get_parent() != null:
		_refresh_hint()


## Shows under the field the error of `kind` about `player_name` (and the server's `reason`), or
## the naming rule for Hint.RULE.
func _show_hint(kind := Hint.RULE, player_name := "", reason := "") -> void:
	_hint_kind = kind
	_hint_name = player_name
	_hint_reason = reason
	_refresh_hint()


func _hint_text() -> String:
	match _hint_kind:
		Hint.PROBLEM:
			return UiText.name_problem(_hint_name)
		Hint.REJECTED:
			return UiText.rejection(_hint_reason, _hint_name)
	return ""


func _refresh_hint() -> void:
	var error := _hint_text()
	_hint.text = error if error != "" else UiText.name_hint()
	_hint.theme_type_variation = "ErrorLabel" if error != "" else "HintLabel"
	_set_icon(_hint_icon, "error" if error != "" else "")


func _submit() -> void:
	if state != State.READY:
		return
	var typed := _name_edit.text
	if UiText.name_problem(typed) != "":
		_show_hint(Hint.PROBLEM, typed)
		_name_edit.grab_focus()
		return
	_show_hint()
	_set_state(State.JOINING)
	client.join_with(_name_edit.text)


func _on_connected() -> void:
	if state == State.CONNECTING:
		_set_state(State.READY)


func _on_rejected(reason: String) -> void:
	_set_state(State.READY)
	var refused: String = client.player_name
	_show_hint(Hint.REJECTED, refused, reason)
	var to := stack_after_rejected(_stack)
	if to != _stack:
		_stack = to
		_show_top(true)
	_focus_next = _name_edit
	_name_edit.select_all()


func _on_welcomed() -> void:
	_in_game = true
	ClientSettings.save_name(client.player_name)
	var f := get_viewport().gui_get_focus_owner()
	if f != null and _root.is_ancestor_of(f):
		f.release_focus()
	_fade_to(0.0, FADE_OUT_S).finished.connect(func(): visible = false)


## The menu comes back on its title screen, saying the connection is lost.
func _on_lost() -> void:
	var was_hidden := not visible
	visible = true
	_set_state(State.LOST)
	var to := stack_after_lost(_stack, was_hidden or _in_game)
	if to != _stack:
		_stack = to
		_show_top(false)
	_fade_to(1.0, FADE_IN_S)


func _fade_to(alpha: float, seconds: float) -> Tween:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", alpha, seconds)
	return _tween
