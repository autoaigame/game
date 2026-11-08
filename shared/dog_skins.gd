## The dogs a player can choose in the look editor: the ids the client sends (set_dog) and the server
## checks. "classic" is the drawn dog (assets/dog.png, client/dog_anim.gd), the others the cyborg models
## of client/dog_3d.gd. The choice only changes how the dog is drawn: its behaviour is the same.
class_name DogSkins
extends RefCounted

const DEFAULT := "classic"
## In editor order.
const IDS: Array[String] = ["classic", "cyborg_a", "cyborg_b", "cyborg_c"]


## `value` if it is a known dog id, the default dog otherwise (a junk value, an older or newer client's).
static func valid(value: Variant) -> String:
	if (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and String(value) in IDS:
		return String(value)
	return DEFAULT


## The next dog after `id` (step 1) or the one before (step -1), wrapping round.
static func cycle(id: String, step: int) -> String:
	return IDS[posmod(IDS.find(valid(id)) + step, IDS.size())]
