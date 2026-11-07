## Every text of the client UI, in one place for a future translation (French for now).
class_name UiText
extends RefCounted

const TITLE := "autoaigame"
const TAGLINE := "un seul monde, qui ne s'arrête jamais"
const NAME_LABEL := "Ton nom"
const NAME_PLACEHOLDER := "ex. Corbeau_42"
const NAME_HINT := "Lettres, chiffres, _ et - (%d au plus)"
const ENTER := "Entrer dans le monde"
const SETTINGS := "Paramètres"

const SETTINGS_TITLE := "Paramètres"
const TAB_SOUND := "Son"
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
