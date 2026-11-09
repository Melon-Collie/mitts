extends GutTest

# A client that joins mid-game never sees the carrier event that put the puck on
# a stick (the snapshot block keeps a second of them; the reliable RPC fired
# before it connected), and the carrier view is never read off world state. The
# join roster's carrier flag is how it learns.

const GAME_MANAGER: GDScript = preload("res://Scripts/game/game_manager.gd")


func _entry(peer_id: int, carries: Variant) -> Array:
	var e: Array = []
	e.resize(GAME_MANAGER.ROSTER_CARRIES_PUCK)
	e[0] = peer_id
	if carries != null:
		e.append(carries)
	return e


func test_the_flagged_entry_names_the_carrier() -> void:
	var roster: Array = [_entry(2, false), _entry(7, true), _entry(9, false)]
	assert_eq(GAME_MANAGER.roster_carrier_peer_id(roster), 7)


func test_no_flag_is_no_carrier() -> void:
	var roster: Array = [_entry(2, false), _entry(7, false)]
	assert_eq(GAME_MANAGER.roster_carrier_peer_id(roster), -1)


func test_an_entry_without_the_field_is_no_carrier() -> void:
	assert_eq(GAME_MANAGER.roster_carrier_peer_id([_entry(2, null)]), -1)


func test_the_collector_writes_the_flag_at_its_index() -> void:
	# The flag is the last field _collect_existing_player_data appends; reading it
	# at any other index reads a cosmetic code as a carrier.
	var src: String = FileAccess.get_file_as_string("res://Scripts/game/game_manager.gd")
	var start: int = src.find("func _collect_existing_player_data(")
	var body: String = src.substr(start, src.find("\nfunc ", start + 1) - start)
	var open_at: int = body.find("existing.append([")
	var close_at: int = body.find("])", open_at)
	var fields: PackedStringArray = body.substr(open_at, close_at - open_at).split(",")
	assert_eq(fields.size() - 1, GAME_MANAGER.ROSTER_CARRIES_PUCK,
			"the carrier flag must be the roster entry's field %d" % GAME_MANAGER.ROSTER_CARRIES_PUCK)
	assert_true(fields[fields.size() - 1].contains("carrier"))
