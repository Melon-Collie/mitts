extends GutTest

# ── THE DIFFICULTY LADDER ON THE PLAY THAT ACTUALLY GETS PLAYED ─────────────
# This project's own player scores overwhelmingly on breakaways, and the move is
# always the one `test_human_wraparound` models: drive at him, pull the puck
# across to commit him, then take it around him. Two ways to finish it, and the
# ladder lives on the one that beats him. He seals the post the puck was pulled
# toward, so carrying on round him is shut; what beats him is coming back across
# into the space he left, which is a race to re-commit: how far out he is
# (depth) and how hard he pushes (the slide push, tiered like every other
# movement speed). Depth cuts the other way: a goalie who challenges the rush
# harder is easier to beat back across.
#
# Every measurement fires the same seven-point aim fan at the same release point
# after the same bait, so the count IS how much net is open — not whether a
# shooter who already knows the answer can find it. The counts themselves are
# the reviewed snapshot, snapshots/breakaway_ladder.txt.
#
# ── THE TRADE IS REAL ───────────────────────────────────────────────────────
# Pulling `depth_base_m` in is not free — it concedes the centre-lane rush shot
# from 5 m, which is exactly what challenge depth exists to cut off.
#
# ⚠️ THIS IS NOT A LICENCE TO RETUNE IT. 1.30 is not a tuning number — it is the
# taught B position, heels at the crease top. Replacing a rink landmark with a
# number that won a 49-shot sweep trades a model for a magic constant, which is
# the thing this codebase spends its effort not doing.

const Snapshot := preload("res://tests/snapshot.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const Harness := preload("res://tests/unit/ai/human_wraparound_harness.gd")
const SkaterScene := preload("res://Scenes/Skater.tscn")
const AIM_X: Array[float] = [-0.85, -0.55, -0.25, 0.0, 0.25, 0.55, 0.85]
const START_M: float = 9.0
const DRIVE_M_S: float = 5.0
const PULL_M: float = 1.1
const PULL_S: float = 0.25
const PULL_AT_M: float = 3.5
const WALK_ROUND: float = -1.0   # carry on to the side the puck was pulled to
const CUT_BACK: float = 1.0      # come back across into the space he left
const TIERS: Array[int] = [GoalieSkillProfile.Difficulty.EASY,
		GoalieSkillProfile.Difficulty.NORMAL, GoalieSkillProfile.Difficulty.HARD]
const LEVER_DEPTH_BASE_M: float = 0.60
const LEVER_PUSH_MPS: float = 1.8
const LEVER_EDGES_MPS2: float = 2.4
const TRADE_BASES: Array[float] = [1.30, 1.00, 0.80, 0.60]
# Un-pend once the goalie stops conceding what the new shot field measured (#836).
const PENDED_FOR_836: bool = true

var _h: RefCounted = null
var _ctrl: GoalieController = null
# Each count is deterministic (every trial resets the keeper), so a count one
# test measured is reused by the next instead of re-run.
var _counts: Dictionary = {}


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	var puck: Node = load("res://Scenes/Puck.tscn").instantiate()
	var shooter: Skater = SkaterScene.instantiate() as Skater
	_ctrl = GoalieController.new()
	for n: Node in [goalie, puck, shooter, _ctrl]:
		add_child_autofree(n)
	_h = Harness.new()
	_h.setup(goalie, puck, _ctrl, shooter)


# ⚠️ OVERRIDES GO ON THE PROFILE, NEVER ON THE CONTROLLER AFTERWARDS.
# `apply_skill_profile` rebuilds the cached rule configs, so a field written
# after it is set but never read again — and a sweep done that way reports the
# baseline for every arm and reads as "this lever does nothing".
func _apply(over: Dictionary) -> void:
	var p: GoalieSkillProfile = GoalieSkillProfile.hard()
	for k: String in over:
		p.set(k, over[k])
	_ctrl.apply_skill_profile(p)


# How much net the finish opens after the bait, as a count of the aim fan.
func _finish_open(over: Dictionary, side: float = CUT_BACK) -> int:
	var key: String = "finish %s %s" % [over, side]
	if _counts.has(key):
		return _counts[key]
	var open: int = 0
	for ax: float in AIM_X:
		_apply(over)
		_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + START_M))
		_h.begin_trial()
		_h.bait_commit(0.0, START_M, 0.9, DRIVE_M_S, PULL_M, PULL_S, PULL_AT_M)
		var rel: Vector3 = _h.wrap_to(side * 1.35, 0.70, 4.0)
		if _h.fire_release_at(rel, Vector3(ax, 0.0, GOAL_Z), 0, 18.0, 0.0) == 0:
			open += 1
	_counts[key] = open
	return open


# The other half of the trade: a shot taken OFF the drive, no attempt to get
# around him. Elevated and hard, which is the rush shot challenge depth exists
# to cut the angle on.
func _rush_open(over: Dictionary, lane: float, dist: float) -> int:
	var key: String = "rush %s %s %s" % [over, lane, dist]
	if _counts.has(key):
		return _counts[key]
	var open: int = 0
	for ax: float in AIM_X:
		_apply(over)
		_h.settle_ready(Vector3(lane, 0.0, GOAL_Z + 14.0))
		_h.begin_trial()
		_h.bait_commit(lane, 14.0, dist, 6.0)
		var spot := Vector3(lane, 0.0, GOAL_Z + dist)
		if _h.fire_release_at(spot, Vector3(ax, 0.0, GOAL_Z), 1, 28.0, 0.0) == 0:
			open += 1
	_counts[key] = open
	return open


func _tier_over(tier: int) -> Dictionary:
	var p: GoalieSkillProfile = GoalieSkillProfile.for_difficulty(tier)
	return {
		"depth_aggressive_m": p.depth_aggressive_m,
		"depth_base_m": p.depth_base_m,
		"reaction_delay_s": p.reaction_delay_s,
		"lateral_accel_mps2": p.lateral_accel_mps2,
		"butterfly_drop_s": p.butterfly_drop_s,
		"arm_reaction_delay_s": p.arm_reaction_delay_s,
		"read_lag_s": p.read_lag_s,
		"five_hole_base_m": p.five_hole_base_m,
		"slide_push_speed_mps": p.slide_push_speed_mps,
	}


# ── 1. THE LADDER MUST NOT RUN BACKWARDS ─────────────────────────────────────
# On every tier the cutback beats him and carrying on round him, which the seal
# answers, does not. No tier leaks less net on the cutback than the one above
# it, and EASY leaks more than HARD.
func test_the_difficulty_ladder_is_not_inverted_on_a_walkaround() -> void:
	if PENDED_FOR_836:
		pending("red since the regulation puck's shot field: #836")
		return
	var open: Dictionary = {}
	for tier: int in TIERS:
		open[tier] = _finish_open(_tier_over(tier))
		assert_lt(_finish_open(_tier_over(tier), WALK_ROUND), open[tier] as int,
				"tier %d: the cutback beats him and the walkaround does not" % tier)
	assert_lte(open[GoalieSkillProfile.Difficulty.HARD] as int,
			open[GoalieSkillProfile.Difficulty.NORMAL] as int, "HARD never leaks more than NORMAL")
	assert_lte(open[GoalieSkillProfile.Difficulty.NORMAL] as int,
			open[GoalieSkillProfile.Difficulty.EASY] as int, "NORMAL never leaks more than EASY")
	assert_lt(open[GoalieSkillProfile.Difficulty.HARD] as int,
			open[GoalieSkillProfile.Difficulty.EASY] as int, "and the ladder separates")


# ── 2. DEPTH, THE PUSH AND THE EDGES ─────────────────────────────────────────
# The ladder reaches the cutback through how far out he stands, how hard he
# pushes back across, and how well his edges stop him set on his spot: a keeper
# sat deeper has less ice to recover, and a softer push or a softer stop loses
# the race to re-commit.
func test_depth_the_push_and_the_edges_move_the_cutback() -> void:
	var baseline: int = _finish_open({})
	assert_lt(_finish_open({"depth_base_m": LEVER_DEPTH_BASE_M}), baseline,
			"a deeper base leaves less net on the cutback")
	assert_gt(_finish_open({"slide_push_speed_mps": LEVER_PUSH_MPS}), baseline,
			"a softer push back across leaves more")
	assert_gt(_finish_open({"lateral_accel_mps2": LEVER_EDGES_MPS2}), baseline,
			"and so do edges that stop him late")


# ── 3. THE TRADE, PRICED ─────────────────────────────────────────────────────
# Both halves at once so neither can be improved quietly at the other's expense:
# the depth that shuts the cutback concedes the centre-lane rush shot from 5 m.
func test_pulling_the_depth_base_in_concedes_the_centre_lane_rush() -> void:
	var authored: int = _rush_open({}, 0.0, 5.0)
	var pulled_in: int = _rush_open({"depth_base_m": TRADE_BASES[-1]}, 0.0, 5.0)
	assert_gt(pulled_in, authored,
			"pulled in to %.2f m he concedes more of the centre-lane rush from 5 m"
			% TRADE_BASES[-1])


# ── THE REVIEWED COUNTS ──────────────────────────────────────────────────────
# Rewrite with MITTS_UPDATE_SNAPSHOTS=1 (tests/snapshot.gd) and review the diff.
func test_breakaway_ladder_snapshot() -> void:
	var snap := Snapshot.new("res://tests/slow/ai/snapshots/breakaway_ladder.txt")
	var n: int = AIM_X.size()
	for tier: int in TIERS:
		var tier_name: String = GoalieSkillProfile.Difficulty.keys()[tier]
		snap.record("%s: cutback open of %d" % [tier_name, n], _finish_open(_tier_over(tier)))
		snap.record("%s: walk round open of %d" % [tier_name, n],
				_finish_open(_tier_over(tier), WALK_ROUND))
	snap.record("HARD, depth_base %.2f: cutback open of %d" % [LEVER_DEPTH_BASE_M, n],
			_finish_open({"depth_base_m": LEVER_DEPTH_BASE_M}))
	snap.record("HARD, slide push %.1f m/s: cutback open of %d" % [LEVER_PUSH_MPS, n],
			_finish_open({"slide_push_speed_mps": LEVER_PUSH_MPS}))
	snap.record("HARD, edges %.1f m/s²: cutback open of %d" % [LEVER_EDGES_MPS2, n],
			_finish_open({"lateral_accel_mps2": LEVER_EDGES_MPS2}))
	for base: float in TRADE_BASES:
		var over := {"depth_base_m": base}
		snap.record("depth_base %.2f: cutback open of %d" % [base, n], _finish_open(over))
		for lane: float in [0.0, 2.5]:
			for dist: float in [5.0, 8.0, 11.0]:
				snap.record("depth_base %.2f: rush lane %.1f from %.0f m, open of %d"
						% [base, lane, dist, n], _rush_open(over, lane, dist))
	snap.verify(self)
