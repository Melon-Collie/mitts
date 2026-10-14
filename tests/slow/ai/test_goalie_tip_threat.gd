extends GutTest

# ── A STICK AT THE NET FRONT ─────────────────────────────────────────────────
# A point shot aimed at a net-front blade and redirected there toward the net,
# scattered ±14°, flat and tipped up; the live goalie settled against the
# shooter. A tip beats the read, so the save is where he already stands
# (GoalieTipDepth): no further out than keeps his body on the tip's line.
#
# From the point the direct shot is a reaction save at any depth, so the angle A
# buys is worth nothing there while the redirect it sells is. A stick on the
# shooter's line is covered by challenging, and one at 5.5 m is a tip he can
# still react to — neither moves him.

const Snapshot := preload("res://tests/snapshot.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const RADIUS: float = GameRules.PUCK_COLLISION_RADIUS
const SHOT_SPEED: float = 30.0
const TIP_RETAIN: float = 0.85

const WIDE_POINT := Vector3(-5.0, 0.0, GOAL_Z + 16.0)
const CENTRE_POINT := Vector3(0.0, 0.0, GOAL_Z + 18.0)
const STICKS: Array[Vector2] = [
	Vector2(1.5, 4.0), Vector2(2.5, 3.0), Vector2(1.0, 5.5), Vector2(-1.5, 4.0),
]

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _tipper: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null
var _scratch := SweptDiscOBB.Result.new()
var _contact := GoalieContactDetector.Contact.new()
var _frame := PuckGeometryCollision.Result.new()
var _tick := PuckAuthorityRules.TickResult.new()


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	var skater_scene: PackedScene = load("res://Scenes/Skater.tscn")
	_shooter = skater_scene.instantiate() as Skater
	_tipper = skater_scene.instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_tipper)
	add_child_autofree(_ctrl)
	_tipper.set_physics_process(false)
	_tipper.set_process(false)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)
	_ctrl.set_skater_getter(func() -> Array: return [_shooter, _tipper])


# Fire at the tip point, redirect toward the net there (scattered by `psi`, with
# vertical launch `vy`), and march against the goalie. True on a goal.
func _tip_scores(shooter: Vector3, tip_pt: Vector3, psi: float, vy: float) -> bool:
	var vel: Vector3 = (tip_pt - shooter).normalized() * SHOT_SPEED
	var pos: Vector3 = shooter
	pos.y = _puck.ice_height
	_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	_puck.global_position = pos
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	var tipped: bool = false
	for _s: int in 300:
		var prev: Vector3 = pos
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)
		_tick.touched_post = false
		_tick.touched_net = false
		PuckAuthorityRules.step_frame_substep(pos, vel, DT, RADIUS,
				_puck.max_speed, _puck.ice_height, _puck.max_height, _frame, _tick)
		pos = _tick.position
		vel = _tick.velocity
		if not tipped and pos.z <= tip_pt.z:
			tipped = true
			pos = Vector3(tip_pt.x, pos.y, tip_pt.z)
			var to_goal := Vector2(-tip_pt.x, GOAL_Z - tip_pt.z).normalized().rotated(psi) \
					* SHOT_SPEED * TIP_RETAIN
			vel = Vector3(to_goal.x, vy, to_goal.y)
		if GoalieContactDetector.nearest([_goalie], prev, pos, RADIUS, _scratch, _contact):
			return false
		if pos.z <= GOAL_Z:
			var f: float = clampf((GOAL_Z - prev.z) / (pos.z - prev.z), 0.0, 1.0)
			var cx: float = lerpf(prev.x, pos.x, f)
			var cy: float = lerpf(prev.y, pos.y, f)
			return absf(cx) < GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - RADIUS \
					and cy < GameRules.NET_HEIGHT - RADIUS
	return false


func _tip_goals(shooter: Vector3, stick: Vector2) -> int:
	var body := Vector3(stick.x, 0.0, GOAL_Z + stick.y)
	_tipper.global_position = body
	var tip_pt: Vector3 = body + Vector3(-0.5 * signf(stick.x), 0.0, 0.3)
	var goals: int = 0
	for vy: float in [0.0, 3.8]:
		for psi_deg: float in [-14.0, -7.0, 0.0, 7.0, 14.0]:
			_h.settle_ready(shooter)
			if _tip_scores(shooter, tip_pt, deg_to_rad(psi_deg), vy):
				goals += 1
	return goals


func _direct_goals(shooter: Vector3) -> int:
	var goals: int = 0
	for loft: int in [0, 1, 2, 3]:
		for ai: int in 7:
			_h.settle_ready(shooter)
			var aim := Vector3(lerpf(-0.8, 0.8, ai / 6.0), 0.0, GOAL_Z)
			if _h.fire_release_at(shooter, aim, loft, SHOT_SPEED, 0.0) == Harness.GOAL:
				goals += 1
	return goals


const NO_STICK := Vector3(-20.0, 0.0, 0.0)
const TIP_IN_TIGHT := Vector3(2.5, 0.0, GOAL_Z + 3.0)
const TIP_REACTABLE := Vector3(1.0, 0.0, GOAL_Z + 5.5)


# His settled depth against the wide point shot with the tipper at `tipper`.
func _depth_with_tipper_at(tipper: Vector3) -> float:
	_tipper.global_position = tipper
	_h.settle_ready(WIDE_POINT)
	return _ctrl._current_depth


func test_a_stick_off_the_shooters_line_holds_him_nearer_his_crease() -> void:
	var free: float = _depth_with_tipper_at(NO_STICK)
	assert_lt(_depth_with_tipper_at(TIP_IN_TIGHT), free,
			"a stick at 3 m off the shooter's line holds him in, on the tip's line")
	assert_almost_eq(_depth_with_tipper_at(TIP_REACTABLE), free, 0.01,
			"a tip from 5.5 m is one he can react to, so it does not move him")


func test_tips_score_less_and_the_direct_shot_is_untouched() -> void:
	var tips := {false: 0, true: 0}
	var direct := {false: 0, true: 0}
	for flag: bool in [false, true]:
		_ctrl.tip_room = flag
		for shooter: Vector3 in [CENTRE_POINT, WIDE_POINT]:
			for stick: Vector2 in STICKS:
				tips[flag] += _tip_goals(shooter, stick)
				direct[flag] += _direct_goals(shooter)
	gut.p("tips %d -> %d, direct %d -> %d" % [tips[false], tips[true], direct[false], direct[true]])
	assert_lt(tips[true], tips[false], "the redirect is covered better")
	assert_gt(tips[true], 0, "and it still scores — not a wall")
	assert_lte(direct[true], direct[false], "at no cost to the shot he can react to")


# Rewrite with MITTS_UPDATE_SNAPSHOTS=1 (tests/snapshot.gd) and review the diff.
func test_tip_depth_snapshot() -> void:
	var snap := Snapshot.new("res://tests/slow/ai/snapshots/goalie_tip_threat.txt")
	snap.record("16 m 5 wide, no stick: depth", _depth_with_tipper_at(NO_STICK))
	snap.record("16 m 5 wide, stick at (2.5, 3.0): depth", _depth_with_tipper_at(TIP_IN_TIGHT))
	snap.record("16 m 5 wide, stick at (1.0, 5.5): depth", _depth_with_tipper_at(TIP_REACTABLE))
	snap.verify(self)
