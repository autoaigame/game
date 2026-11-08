## The languages to choose from (client/i18n.gd languages()), one button each, named in its own language
## and never translated, the language shown now pressed and ticked. Pressing one shows the whole UI in
## it at once and saves it (I18n.choose). Used by the Langue screen (client/language_screen.gd) and the
## settings menu's Langue tab (client/settings_menu.gd).
extends VBoxContainer

signal chosen(locale: String)

var sounds: Node  ## client/sound_director.gd, or null (no sound)
var settings_path := ClientSettings.PATH  ## where the choice is kept (tests use their own)
var _buttons := {}  ## locale -> Button
var _order: Array = []  ## locales, top to bottom


func _init() -> void:
	add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for lang in I18n.languages():
		var locale: String = lang["locale"]
		var b := Button.new()
		b.text = lang["name"]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # a language's name is never translated
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "TabButton"
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func(): choose(locale))
		b.mouse_entered.connect(func(): _play("hover"))
		b.button_down.connect(func(): _play("click"))
		add_child(b)
		_buttons[locale] = b
		_order.append(locale)
	_mark()


## Shows the UI in `locale` from now on and keeps the choice.
func choose(locale: String) -> void:
	if not _buttons.has(locale):
		return
	I18n.choose(locale, settings_path)  # saved even when it is the system's: the player chose it
	_mark()
	chosen.emit(locale)


func button(locale: String) -> Button:
	return _buttons.get(locale)


func locales() -> Array:
	return _order.duplicate()


## The button of the language shown now: the focus starts there.
func current_button() -> Button:
	return _buttons.get(I18n.current(_order), _buttons[_order[0]] if not _order.is_empty() else null)


## The other list (title screen or settings) may have changed the language: the mark follows.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not _buttons.is_empty():
		_mark()


func _mark() -> void:
	var now := I18n.current(_order)
	for l in _buttons:
		var b: Button = _buttons[l]
		b.set_pressed_no_signal(l == now)
		b.icon = UiTheme.icon("ok") if l == now else null


func _play(kind: String) -> void:
	if sounds != null:
		sounds.ui(kind)
