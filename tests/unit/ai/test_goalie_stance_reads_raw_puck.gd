extends GutTest

# ── THE STANCE GATES AGAINST A STILL CARRIER ─────────────────────────────────
# `_update_tracking` low-passes the puck's offset from its carrier, and
# `_tracked_threat_position` is what `_update_depth` and the arc target consume
# (see "Filter the puck, not the man"). Several stance gates read
# `puck.global_position` directly instead — `_is_ready_situation`,
# `_is_puck_in_defensive_zone`, `_should_play_rim` and `_build_save_situation`'s
# own puck read — each with a real play on it: the READY zone edge, the RVH/VH
# angle, the block decision.
#
# These hold the contract both kinds of read share: a carrier standing perfectly
# still, puck on his blade, never moves the stance at those gates.

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const SkaterScene := preload("res://Scenes/Skater.tscn")
const DANGLE_M: float = 0.35      # a stickhandle, not a deke
const DANGLE_HZ: float = 2.0

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = SkaterScene.instantiate() as Skater
	_ctrl = GoalieController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_ctrl.set_skater_getter(func() -> Array: return [_shooter])
	_ctrl.setup(_goalie, _puck, GOAL_Z, true)


# Park a carrier at (lane, dist) and stickhandle for `secs`, counting stance
# changes. `amplitude` 0 is the control: the same standing carrier, no dangle.
func _dangle(lane: float, dist: float, amplitude: float, secs: float) -> Dictionary:
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	_shooter.predicted_shot_velocity = Vector3.ZERO
	_shooter.global_position = Vector3(lane, 0.0, GOAL_Z + dist)
	_shooter.velocity = Vector3.ZERO
	_puck.global_position = _shooter.global_position
	_puck.set_carrier(_shooter)
	_ctrl.reset_to_crease()
	for _i: int in 240:                      # settle with the puck still
		_puck.global_position = _shooter.global_position
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(DT)
	var flips: int = 0
	var prev: int = _ctrl.stance()
	var raw_lo: float = INF
	var raw_hi: float = -INF
	var trk_lo: float = INF
	var trk_hi: float = -INF
	var t: float = 0.0
	for _i: int in int(secs / DT):
		var off: float = amplitude * sin(TAU * DANGLE_HZ * t)
		_puck.global_position = _shooter.global_position + Vector3(off, 0.0, 0.0)
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(DT)
		t += DT
		raw_lo = minf(raw_lo, _puck.global_position.x)
		raw_hi = maxf(raw_hi, _puck.global_position.x)
		trk_lo = minf(trk_lo, _ctrl._tracked_threat_position.x)
		trk_hi = maxf(trk_hi, _ctrl._tracked_threat_position.x)
		var s: int = _ctrl.stance()
		if s != prev:
			flips += 1
		prev = s
	return {"flips": flips, "raw_span": raw_hi - raw_lo,
			"tracked_span": trk_hi - trk_lo, "final": _ctrl.stance()}


# ── HOW MUCH THE FILTER ACTUALLY REMOVES ─────────────────────────────────────
# The positional half filters a stickhandle: the tracked threat swings less than
# the raw puck the gates read.
func test_the_filter_removes_most_of_the_dangle() -> void:
	for dist: float in [2.0, 5.0, 9.0]:
		var r: Dictionary = _dangle(0.0, dist, DANGLE_M, 3.0)
		var kept: float = 100.0 * (r["tracked_span"] as float) \
				/ maxf(r["raw_span"] as float, 0.0001)
		gut.p("carrier %.0f m | raw puck swings %.3f m, tracked threat swings %.3f m (%.0f%% kept)"
				% [dist, r["raw_span"], r["tracked_span"], kept])
		assert_lt(r["tracked_span"] as float, r["raw_span"] as float,
				"the filter is doing something at %.0f m" % dist)


# ── IN TIGHT ─────────────────────────────────────────────────────────────────
func test_a_still_carrier_in_tight_never_moves_the_stance() -> void:
	var edge: float = 2.4
	for lane: float in [0.0, 1.5]:
		var dist: float = sqrt(maxf(edge * edge - lane * lane, 0.04))
		assert_eq(_dangle(lane, dist, 0.0, 3.0)["flips"], 0,
				"lane %.1f, %.2f m out: a carrier standing still does not move his stance"
				% [lane, dist])


# ── THE POST-STANCE GATE ─────────────────────────────────────────────────────
# `is_puck_in_defensive_zone` is an ANGLE test on the raw puck, so its threshold
# is sharpest close to the goal line, where a walkout lives.
func test_a_still_carrier_at_the_post_stance_angle_never_moves_the_stance() -> void:
	for z: float in [0.30, 0.50, 0.80]:
		var edge_x: float = z * tan(deg_to_rad(_ctrl.rvh_early_angle))
		assert_eq(_dangle(edge_x, z, 0.0, 3.0)["flips"], 0,
				"%.2f m off the line, on the %.0f deg gate: a carrier standing still does not move his stance"
				% [z, _ctrl.rvh_early_angle])
