extends GutTest

# What a penalty shot is worth: a real bot from centre ice against the real
# keeper, on bot_vs_goalie_harness (read its header for what is real and what
# is reconstructed before quoting a number from here).
#
# A penalty shot is one staging, so a tier pairing has one answer on the
# harness. The spread comes from the things that differ between two shots in a
# match: how far off the puck's line the shooter collects it and how much pace
# he has by then. Each pairing is run over that small grid.
#
# The shooter starts as the carrier at the spot the puck is laid, so the
# collect itself is not here; tests/slow/ai/test_bot_penalty_shot.gd holds
# that he makes it. There are no rebounds, as in the match's rule.
#
# Reported, not pinned: it is the number to read when deciding what a foul in
# 3v3 should cost, against what a power play is worth in 5v5.

const BotGoalie := preload("res://tests/unit/ai/bot_vs_goalie_harness.gd")
const TEAM: int = 0
const COLLECT_OFFSETS_M: Array[float] = [-0.6, -0.3, 0.0, 0.3, 0.6]
const COLLECT_SPEEDS: Array[float] = [0.0, 1.5, 3.0]
# Centre ice to the net at a carry's pace, with room to spare.
const WINDOW_S: float = 12.0

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _bg: RefCounted = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_bg = BotGoalie.new()
	_bg.setup(_goalie, _puck, _ctrl, _shooter)


func _shots(shooter: BotSkillProfile) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spot: Vector2 = PlayerRules.penalty_shot_puck_spot(TEAM)
	var toward_net := Vector3(0.0, 0.0, -PlayerRules.own_goal_dir(TEAM))
	for offset: float in COLLECT_OFFSETS_M:
		for speed: float in COLLECT_SPEEDS:
			_ctrl.reset_to_crease()
			out.append(_bg.run_rush(Vector3(spot.x + offset, 0.0, spot.y),
					toward_net * speed, shooter, WINDOW_S, false))
	return out


# {shots, goals, never_fired, mean release distance}
func _tally(rows: Array[Dictionary]) -> Dictionary:
	var shots: int = 0
	var goals: int = 0
	var never_fired: int = 0
	var range_sum: float = 0.0
	for r: Dictionary in rows:
		if r["outcome"] == BotGoalie.NO_SHOT:
			never_fired += 1
			continue
		shots += 1
		range_sum += float(BotGoalie.zone_of(r["release"])["dist"])
		if r["outcome"] == BotGoalie.GOAL:
			goals += 1
	return {"shots": shots, "goals": goals, "never_fired": never_fired,
			"range": range_sum / float(maxi(shots, 1))}


func test_report_penalty_shot_conversion_by_tier() -> void:
	gut.p("shooter x keeper: goals / shots (rate), mean release range, shots never taken")
	var all_shots: int = 0
	var all_goals: int = 0
	for shooter_tier: int in BotSkillProfile.Difficulty.values():
		for keeper_tier: int in GoalieSkillProfile.Difficulty.values():
			_ctrl.apply_skill_profile(GoalieSkillProfile.for_difficulty(keeper_tier))
			var t: Dictionary = _tally(_shots(BotSkillProfile.for_difficulty(shooter_tier)))
			all_shots += int(t["shots"])
			all_goals += int(t["goals"])
			gut.p("  %-6s x %-6s  %2d / %2d  (%5.1f%%)   %4.1f m   %d" % [
					BotSkillProfile.Difficulty.keys()[shooter_tier],
					GoalieSkillProfile.Difficulty.keys()[keeper_tier],
					t["goals"], t["shots"],
					100.0 * float(t["goals"]) / float(maxi(int(t["shots"]), 1)),
					t["range"], t["never_fired"]])
	gut.p("  all pairings: %d / %d  (%.1f%%)" % [all_goals, all_shots,
			100.0 * float(all_goals) / float(maxi(all_shots, 1))])
	# The teeth: an instrument whose shooter has stopped shooting, or whose
	# keeper has stopped touching the puck, reports a number that means nothing.
	assert_gt(all_shots, 0, "the bots still take the shot")
	assert_lt(all_goals, all_shots, "and the keeper still stops some")
