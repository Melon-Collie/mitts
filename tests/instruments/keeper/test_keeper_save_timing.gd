extends GutTest

# ── WHETHER HIS SAVE GETS THERE ──────────────────────────────────────────────
# The scoreboard counts goals; this says why. Each shot is fired at the live
# keeper (KeeperController on Goalie.tscn, set on the shooter first) and marched
# through the puck's real frame step and contact test, as the shot harness
# does. Per shot it prints the save he chose and when, its margin (the time the
# puck gives him less the time the save needs; negative is late), how far his
# hand and his drop had got when the shot was decided, and what decided it:
# the gear it met, or where it crossed the line.
#
#   grid     every tier, from the slot, the high slot and the dot, at a wrister
#            and a hard shot, to the corners, the pads' height, the middle, the
#            top and the five-hole
#   rebound  a five-hole shot he saves, then a low shot to the far corner
#            fired at gaps after it, and what he was doing (his mover) as it
#            left the stick
#
# Run: bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments/keeper
#      -gselect=test_keeper_save_timing. Asserts nothing.

const Harness := preload("res://tests/unit/ai/human_wraparound_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const MAX_TICKS: int = 200
const SETTLE_MAX_TICKS: int = 400
# Inside the iron, by a puck's width.
const AIM_X: float = GameRules.NET_HALF_WIDTH - 0.12
const SPEEDS: Array[float] = [22.0, 32.0]
const TIERS: Array[int] = [GoalieSkillProfile.Difficulty.HARD, GoalieSkillProfile.Difficulty.NORMAL,
		GoalieSkillProfile.Difficulty.EASY]
const SPOTS: Array[Vector3] = [Vector3(0.0, 0.0, GOAL_Z + 9.0), Vector3(0.0, 0.0, GOAL_Z + 13.0),
		Vector3(-6.7, 0.0, GOAL_Z + 6.1)]
const REBOUND_GAPS_S: Array[float] = [0.2, 0.4, 0.6, 0.8, 1.0, 1.3]
const REBOUND_FROM := Vector3(-1.5, 0.0, GOAL_Z + 7.0)

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: KeeperController = null
var _h: RefCounted = null
var _scratch := SweptDiscOBB.Result.new()
var _contact := GoalieContactDetector.Contact.new()
var _frame := PuckGeometryCollision.Result.new()
var _tick := PuckAuthorityRules.TickResult.new()


func _build() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)
	_ctrl.set_skater_getter(func() -> Array: return [_shooter])


func _targets() -> Dictionary:
	return {
		"low glove": Vector3(AIM_X, 0.0, GOAL_Z), "low blocker": Vector3(-AIM_X, 0.0, GOAL_Z),
		"five-hole": Vector3(0.0, 0.0, GOAL_Z),
		"pad glove": Vector3(AIM_X, 0.3, GOAL_Z), "pad blocker": Vector3(-AIM_X, 0.3, GOAL_Z),
		"mid glove": Vector3(AIM_X, 0.7, GOAL_Z), "mid blocker": Vector3(-AIM_X, 0.7, GOAL_Z),
		"top glove": Vector3(AIM_X, 1.05, GOAL_Z), "top blocker": Vector3(-AIM_X, 1.05, GOAL_Z),
	}


func test_report_save_timing() -> void:
	_build()
	var targets: Dictionary = _targets()
	for tier: int in TIERS:
		for spot: Vector3 in SPOTS:
			for speed: float in SPEEDS:
				gut.p("── %s from (%.1f, %.1f) m off the goal line's centre, %.0f m/s" % [
						GoalieSkillProfile.Difficulty.keys()[tier], spot.x, spot.z - GOAL_Z, speed])
				for k: String in targets:
					_settle(tier, spot)
					gut.p("  %-12s %s" % [k, _fire(spot, targets[k], speed)])
	for tier: int in TIERS:
		gut.p("── %s rebound: a low shot from (%.1f, %.1f) after a five-hole shot" % [
				GoalieSkillProfile.Difficulty.keys()[tier], REBOUND_FROM.x, REBOUND_FROM.z - GOAL_Z])
		for gap: float in REBOUND_GAPS_S:
			gut.p("  %.1f s on  %s" % [gap, _rebound(tier, gap)])
	assert_true(true)


# Set on a carrier standing at `spot`, on the tier's profile, from a full reset.
func _settle(tier: int, spot: Vector3) -> void:
	_ctrl.apply_skill_profile(GoalieSkillProfile.for_difficulty(tier))
	_ctrl.reset_to_crease()
	_ctrl._view.invalidate()
	_h.settle_ready(spot)
	for _i: int in SETTLE_MAX_TICKS:
		if _ctrl.motor.is_idle():
			return
		_puck.global_position = spot
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._view.invalidate()
		_ctrl._physics_process(DT)


func _rebound(tier: int, gap_s: float) -> String:
	_settle(tier, Vector3(0.0, 0.0, GOAL_Z + 10.0))
	var first: String = _fire(Vector3(0.0, 0.0, GOAL_Z + 10.0), Vector3(0.0, 0.0, GOAL_Z), 20.0)
	_shooter.global_position = REBOUND_FROM
	for _i: int in int(gap_s / DT):
		_puck.global_position = REBOUND_FROM
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._view.invalidate()
		_ctrl._physics_process(DT)
	var doing: String = KeeperMotor.Mover.keys()[_ctrl.motor._mover]
	return "first: %s | %-6s second: %s" % [first.get_slice("|", 3).strip_edges(), doing,
			_fire(REBOUND_FROM, Vector3(AIM_X, 0.0, GOAL_Z), 20.0)]


# Fires from `spot` on the flight that crosses the goal line at `target` (along
# the ice for a target on it) and marches it until it is decided.
func _fire(spot: Vector3, target: Vector3, speed: float) -> String:
	var flat := Vector2(target.x - spot.x, target.z - spot.z)
	var flight_s: float = flat.length() / speed
	var vy: float = 0.0
	if target.y > 0.0:
		vy = (target.y + 0.5 * GameRules.GRAVITY_M_S2 * flight_s * flight_s) / flight_s
	var along: Vector2 = flat.normalized() * speed
	var vel := Vector3(along.x, vy, along.y)
	_puck.clear_carrier()
	var pos := Vector3(spot.x, _puck.ice_height, spot.z)
	_puck.global_position = pos
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	var chosen: String = "nothing chosen"
	var hand_from := Vector3.INF
	for step: int in MAX_TICKS:
		var prev: Vector3 = pos
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)
		var s: KeeperSave = _ctrl.save
		if _ctrl._chosen and chosen == "nothing chosen":
			chosen = "%-9s+%-7s at %.3f s, margin %+.3f" % [KeeperSaveMove.Low.keys()[s.low],
					KeeperSave.Hand.keys()[s.hand], (step + 1) * DT, s.impact_s - s.ready_s]
		if _ctrl._chosen and s.active() and hand_from == Vector3.INF:
			hand_from = s._hand_at
		_tick.touched_post = false
		_tick.touched_net = false
		PuckAuthorityRules.step_frame_substep(pos, vel, DT, GameRules.PUCK_COLLISION_RADIUS, _puck.max_speed,
				_puck.ice_height, _puck.max_height, _frame, _tick)
		pos = _tick.position
		vel = _tick.velocity
		var met: bool = GoalieContactDetector.nearest([_goalie], prev, pos, GameRules.PUCK_COLLISION_RADIUS,
				_scratch, _contact)
		var crossed: bool = pos.z <= GOAL_Z
		if met or crossed:
			var verdict: String = "saved, %s" % (_contact.part as Node3D).name if met else _crossing(pos)
			return "%-46s | hand %s, drop %s | %.3f s | %s" % [chosen, _hand_share(s, hand_from), _drop_share(),
					step * DT, verdict]
	return "%s | undecided" % chosen


func _crossing(at: Vector3) -> String:
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	var inside: bool = absf(at.x) < GameRules.NET_HALF_WIDTH - r and at.y < GameRules.NET_HEIGHT - r
	return "%s at (%.2f, %.2f)" % ["GOAL" if inside else "wide", at.x, at.y]


# How far the hand had come from where it set out to its target.
func _hand_share(s: KeeperSave, from: Vector3) -> String:
	if not s.active() or from == Vector3.INF:
		return "  -"
	var whole: float = maxf(from.distance_to(s.hand_target), 1e-4)
	return "%3d%%" % roundi(100.0 * (1.0 - s._hand_at.distance_to(s.hand_target) / whole))


# How far down the low save had fallen (the fall's own ease).
func _drop_share() -> String:
	var m: KeeperSaveMove = _ctrl.motor.save_move
	match m.state:
		KeeperSaveMove.State.GOING:
			return "%3d%%" % roundi(100.0 * m._clock * m._clock)
		KeeperSaveMove.State.HELD:
			return "100%"
	return "  -"
