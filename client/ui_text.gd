## Every text of the client UI, in one place. Each one is a key of the gettext files i18n/<locale>.po
## (client/i18n.gd), which hold its words in each language.
class_name UiText
extends RefCounted

const TITLE := "ui.title"
const TAGLINE := "ui.tagline"
const NAME_LABEL := "ui.name_label"
const NAME_PLACEHOLDER := "ui.name_placeholder"
const NAME_HINT := "ui.name_hint"  ## %d: Protocol.NAME_MAX_LEN (name_hint())
## In-game HUD (client/hud.gd).
const HUNGER := "hud.hunger"
const STARVING := "hud.starving"
const BAG := "bag.title"
const BAG_EMPTY := "bag.empty"
## Server notice key (shared/net.gd notice) -> text key. Formatted by notice().
const NOTICES := {
	"gathered": "notice.gathered",
	"bush_empty": "notice.bush_empty",
	"too_far": "notice.too_far",
	"ate": "notice.ate",
	"tree_empty": "notice.tree_empty",
	"fire_built": "notice.fire_built",
	"need_sticks": "notice.need_sticks",
	"fire_here": "notice.fire_here",
	"hunt": "notice.hunt",
	"no_prey": "notice.no_prey",
	"dog_busy": "notice.dog_busy",
	"cooked": "notice.cooked",
	"no_fire": "notice.no_fire",
	"bag_full": "notice.bag_full",
}
const COOK := "bag.cook"
## Key hints (physical key, what it does), shown as key caps under the hunger bar.
## Physical keys sit next to the movement keys whatever the layout: E and Q on QWERTY, E and A on AZERTY.
const KEYS := [[KEY_E, "hud.key_bag"], [KEY_Q, "hud.key_whistle"]]
## The bag window (client/bag_view.gd).
const FOOD_DESC := "bag.food_desc"  ## %d: food points
const COOKS_DESC := "bag.cooks_desc"  ## %s: the cooked item's name
const STICKS_DESC := "bag.sticks_desc"
const CRAFT := "bag.craft"
const FIRE_RECIPE := "bag.fire_recipe"
const EAT := "bag.eat"
## The start menu (client/login_ui.gd, client/title_screen.gd).
const PLAY := "menu.play"
const QUIT := "menu.quit"
const BACK := "menu.back"
const ENTER := "menu.enter"
const SETTINGS := "menu.settings"
const CREDITS := "menu.credits"
const LANGUAGE := "menu.language"  ## the title button, the Langue screen and the settings tab

## The credits screen (client/credits_screen.gd), from ASSETS.toml (client/credits.gd).
const CREDITS_COMMUNITY := "credits.community"
const CREDITS_PEOPLE := "credits.people"
const CREDITS_THIRD_PARTY := "credits.third_party"
const CREDITS_TOOLS := "credits.tools"
const CREDITS_FILES := "credits.files"  ## plural on {count}; {kinds}
const CREDITS_LICENSE := "credits.license"  ## plural on the number of licences; %s
const CREDITS_SOURCE := "credits.source"  ## %s: where the asset comes from
const CREDITS_MISSING := "credits.missing"
const CREDITS_HINT := "credits.hint"
## What an asset is (client/credits.gd kind()) -> text key.
const CREDITS_KINDS := {"character": "credits.kind.character", "decals": "credits.kind.decals",
		"dog": "credits.kind.dog", "items": "credits.kind.items", "music": "credits.kind.music",
		"objects": "credits.kind.objects", "sounds": "credits.kind.sounds", "tiles": "credits.kind.tiles",
		"ui": "credits.kind.ui"}
## Licences of ASSETS.toml -> text key of their words.
const CREDITS_LICENSES := {"CC0-1.0": "credits.licence.cc0",
		"LicenseRef-ElevenLabs-in-game-only": "credits.licence.elevenlabs",
		"LicenseRef-Suno-in-game-only": "credits.licence.suno"}

const SETTINGS_TITLE := "settings.title"
const TAB_SOUND := "settings.tab_sound"
const TAB_DISPLAY := "settings.tab_display"
const TAB_CONTROLS := "settings.tab_controls"
const FULLSCREEN := "settings.fullscreen"
const PERCENT := "settings.percent"  ## %d: a volume in percent
## The controls tab (client/settings_menu.gd): what each key does. The bag and the whistle come from KEYS.
const CONTROL_MOVE := "control.move"
const CONTROL_SPRINT := "control.sprint"
const CONTROL_CLICK := "control.click"
const CONTROL_LOOK := "control.look"
const CONTROL_MUTE := "control.mute"
const CONTROL_VOLUME := "control.volume"
const CONTROL_ZOOM := "control.zoom"
const CONTROL_SETTINGS := "control.settings"
const MOUSE_LEFT := "key.mouse_left"
const MOUSE_WHEEL := "key.mouse_wheel"
const PAD_START := "key.pad_start"
## Key caps that are not printed as one character -> text key.
const KEY_CAPS := {KEY_ESCAPE: "key.escape", KEY_SHIFT: "key.shift"}
const LOOK_TITLE := "look.title"
const LOOK_COLOUR := "look.colour"
const LOOK_NONE := "look.none"
const SOUND_CHANNELS := {"master": "sound.master", "music": "sound.music", "ambience": "sound.ambience",
		"effects": "sound.effects", "ui": "sound.ui"}
const MUTE := "settings.mute"
const CLOSE := "settings.close"
const SETTINGS_HINT := "settings.hint"

const CONNECTING := "status.connecting"
const READY := "status.ready"
const JOINING := "status.joining"
const LOST := "status.lost"
const LOST_IN_GAME := "status.lost_in_game"

const NAME_EMPTY := "name.empty"
const NAME_TOO_LONG := "name.too_long"  ## plural on %d, Protocol.NAME_MAX_LEN
const NAME_BAD_CHARS := "name.bad_chars"
const NAME_TAKEN := "name.taken"  ## %s: the name

## The sound debug overlay (F3, client/sound_director.gd).
const DEBUG_SOUND := "debug.sound"  ## {state} {volume}
const DEBUG_SOUND_MUTED := "debug.sound_muted"
const DEBUG_SOUND_ON := "debug.sound_on"
const DEBUG_AMBIENCE_FORCED := "debug.ambience_forced"  ## {current}
const DEBUG_AMBIENCE_AUTO := "debug.ambience_auto"  ## {current} {radius}
const DEBUG_AMBIENCE_ROW := "debug.ambience_row"  ## {mark} {name} {weight} {score}
const DEBUG_BED := "debug.bed"  ## {sound} {at}
const DEBUG_EVENT := "debug.event"  ## {sound} {in}


## The text of `key` in the current language (i18n/<locale>.po), else in English, else the key itself.
## UiText is static, so it cannot use Object.tr(). A Label or Button whose text is a key is translated
## by itself; a text built here is not, so whoever shows it builds it again on
## NOTIFICATION_TRANSLATION_CHANGED.
static func t(key: String) -> String:
	I18n.ensure_loaded()
	return TranslationServer.translate(key)


## The text of `key` for the number `n`, in the plural form the current language uses for it.
static func tn(key: String, n: int) -> String:
	I18n.ensure_loaded()
	return TranslationServer.translate_plural(key, key, n)


static func name_hint() -> String:
	return t(NAME_HINT) % Protocol.NAME_MAX_LEN


## "" if the server would accept the name, otherwise why not (same rules as Protocol.validate_name).
static func name_problem(player_name: String) -> String:
	if Protocol.validate_name(player_name) == "":
		return ""
	if player_name.is_empty():
		return t(NAME_EMPTY)
	if player_name.length() > Protocol.NAME_MAX_LEN:
		return tn(NAME_TOO_LONG, Protocol.NAME_MAX_LEN) % Protocol.NAME_MAX_LEN
	return t(NAME_BAD_CHARS)


## The text shown when the server refuses `player_name` with `reason`. The server refuses a valid
## name only when it is online already (invariant 4), so its English reason is not shown then.
static func rejection(_reason: String, player_name: String) -> String:
	var problem := name_problem(player_name)
	if problem != "":
		return problem
	return t(NAME_TAKEN) % player_name


## The text of a server notice (shared/net.gd notice), or "" for an unknown key. Item names come from
## data/items as they are.
static func notice(key: String, args: Dictionary) -> String:
	if not NOTICES.has(key):
		return ""
	var text: String = NOTICES[key]
	match key:
		"gathered":
			return t(text).format({"count": int(args.get("count", 0)), "item": _item_name(args)})
		"ate", "cooked":
			return t(text) % _item_name(args)
		"need_sticks":
			return tn(text, Protocol.FIRE_STICKS) % Protocol.FIRE_STICKS
	return t(text)


static func _item_name(args: Dictionary) -> String:
	return ItemData.item(String(args.get("item", ""))).get("name", "?")


## A volume in percent, as the settings menu shows it.
static func percent(value: int) -> String:
	return t(PERCENT) % value


## Display servers that know the keyboard layout. Others (headless, web) learn it from key presses.
const LAYOUT_AWARE := ["Windows", "macOS", "X11", "Wayland"]
## The controls listed in the settings menu: {caps, action}. A cap is a physical key, named by cap_text
## after the player's layout, or a text (a mouse button). Read only: the keys are handled in hud.gd,
## look_panel.gd, sound_director.gd, world_view.gd and settings_menu.gd.
static func controls() -> Array:
	var rows := [{"caps": [KEY_W, KEY_A, KEY_S, KEY_D], "action": CONTROL_MOVE},
			{"caps": [KEY_SHIFT], "action": CONTROL_SPRINT}, {"caps": [MOUSE_LEFT], "action": CONTROL_CLICK}]
	for k in KEYS:
		rows.append({"caps": [k[0]], "action": k[1]})
	rows.append_array([{"caps": [KEY_C], "action": CONTROL_LOOK}, {"caps": [KEY_M], "action": CONTROL_MUTE},
			{"caps": [KEY_MINUS, KEY_EQUAL], "action": CONTROL_VOLUME},
			{"caps": [MOUSE_WHEEL], "action": CONTROL_ZOOM},
			{"caps": [KEY_ESCAPE, PAD_START], "action": CONTROL_SETTINGS}])
	return rows


## Remembers the label of the key pressed in `event` (see key_name); true when `seen` changed.
static func learn_key(seen: Dictionary, event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed):
		return false
	var label: Key = event.key_label if event.key_label != KEY_NONE else event.keycode
	if label == KEY_NONE or seen.get(event.physical_keycode) == label:
		return false
	seen[event.physical_keycode] = label
	return true


## The text on a key cap of the controls list: a text cap (a key of the .po files) translated, a
## physical key as key_name names it, translated for Escape and Shift and as its character for a
## symbol key (")" rather than "ParenRight").
static func cap_text(cap: Variant, seen := {}) -> String:
	if cap is String:
		return t(cap)
	var label := key_label(cap, seen)
	if KEY_CAPS.has(label):
		return t(KEY_CAPS[label])
	if label > KEY_SPACE and label < KEY_SPECIAL:
		return String.chr(label).to_upper()
	return OS.get_keycode_string(label)


## Physical keys that AZERTY labels differently from QWERTY (the letters around the movement keys).
const AZERTY := {KEY_Q: KEY_A, KEY_A: KEY_Q, KEY_W: KEY_Z, KEY_Z: KEY_W}


## The name printed on the player's keyboard for a physical key. `seen` maps physical keys the
## player pressed to their labels: it names those keys, and tells AZERTY apart from QWERTY.
static func key_name(physical: Key, seen := {}) -> String:
	return OS.get_keycode_string(key_label(physical, seen))


## The key printed on the player's keyboard for a physical key (see key_name).
static func key_label(physical: Key, seen := {}) -> Key:
	if seen.has(physical):
		return seen[physical]
	if DisplayServer.get_name() in LAYOUT_AWARE:
		return DisplayServer.keyboard_get_label_from_physical(physical)
	for k in AZERTY:
		if seen.get(k) == AZERTY[k]:
			return AZERTY.get(physical, physical)
	return physical
