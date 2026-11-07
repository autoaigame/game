## A player's inventory: item id -> count (only ids with a count above 0). Pure functions (server only).
extends RefCounted

const MAX_STACK := 99


static func count(inv: Dictionary, id: String) -> int:
	return inv.get(id, 0)


## Adds up to `n` of an item, at most MAX_STACK in all; returns how many were added.
static func add(inv: Dictionary, id: String, n: int) -> int:
	var added := clampi(MAX_STACK - count(inv, id), 0, n)
	if added > 0:
		inv[id] = count(inv, id) + added
	return added


## Removes `n` of an item if there are that many; false (and nothing removed) otherwise.
static func remove(inv: Dictionary, id: String, n: int) -> bool:
	if count(inv, id) < n:
		return false
	inv[id] = count(inv, id) - n
	if inv[id] == 0:
		inv.erase(id)
	return true
