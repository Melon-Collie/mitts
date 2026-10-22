extends GutTest

# The bots score their shots against a MODEL of the goalie, not the goalie. When
# the two disagree the bots aim at a net that isn't there — and nothing fails,
# because both halves are individually consistent. Every shot decision in the
# game is quietly wrong and the only symptom is that the bots look bad.
#
# Two contracts hold them together, and both were prose:
#
#   1. The AUTHORED defaults must agree. AIGoalieModel's static vars start at
#      the same values GoalieController's @exports do, so a fresh scene with no
#      profile applied has the bots modelling the goalie they face.
#   2. set_goalie_profile must carry EVERY tiered knob the model reads. A knob
#      added to GoalieSkillProfile and wired into the controller but not into
#      the sync leaves the bots scoring against the Hard goalie while an Easy
#      one is in the net.
#
# The area docs now state this (Scripts/domain/ai/CLAUDE.md, "the skater AI's
# goalie model is a MIRROR, not a second tier"); this is what makes it hold.

const _GAME_RULES: String = "res://Scripts/domain/config/game_rules.gd"

var _goalie_src: String = ""


func before_all() -> void:
	_goalie_src = FileAccess.get_file_as_string("res://Scripts/controllers/goalie_controller.gd")


# `var name: T = <literal>` at column 0 -> the literal, as a float. Accepts an
# `@export` prefix too: the goalie's tunables are plain fields now (a scene
# overrode none of them), but the parser should not care which a knob is.
func _export_default(export_name: String) -> float:
	var re := RegEx.create_from_string(
			"(?m)^(?:@export(?:_[a-z_]+)?(?:\\([^)]*\\))? )?var %s\\s*:\\s*float\\s*=\\s*([^\\n#]+)" % export_name)
	var m: RegExMatch = re.search(_goalie_src)
	assert_not_null(m, "no float field named `%s` in goalie_controller.gd" % export_name)
	if m == null:
		return NAN
	var expr: String = m.get_string(1).strip_edges()
	# The defaults that matter are either a literal or a GameRules constant.
	# Resolved through the script's own constant map — `GameRules.get(name)` is a
	# non-static call and GameRules is never instanced.
	if expr.begins_with("GameRules."):
		var consts: Dictionary = (load(_GAME_RULES) as GDScript).get_script_constant_map()
		var key: String = expr.substr("GameRules.".length())
		assert_true(consts.has(key), "GameRules has no constant `%s`" % key)
		return float(consts.get(key, NAN))
	return float(expr)


func test_authored_defaults_agree_before_any_profile_is_applied() -> void:
	# GoalieSkillProfile.hard() is the controller's authored default by
	# construction, so applying it must not move the model.
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.hard())
	assert_almost_eq(AIGoalieModel.goalie_leg_delay_s, _export_default("reaction_delay"), 1e-6,
			"the bots' leg-reaction delay must be the goalie's own")
	assert_almost_eq(AIGoalieModel.goalie_lateral_accel_m_s2,
			_export_default("lateral_accel"), 1e-6,
			"the bots' lateral accel must be the goalie's own — it decides whether a " +
			"cross-crease look is reachable")
	assert_almost_eq(AIGoalieModel._planning_ceiling, _export_default("depth_aggressive"), 1e-6,
			"the bots' challenge-depth ceiling must be the goalie's own")


# A lower tier has to actually move the model, or the ladder is decoration.
func test_an_easier_tier_moves_every_axis_the_bots_read() -> void:
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.hard())
	var hard := {
		"leg": AIGoalieModel.goalie_leg_delay_s,
		"accel": AIGoalieModel.goalie_lateral_accel_m_s2,
		"depth": AIGoalieModel._planning_ceiling,
	}
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.easy())
	assert_gt(AIGoalieModel.goalie_leg_delay_s, hard.leg, "Easy reads later with the legs")
	assert_lt(AIGoalieModel.goalie_lateral_accel_m_s2, hard.accel, "and pushes across slower")
	assert_lt(AIGoalieModel._planning_ceiling, hard.depth, "and sits deeper in his net")
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.hard())


# The one that catches the real mistake: a knob added to the profile and wired
# into the controller, but never into the sync. Every profile field that names a
# quantity the bots' goalie prediction reads must appear in set_goalie_profile's
# body.
func test_every_mirrored_profile_field_is_carried_by_the_sync() -> void:
	var src: String = FileAccess.get_file_as_string(
			"res://Scripts/domain/ai/goalie_model.gd")
	var head: int = src.find("static func set_goalie_profile(")
	assert_gt(head, 0, "set_goalie_profile must exist — it is the whole seam")
	var body: String = src.substr(head, src.find("\n\n\n", head) - head)
	for field: String in ["reaction_delay_s", "lateral_accel_mps2", "depth_aggressive_m",
			"depth_base_m", "puck_play_go_margin_s"]:
		assert_true(body.contains("profile.%s" % field),
				"set_goalie_profile does not read `profile.%s`, which the goalie prediction " % field +
				"depends on — the bots would go on scoring against the Hard goalie " +
				"while facing a lower tier")


# Guards the guard: the export parser is the only moving part above, and if it
# stopped matching every assertion would compare NAN against NAN.
func test_the_bots_know_how_long_the_goalie_takes_to_stand_up() -> void:
	assert_almost_eq(AIGoalieModel.GOALIE_RECOVERY_S, _export_default("recovery_duration"),
			1e-6, "the window the carrier prices a down goalie's stance over is his rise")


# A predicted seal the live keeper does not adopt prices a sharp-angle look against
# a post he is not on, or the other way round.
func test_the_bots_seal_the_post_where_the_goalie_does() -> void:
	assert_almost_eq(AIGoalieModel.GOALIE_SEAL_ZONE_POST_Z_M, _export_default("zone_post_z"),
			1e-6, "the seal zone's depth must be the goalie's own")
	assert_almost_eq(rad_to_deg(AIGoalieModel.GOALIE_SEAL_ANGLE_RAD),
			_export_default("rvh_early_angle"), 1e-4, "the seal angle must be the goalie's own")


# The planner predicts the keeper's depth through the live GoalieDepthSolver and
# rush backflow, so only the constants it feeds them can drift.
func test_the_bots_predict_depth_from_the_goalies_own_chart() -> void:
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.hard())
	assert_almost_eq(AIGoalieModel.GOALIE_RESTING_DEPTH_M, _export_default("depth_conservative"),
			1e-6, "resting depth before the play enters the zone")
	assert_almost_eq(AIGoalieModel.GOALIE_CHALLENGE_STANDOFF_M,
			_export_default("challenge_standoff"), 1e-6, "the gap he keeps while challenging")
	assert_almost_eq(AIGoalieModel.GOALIE_DEPTH_MAX_SPEED_M_S, _export_default("depth_max_speed"),
			1e-6, "his skating speed in and out of the crease")
	assert_almost_eq(AIGoalieModel._depth_cfg_planning.floor_radius,
			_export_default("depth_defensive"), 1e-6, "the deepest he plays")


func test_the_bots_back_him_in_on_the_goalies_own_rush_read() -> void:
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.hard())
	var rush: GoalieBehaviorRules.RushRetreatConfig = AIGoalieModel._rush_cfg_planning
	assert_almost_eq(AIGoalieModel.GOALIE_RUSH_MIN_CLOSING_M_S,
			_export_default("rush_min_closing_speed"), 1e-6,
			"a carrier slower than this does not back him in")
	assert_almost_eq(rush.engage_distance, _export_default("rush_engage_distance"), 1e-6)
	assert_almost_eq(rush.mid_distance, _export_default("rush_mid_distance"), 1e-6)
	assert_almost_eq(rush.arrive_distance, _export_default("rush_arrive_distance"), 1e-6)
	assert_almost_eq(rush.depth_arrive, _export_default("rush_arrive_depth"), 1e-6)
	assert_almost_eq(rush.depth_engage, _export_default("depth_aggressive"), 1e-6)
	assert_almost_eq(rush.depth_mid, _export_default("depth_base"), 1e-6)


func test_the_export_parser_still_reads_the_controller() -> void:
	assert_gt(_export_default("reaction_delay"), 0.0, "parsed a real reaction delay")
	assert_gt(_export_default("glove_react_max_speed"), 0.0, "parsed a real glove speed")
	assert_gt(_export_default("depth_aggressive"), 0.0, "parsed a real challenge depth")
