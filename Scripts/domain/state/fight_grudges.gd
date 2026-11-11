class_name FightGrudges
extends RefCounted

# Every bot's grudge against every opponent, by peer id (FightGrudgeRules). A
# level is stored with the host time it was last raised and decays on read, so
# nothing ticks it. Host-only, never on the wire.

class Entry:
	var level: float = 0.0
	var at: float = 0.0


var _by_holder: Dictionary = {}   # holder pid -> Dictionary[target pid -> Entry]


func level(holder: int, target: int, now: float) -> float:
	var row: Dictionary = _by_holder.get(holder, {})
	var e: Entry = row.get(target, null)
	return FightGrudgeRules.decayed(e.level, now - e.at) if e != null else 0.0


func raise(holder: int, target: int, gain: float, now: float) -> void:
	if not _by_holder.has(holder):
		_by_holder[holder] = {}
	var row: Dictionary = _by_holder[holder]
	var e: Entry = row.get(target, null)
	if e == null:
		e = Entry.new()
		row[target] = e
	e.level = FightGrudgeRules.raised(FightGrudgeRules.decayed(e.level, now - e.at), gain)
	e.at = now


# The holder's highest grudge against anyone.
func peak(holder: int, now: float) -> float:
	var row: Dictionary = _by_holder.get(holder, {})
	var best: float = 0.0
	for target: int in row:
		var e: Entry = row[target]
		best = maxf(best, FightGrudgeRules.decayed(e.level, now - e.at))
	return best


# They fought: the holder's grudge against him is spent.
func settle(holder: int, target: int) -> void:
	var row: Dictionary = _by_holder.get(holder, {})
	row.erase(target)


func clear() -> void:
	_by_holder.clear()
