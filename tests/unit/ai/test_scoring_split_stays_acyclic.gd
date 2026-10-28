extends GutTest

# The bot evaluators are split by dependency, not by topic, and the split is
# only safe while it stays acyclic: a const read across a GDScript `class_name`
# cycle can fail at PARSE time, which takes the whole class down — every static
# call on it, from every file, at once — with nothing pointing at the cause.
#
# The shape held here: the shared primitives (the arrival clock, the net and
# slot segment tests, the puck lane, a defender's one chance at a path, the feed's
# reception, the body's execution constants, the planning keeper, the measured
# shot odds) are LEAVES that read no evaluator, the two big
# evaluators that read them — AIActionScoring and AICarrySpace — never read
# each other, and the possession read (AIPossessionValue) reads both from above.

const _SCORING: String = "res://Scripts/domain/ai/action_scoring.gd"
const _CARRY: String = "res://Scripts/domain/ai/carry_space.gd"
const _LEAVES: PackedStringArray = [
	"res://Scripts/domain/ai/arrival.gd",
	"res://Scripts/domain/ai/net_obstacle.gd",
	"res://Scripts/domain/ai/puck_lane.gd",
	"res://Scripts/domain/ai/lane_reach.gd",
	"res://Scripts/domain/ai/strip_odds.gd",
	"res://Scripts/domain/ai/feed_reception.gd",
	"res://Scripts/domain/ai/bot_mechanics.gd",
	"res://Scripts/domain/ai/goalie_model.gd",
	"res://Scripts/domain/ai/shot_odds.gd",
]
const _EVALUATORS: PackedStringArray = ["AIActionScoring", "AICarrySpace"]


# Every non-comment line of `path` that names `symbol`.
func _code_refs(path: String, symbol: String) -> PackedStringArray:
	var src: String = FileAccess.get_file_as_string(path)
	assert_false(src.is_empty(), "could not read %s" % path)
	var out := PackedStringArray()
	for line: String in src.split("\n"):
		var code: String = line.split("#")[0]
		if code.contains(symbol):
			out.append(code.strip_edges())
	return out


func test_the_leaves_read_no_evaluator() -> void:
	for leaf: String in _LEAVES:
		for evaluator: String in _EVALUATORS:
			var refs: PackedStringArray = _code_refs(leaf, evaluator)
			assert_eq(refs.size(), 0,
					"%s references %s: %s. The leaves are what both evaluators " % [
							leaf, evaluator, refs] +
					"share; a leaf that reads one of them closes a cycle.")


# The possession read sits above both evaluators: it reads them, so nothing it
# reads may read it back.
func test_nothing_the_possession_read_reads_reads_it() -> void:
	for path: String in [_SCORING, _CARRY] + Array(_LEAVES):
		assert_eq(_code_refs(path, "AIPossessionValue").size(), 0,
				"%s references AIPossessionValue, which reads it" % path)


func test_the_scorer_and_carry_space_never_read_each_other() -> void:
	assert_eq(_code_refs(_SCORING, "AICarrySpace").size(), 0,
			"action_scoring.gd references AICarrySpace — move what both need into a leaf")
	assert_eq(_code_refs(_CARRY, "AIActionScoring").size(), 0,
			"carry_space.gd references AIActionScoring — move what both need into a leaf")


# The primitives everything shares live in the leaves. One drifting back into an
# evaluator is the failure this file exists for, and it is silent until a class
# stops parsing.
func test_the_shared_primitives_live_in_the_leaves() -> void:
	var placement: Dictionary = {
		"res://Scripts/domain/ai/arrival.gd": ["time_to_arrive"],
		"res://Scripts/domain/ai/net_obstacle.gd": ["carry_path_blocked_by_net",
				"pass_lane_blocked_by_net", "pass_crosses_own_slot"],
		"res://Scripts/domain/ai/puck_lane.gd": ["lane_clear", "lane_clear_saucer",
				"pass_launch_speed", "release_contest_clean"],
		"res://Scripts/domain/ai/goalie_model.gd": ["set_goalie_profile",
				"predict_goalie_pos", "planned_goalie_depth", "goalie_lateral_reach"],
	}
	for path: String in placement:
		var src: String = FileAccess.get_file_as_string(path)
		for shared: String in placement[path]:
			assert_true(src.contains("static func %s(" % shared),
					"`%s` should live in %s" % [shared, path])
