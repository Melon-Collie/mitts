class_name Titles
## The titles a player can wear (docs/game-pucks-plan.md). Pure data: each row
## names the Game Puck requirement that unlocks it (GamePucks), and TITLE_<ID>
## in the locale catalogue names it. An id travels the wire with a player's
## look; "" is no title.

const ALL: Array[Dictionary] = [
	{"id": "power_forward", "puck": "power_forward"},
	{"id": "shutdown", "puck": "shutdown"},
	{"id": "two_way", "puck": "two_way"},
	{"id": "iron_man", "puck": "iron_man"},
	{"id": "playmaker", "puck": "playmaker"},
	{"id": "sniper", "puck": "sniper"},
	{"id": "enforcer", "puck": "enforcer"},
]


static func is_known(id: String) -> bool:
	return not find(id).is_empty()


static func find(id: String) -> Dictionary:
	for row: Dictionary in ALL:
		if String(row["id"]) == id:
			return row
	return {}


# A wire or prefs value as a title this build knows; anything else wears none.
static func coerce(id: String) -> String:
	return id if is_known(id) else ""


static func name_key(id: String) -> StringName:
	return StringName("TITLE_" + id.to_upper())


# The titles a requirement unlocks, in catalogue order.
static func unlocked_by(req: String) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in ALL:
		if String(row["puck"]) == req:
			out.append(String(row["id"]))
	return out
