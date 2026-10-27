extends RefCounted

# Puts the live keeper into a staged state and fires the bot's release at him,
# over real_goalie_shot_harness. Shared by the shot-odds truth table and the
# shot-field generator so the two stage the keeper identically. No class_name
# (test infra stays out of the global namespace).

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SHOT_SPEED: float = AIBotMechanics.WRISTER_SHOT_SPEED_M_S
const CHARGE_TICKS: int = AIBotMechanics.BOT_WRISTER_CHARGE_TICKS
# Post to post at ~6.5 cm.
const AIM_POINTS: int = 24
const LOFTS: Array[int] = [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW,
		ShotMechanics.ELEVATION_HIGH]
const OUTCOME_CHARS: String = "GsPw"
# The deke's forward pace and duration; the caller picks how far across.
const DEKE_S: float = 0.4
const DEKE_FORWARD_M_S: float = 3.0
# Every staged carrier skated in: from this far straight out, at this pace.
const APPROACH_M: float = 4.0
const APPROACH_M_S: float = 4.0
# A wrap's carrier comes along the end boards from this far across.
const WRAP_FROM_X_M: float = 5.0

var goal := Vector3(0.0, 0.0, GOAL_Z)
# The keeper as he stood square on the passer, just before the last feed left.
var pre_feed_read: GoalieNetworkState = GoalieNetworkState.new()
var _h: RefCounted
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController


func _init(goalie: Node, puck: Node, ctrl: GoalieController, shooter: Skater) -> void:
	_puck = puck
	_shooter = shooter
	_ctrl = ctrl
	_h = Harness.new()
	_h.setup(goalie, puck, ctrl, shooter)


# Settled and square on a carrier at `spot`. Returns the release point.
func stage_set(spot: Vector3) -> Vector3:
	_settle_on(spot)
	return spot


# Settled square on a carrier at `passer`, then a feed travels loose to the
# receiver waiting at `spot` at `speed`. Returns the release point.
func stage_feed(spot: Vector3, passer: Vector3, speed: float) -> Vector3:
	_settle_on(passer)
	_ctrl.fill_state(pre_feed_read)
	_shooter.global_position = spot
	_shooter.velocity = Vector3.ZERO
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_puck.clear_carrier()
	var dist: float = passer.distance_to(spot)
	var ticks: int = maxi(int(dist / speed / DT), 1)
	var vel: Vector3 = (spot - passer).normalized() * speed
	for i: int in ticks:
		_puck.global_position = passer.lerp(spot, float(i + 1) / float(ticks))
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)
	return spot


# Settled square on a carrier at `decoy`, then the puck is at `spot` with no
# flight between: the limit of a feed, the keeper as a play left him out of
# position. Returns the release point.
func stage_decoy(spot: Vector3, decoy: Vector3) -> Vector3:
	_settle_on(decoy)
	_shooter.global_position = spot
	_shooter.velocity = Vector3.ZERO
	_puck.global_position = spot
	_puck.linear_velocity = Vector3.ZERO
	return spot


# Sealed in the RVH on a carrier behind the net at `behind`, skated in along
# the end boards, then the puck is at `spot` with no flight between: the limit
# of a wrap out front, the keeper still on the post. Returns the release point.
func stage_wrap(spot: Vector3, behind: Vector3) -> Vector3:
	_h.approach_and_settle(behind, Vector3(signf(behind.x) * WRAP_FROM_X_M, 0.0, behind.z),
			APPROACH_M_S)
	_shooter.global_position = spot
	_shooter.velocity = Vector3.ZERO
	_puck.global_position = spot
	_puck.linear_velocity = Vector3.ZERO
	return spot


# Settled on the carrier `across` metres to the side of `spot` (and a stride
# further out), who then dekes across onto it. Returns where the puck ends up,
# which is the release point.
func stage_deke(spot: Vector3, across: float) -> Vector3:
	_settle_on(Vector3(spot.x - across, 0.0, spot.z + DEKE_FORWARD_M_S * DEKE_S))
	return _h.deke_across(spot.x, DEKE_S, DEKE_FORWARD_M_S)


# The keeper set on a carrier who skated in to `at` straight from up the ice.
func _settle_on(at: Vector3) -> void:
	_h.approach_and_settle(at, at - Vector3(0.0, 0.0, signf(GOAL_Z) * APPROACH_M), APPROACH_M_S)


# The bot's release from the staged state: a one-timer leaves cold; everything
# else charges the wrister first, publishing its aim as it does. `caught`: the
# puck arrived loose and the receiver takes it before charging.
func release(release_pos: Vector3, one_timer: bool, caught: bool, aim: Vector3,
		loft: int) -> int:
	if one_timer:
		return _h.fire_at(release_pos, aim, loft, SHOT_SPEED, 0.0)
	if caught:
		_puck.set_carrier(_shooter)
	_h.hold_windup_at(release_pos, aim, loft, SHOT_SPEED, CHARGE_TICKS)
	return _h.fire_release_at(release_pos, aim, loft, SHOT_SPEED, 0.0)


# The goalie's open set for a staged state: FLAT / LOW / HIGH, each AIM_POINTS
# outcome characters post to post. `stage` re-stages the keeper and returns the
# release point; it runs before every shot.
func open_set(stage: Callable, one_timer: bool, caught: bool) -> PackedStringArray:
	var out: PackedStringArray = []
	for loft: int in LOFTS:
		var p: String = ""
		for i: int in AIM_POINTS:
			var at: Vector3 = stage.call()
			p += OUTCOME_CHARS[release(at, one_timer, caught,
					Vector3(aim_x(i), 0.0, GOAL_Z), loft)]
		out.append(p)
	return out


# One shot from a staged state, as its outcome character.
func outcome(stage: Callable, one_timer: bool, caught: bool, aim: Vector3,
		loft: int) -> String:
	var at: Vector3 = stage.call()
	return OUTCOME_CHARS[release(at, one_timer, caught, aim, loft)]


func read() -> GoalieNetworkState:
	var gs := GoalieNetworkState.new()
	_ctrl.fill_state(gs)
	return gs


static func aim_x(i: int) -> float:
	var reach: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS \
			- GameRules.PUCK_COLLISION_RADIUS
	return lerpf(-reach, reach, float(i) / float(AIM_POINTS - 1))


static func read_fields(gs: GoalieNetworkState) -> String:
	var v: Array[float] = [gs.position_x, gs.position_z, gs.rotation_y,
			float(gs.state_enum), gs.five_hole_openness, gs.velocity_x, gs.velocity_z]
	var parts: PackedStringArray = []
	for f: float in v:
		parts.append("%.4f" % f)
	return "\t".join(parts)
