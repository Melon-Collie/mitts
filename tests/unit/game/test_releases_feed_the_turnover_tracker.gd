extends GutTest

# A pass is a paced wrister, so every release from carry arms ShotOnGoalTracker's
# pending shot. What the release was for the TURNOVER stats is read afterwards,
# from its trajectory and its button (TurnoverRules.release_kind). Two things
# hold that here:
# the real trackers through the host's call sequence, and GameManager's source
# for the sequence itself, which needs a live match to reach.

const _GM: String = "res://Scripts/game/game_manager.gd"
const _FIRING_FUNCTIONS: Array[String] = [
	"_on_puck_release_requested", "_fire_remote_shot", "_host_release_one_timer"]

var shots: ShotOnGoalTracker
var turnovers: TurnoverTracker
var registry: PlayerRegistry
var passer: PlayerRecord
var picker: PlayerRecord


func before_each() -> void:
	registry = PlayerRegistry.new()
	shots = ShotOnGoalTracker.new()
	shots.setup(registry, GameStateMachine.new())
	turnovers = TurnoverTracker.new()
	turnovers.setup(registry)
	passer = _add_player(10, 0)
	picker = _add_player(20, 1)


func _add_player(peer_id: int, team_id: int) -> PlayerRecord:
	var team := Team.new()
	team.team_id = team_id
	var record := PlayerRecord.new(peer_id, 1, false, team)
	record.stats = PlayerStats.new()
	registry._players[peer_id] = record
	return record


# GameManager's sequence for one release from carry, the puck 20 m/s up the ice
# from the origin with a teammate at `mate`.
func _release(peer_id: int, directed_at_net: bool, mate: Vector2,
		shot_button: bool = true) -> void:
	shots.on_pickup(peer_id)
	turnovers.on_carrier_gained(peer_id, false)
	turnovers.on_possession_established(peer_id)
	shots.on_shot_started(peer_id)
	shots.note_release_intent(shot_button)
	shots.note_directed_at_net(directed_at_net)
	var mates: Array[Vector2] = [mate]
	match TurnoverRules.release_kind(shots.pending_is_shot_attempt(),
			Vector2.ZERO, Vector2(0.0, 20.0), mates):
		TurnoverRules.Release.SHOT:
			turnovers.note_shot(peer_id)
		TurnoverRules.Release.DUMP:
			turnovers.note_dump(peer_id)
		TurnoverRules.Release.PASS:
			turnovers.note_pass(peer_id)


func _pick_off(peer_id: int) -> void:
	shots.on_pickup(peer_id)
	turnovers.on_carrier_gained(peer_id, false)
	turnovers.on_possession_established(peer_id)


func test_a_pass_picked_off_is_an_interception_though_it_armed_a_shot() -> void:
	_release(10, false, Vector2(0.5, 10.0))
	assert_true(shots.has_pending_shot(), "the pass armed the pending shot")
	_pick_off(20)
	assert_eq(picker.stats.interceptions, 1)
	assert_eq(passer.stats.giveaways, 1)


func test_a_dump_recovered_is_a_concession() -> void:
	_release(10, false, Vector2(8.0, 10.0))
	_pick_off(20)
	assert_eq(picker.stats.interceptions, 0)
	assert_eq(passer.stats.giveaways, 0)


func test_a_pass_button_feed_through_the_mouth_picked_off_is_an_interception() -> void:
	_release(10, true, Vector2(0.5, 10.0), false)
	_pick_off(20)
	assert_eq(picker.stats.interceptions, 1)
	assert_eq(picker.stats.shots_blocked, 0, "a pass is not a blocked shot")
	assert_eq(passer.stats.giveaways, 1)


func test_a_shot_picked_off_is_a_block_and_no_interception() -> void:
	_release(10, true, Vector2(0.5, 10.0))
	_pick_off(20)
	assert_eq(picker.stats.shots_blocked, 1)
	assert_eq(picker.stats.interceptions, 0)
	assert_eq(passer.stats.giveaways, 0)


func test_a_release_reads_as_a_shot_until_it_is_read_otherwise() -> void:
	shots.on_pickup(10)
	shots.on_shot_started(10)
	assert_true(shots.pending_is_shot_attempt())
	shots.note_directed_at_net(false)
	assert_false(shots.pending_is_shot_attempt())
	shots.on_shot_started(10)
	shots.note_release_intent(false)
	assert_false(shots.pending_is_shot_attempt())


# ── GameManager's sequence ───────────────────────────────────────────────────

func _functions() -> Dictionary:
	var out: Dictionary = {}
	var src: String = FileAccess.get_file_as_string(_GM)
	for chunk: String in src.split("\nfunc ").slice(1):
		var code: PackedStringArray = PackedStringArray()
		for line: String in chunk.split("\n"):
			if not line.strip_edges().begins_with("#"):
				code.append(line)
		out[chunk.substr(0, chunk.find("("))] = "\n".join(code)
	return out


func test_only_the_known_functions_fire_the_puck() -> void:
	var firing: Array[String] = []
	var functions: Dictionary = _functions()
	for fn: String in functions:
		if (functions[fn] as String).contains("puck.release("):
			firing.append(fn)
	firing.sort()
	var expected: Array[String] = _FIRING_FUNCTIONS.duplicate()
	expected.sort()
	assert_eq(firing, expected,
			"a new path that fires the puck must tell the turnover tracker what it fired")


func test_a_fired_puck_is_classified_after_its_trajectory_is_read() -> void:
	var functions: Dictionary = _functions()
	for fn: String in _FIRING_FUNCTIONS:
		var body: String = functions[fn]
		var fired: int = body.find("puck.release(")
		var read: int = body.find("_note_shot_trajectory()", fired)
		assert_gt(read, fired, "%s reads the trajectory after the release" % fn)
		assert_gt(body.find("_note_release_for_turnovers(", read), read,
				"%s classifies the release after the read" % fn)


func test_the_release_signal_classifies_nothing() -> void:
	# A strip, a nudge and a whistle drop raise it too, and none is a pass.
	var body: String = _functions()["_on_server_puck_released_by_carrier"]
	assert_false(body.contains("_turnover_tracker"))
	assert_false(body.contains("_note_release_for_turnovers"))


func test_a_puck_knocked_off_the_stick_opens_no_window() -> void:
	# The post and the boards fire the puck through the same path a pass takes.
	var body: String = _functions()["_note_release_for_turnovers"]
	var forced: int = body.find("last_release_was_forced")
	assert_gt(forced, -1)
	assert_lt(forced, body.find("TurnoverRules.release_kind("),
			"refused before the release is read as a pass")


func test_only_a_counted_shot_on_goal_opens_the_shot_window_by_signal() -> void:
	var src: String = FileAccess.get_file_as_string(_GM)
	assert_eq(src.count("connect(_turnover_tracker.note_shot)"), 1)
	assert_true(src.contains(
			"_shot_tracker.shot_on_goal_recorded.connect(_turnover_tracker.note_shot)"))
