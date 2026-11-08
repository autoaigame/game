## Every text of the client UI, in one place for a future translation (French for now).
class_name UiText
extends RefCounted

const TITLE := "autoaigame"
const TAGLINE := "un seul monde, qui ne s'arrête jamais"
const NAME_LABEL := "Ton nom"
const NAME_PLACEHOLDER := "ex. Corbeau_42"
const NAME_HINT := "Lettres, chiffres, _ et - (%d au plus)"
## In-game HUD (client/hud.gd).
const HUNGER := "Faim"
const STARVING := "Affamé : tu marches plus lentement"
const BAG := "Sac"
const BAG_EMPTY := "Ton sac est vide."
const NOTICES := {
	"gathered": "+%d %s",
	"bush_empty": "Ce buisson n'a plus de baies. Reviens plus tard.",
	"too_far": "Trop loin.",
	"ate": "Tu manges : %s",
	"tree_empty": "Plus de bâtons sur cet arbre pour l'instant.",
	"fire_built": "Tu allumes un feu.",
	"need_sticks": "Il te faut %d bâtons pour faire un feu." % Protocol.FIRE_STICKS,
	"fire_here": "Il y a déjà un feu ici.",
	"hunt": "Ton chien part en chasse !",
	"no_prey": "Aucun animal à chasser près de toi.",
	"dog_busy": "Ton chien te rapporte déjà sa prise.",
	"cooked": "Cuit : %s",
	"no_fire": "Il te faut un feu tout près pour cuire.",
	"bag_full": "Ton sac est plein.",
}
const COOK := "Cuire"
## Key hints (physical key, what it does), shown as key caps under the hunger bar.
## Physical keys sit next to the movement keys whatever the layout: E and Q on QWERTY, E and A on AZERTY.
const KEYS := [[KEY_E, "Sac"], [KEY_Q, "Siffler le chien"]]
## The bag window (client/bag_view.gd).
const FOOD_DESC := "Nourrit : +%d"
const COOKS_DESC := "Sur un feu, devient : %s"
const STICKS_DESC := "Sert à faire un feu."
const CRAFT := "Fabriquer"
const FIRE_RECIPE := "Faire un feu"
const EAT := "Manger"
## The start menu (client/login_ui.gd, client/title_screen.gd).
const PLAY := "Jouer"
const QUIT := "Quitter"
const BACK := "Retour"
const ENTER := "Entrer dans le monde"
const SETTINGS := "Paramètres"
const CREDITS := "Crédits"

## The credits screen (client/credits_screen.gd), from data/credits.json.
const CREDITS_COMMUNITY := "Ce jeu est construit par sa communauté : chacun propose ses changements en pull request, et celles qui recueillent assez de votes entrent dans le jeu."
const CREDITS_PEOPLE := "Contributeurs"
const CREDITS_THIRD_PARTY := "Ressources tierces"
const CREDITS_TOOLS := "Outils de génération"
const CREDITS_FILES := "%d fichiers : %s"
const CREDITS_ONE_FILE := "1 fichier : %s"
const CREDITS_LICENSE := "Licence : %s"
const CREDITS_LICENSES_LABEL := "Licences : %s"
const CREDITS_SOURCE := "Source : %s"
const CREDITS_HINT := "Haut et bas pour faire défiler, Échap ou B pour revenir"
## What an asset is (art/credits.gd kind()).
const CREDITS_KINDS := {"character": "personnage", "decals": "détails du sol", "dog": "chien",
		"items": "objets du sac", "music": "musique", "objects": "décor", "sounds": "sons", "tiles": "sols",
		"ui": "interface"}
## Licences of ASSETS.toml, in words.
const CREDITS_LICENSES := {"CC0-1.0": "CC0 1.0 (domaine public)",
		"LicenseRef-ElevenLabs-in-game-only": "sons ElevenLabs, dans ce jeu seulement",
		"LicenseRef-Suno-in-game-only": "musique Suno, dans ce jeu seulement"}

const SETTINGS_TITLE := "Paramètres"
const TAB_SOUND := "Son"
const TAB_DISPLAY := "Affichage"
const TAB_CONTROLS := "Commandes"
const FULLSCREEN := "Plein écran"
## The controls tab (client/settings_menu.gd): what each key does. The bag and the whistle come from KEYS.
const CONTROL_MOVE := "Se déplacer"
const CONTROL_CLICK := "Aller, cueillir, ramasser"
const CONTROL_LOOK := "Apparence"
const CONTROL_MUTE := "Couper le son"
const CONTROL_VOLUME := "Baisser, monter le volume"
const CONTROL_ZOOM := "Zoomer"
const CONTROL_SETTINGS := "Paramètres"
const MOUSE_LEFT := "Clic gauche"
const MOUSE_WHEEL := "Molette"
const PAD_START := "Start (manette)"
## Key caps that are not printed as one character.
const KEY_CAPS := {KEY_ESCAPE: "Échap"}
const LOOK_TITLE := "Apparence (C pour fermer)"
const LOOK_COLOUR := "Couleur (clic droit : précédente)"
const LOOK_NONE := "—"
const SOUND_CHANNELS := {"master": "Général", "music": "Musique", "ambience": "Ambiance", "effects": "Effets",
		"ui": "Interface"}
const MUTE := "Couper le son (M)"
const CLOSE := "Fermer"
const SETTINGS_HINT := "Échap pour fermer"

const CONNECTING := "Connexion au serveur…"
const READY := "Serveur prêt."
const JOINING := "Entrée dans le monde…"
const LOST := "Le serveur ne répond pas. Recharge la page pour réessayer."
const LOST_IN_GAME := "Connexion perdue. Recharge la page pour revenir."

const NAME_EMPTY := "Écris un nom pour entrer."
const NAME_TOO_LONG := "%d caractères au plus."
const NAME_BAD_CHARS := "Lettres, chiffres, _ et - seulement."
const NAME_TAKEN := "Le nom %s est déjà en jeu. Choisis-en un autre."


## "" if the server would accept the name, otherwise why not (same rules as Protocol.validate_name).
static func name_problem(player_name: String) -> String:
	if Protocol.validate_name(player_name) == "":
		return ""
	if player_name.is_empty():
		return NAME_EMPTY
	if player_name.length() > Protocol.NAME_MAX_LEN:
		return NAME_TOO_LONG % Protocol.NAME_MAX_LEN
	return NAME_BAD_CHARS


## The text shown when the server refuses `player_name` with `reason`. The server refuses a valid
## name only when it is online already (invariant 4), so its English reason is not shown then.
static func rejection(_reason: String, player_name: String) -> String:
	var problem := name_problem(player_name)
	if problem != "":
		return problem
	return NAME_TAKEN % player_name


## The text of a server notice (shared/net.gd notice), or "" for an unknown key.
static func notice(key: String, args: Dictionary) -> String:
	if key == "gathered":
		return NOTICES[key] % [int(args.get("count", 0)), ItemData.item(String(args.get("item", ""))).get("name", "?")]
	if key == "ate" or key == "cooked":
		return NOTICES[key] % ItemData.item(String(args.get("item", ""))).get("name", "?")
	return NOTICES.get(key, "")


## Display servers that know the keyboard layout. Others (headless, web) learn it from key presses.
const LAYOUT_AWARE := ["Windows", "macOS", "X11", "Wayland"]
## The controls listed in the settings menu: {caps, action}. A cap is a physical key, named by cap_text
## after the player's layout, or a text (a mouse button). Read only: the keys are handled in hud.gd,
## look_panel.gd, sound_director.gd, world_view.gd and settings_menu.gd.
static func controls() -> Array:
	var rows := [{"caps": [KEY_W, KEY_A, KEY_S, KEY_D], "action": CONTROL_MOVE},
			{"caps": [MOUSE_LEFT], "action": CONTROL_CLICK}]
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


## The text on a key cap of the controls list: a text cap as it is, a physical key as key_name names
## it, in French for Escape and as its character for a symbol key (")" rather than "ParenRight").
static func cap_text(cap: Variant, seen := {}) -> String:
	if cap is String:
		return cap
	var label := key_label(cap, seen)
	if KEY_CAPS.has(label):
		return KEY_CAPS[label]
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
