class_name TrophyLedger
extends RefCounted
## The stored part of a player's Game Pucks: the single pucks earned (one-game,
## moment and roster pucks), each with the unix second it was earned (0 when
## unknown, as for a puck imported from an older Steam unlock). Ladder tiers and
## combos are derived from the Steam totals and the stored pucks, never stored
## here.
##
## A ledger only grows: merging two copies keeps every puck either holds, so a
## Steam Cloud copy from another machine can never take one away. An id this
## build does not know is kept, not dropped, so a newer build's puck survives a
## round trip through an older one.

var _pucks: Dictionary = {}  # String id -> int unix seconds (0 = unknown)


func has(id: String) -> bool:
	return _pucks.has(id)


func earned_at(id: String) -> int:
	return int(_pucks.get(id, 0))


func ids() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in _pucks:
		out.append(String(id))
	return out


func size() -> int:
	return _pucks.size()


# Records `id` as earned at `at`. Returns true only when it is new.
func earn(id: String, at: int) -> bool:
	if id.is_empty() or _pucks.has(id):
		return false
	_pucks[id] = maxi(at, 0)
	return true


# Union with `other`, keeping the earliest known date for a puck both hold.
# Returns true when this ledger changed.
func merge(other: TrophyLedger) -> bool:
	if other == null:
		return false
	var changed: bool = false
	for id: Variant in other._pucks:
		var theirs: int = int(other._pucks[id])
		if not _pucks.has(id):
			_pucks[id] = theirs
			changed = true
			continue
		var mine: int = int(_pucks[id])
		if theirs > 0 and (mine == 0 or theirs < mine):
			_pucks[id] = theirs
			changed = true
	return changed


func to_dict() -> Dictionary:
	return _pucks.duplicate()


# Reads whatever a prefs file held, skipping anything malformed rather than
# failing the load.
static func from_variant(value: Variant) -> TrophyLedger:
	var ledger := TrophyLedger.new()
	if not value is Dictionary:
		return ledger
	var raw: Dictionary = value
	for id: Variant in raw:
		if not id is String or String(id).is_empty():
			continue
		var at: Variant = raw[id]
		if at is int or at is float:
			ledger._pucks[String(id)] = maxi(int(at), 0)
	return ledger
