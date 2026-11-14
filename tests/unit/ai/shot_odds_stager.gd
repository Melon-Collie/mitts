extends RefCounted

# Puts the live keeper into a staged state and fires the bot's release at him,
# over real_goalie_shot_harness. Shared by the shot-odds truth table and the
# shot-field generator so the two stage the keeper identically. No class_name
# (test infra stays out of the global namespace).

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const Edges := preload("res://tests/unit/ai/open_set_edges.gd")
const Cloner := preload("res://tests/instruments/keeper/keeper_state_cloner.gd")

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
# A wrap's carrier comes along the end boards from this far across, then carries
# it round the post on his side, this far across and out in front, at this pace.
const WRAP_FROM_X_M: float = 5.0
const WRAP_CORNER_X_M: float = 1.6
const WRAP_CORNER_OUT_M: float = 0.6
const WRAP_CARRY_M_S: float = 4.0
# What a staging leaves on the shooter: every field of his it writes, and all
# the keeper reads of him.
const SHOOTER_STAGED: Array[String] = ["global_transform", "velocity", "current_shot_state",
		"predicted_shot_velocity"]
# A drive: a carrier skating straight down the ice at a breakaway's pace (the
# breakaway fixtures skate in at 8.4–9.2 m/s) from this far out, the keeper
# tracking him the whole way, who charges his wrister in stride over the last
# CHARGE_M and releases at the spot.
const DRIVE_FROM_M: float = 25.0
const DRIVE_M_S: float = 9.0
const CHARGE_M: float = DRIVE_M_S * float(CHARGE_TICKS) * DT

var goal := Vector3(0.0, 0.0, GOAL_Z)
# The keeper as he stood square on the passer, just before the last feed left.
var pre_feed_read: GoalieNetworkState = GoalieNetworkState.new()
# Re-stage him before every shot of an open set rather than restore the state
# the first staging left: the reference a restored open set is held against.
var restage_every_shot: bool = false
var _h: RefCounted
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController
var _cloner: RefCounted = Cloner.new()
var _staged_keeper: Dictionary = {}
var _staged_puck: Dictionary = {}
var _staged_shooter: Dictionary = {}


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
	return _feed(spot, passer, speed)


# Sealed in the RVH on a carrier behind the net at `passer`, skated in along the
# end boards as a wrap's is, who passes it out to the receiver waiting at `spot`
# at `speed`. Returns the release point.
func stage_pass_out(spot: Vector3, passer: Vector3, speed: float) -> Vector3:
	_h.approach_and_settle(passer, Vector3(signf(passer.x) * WRAP_FROM_X_M, 0.0, passer.z),
			APPROACH_M_S)
	return _feed(spot, passer, speed)


# The feed from `passer` to the receiver waiting at `spot` at `speed`, the keeper
# read as he stood before it left and then every tick of its flight.
func _feed(spot: Vector3, passer: Vector3, speed: float) -> Vector3:
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
		_h.step_keeper()
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
# the end boards, who then carries it round the post on his side and out to
# `spot`, the keeper tracking him the whole way. Never a jump from behind the
# net to the spot: what the keeper does then depends on where it jumped from,
# which no read of him shows. Returns the release point.
func stage_wrap(spot: Vector3, behind: Vector3) -> Vector3:
	var side: float = signf(behind.x)
	_h.approach_and_settle(behind, Vector3(side * WRAP_FROM_X_M, 0.0, behind.z), APPROACH_M_S)
	var corner := Vector3(side * WRAP_CORNER_X_M, 0.0,
			GOAL_Z - signf(GOAL_Z) * WRAP_CORNER_OUT_M)
	_carry(behind, corner)
	_carry(corner, spot)
	_shooter.velocity = Vector3.ZERO
	return spot


# The carrier skates the puck on his blade from `from` to `to` at WRAP_CARRY_M_S,
# the keeper reading him every tick.
func _carry(from: Vector3, to: Vector3) -> void:
	var ticks: int = maxi(int(from.distance_to(to) / WRAP_CARRY_M_S / DT), 1)
	var vel: Vector3 = (to - from) / (float(ticks) * DT)
	for i: int in ticks:
		var at: Vector3 = from.lerp(to, float(i + 1) / float(ticks))
		_shooter.global_position = at
		_shooter.velocity = vel
		_puck.global_position = at
		_puck.linear_velocity = Vector3.ZERO
		_h.step_keeper()


# Settled on the carrier `across` metres to the side of `spot` (and a stride
# further out), who then dekes across onto it. Returns where the puck ends up,
# which is the release point.
func stage_deke(spot: Vector3, across: float) -> Vector3:
	_settle_on(Vector3(spot.x - across, 0.0, spot.z + DEKE_FORWARD_M_S * DEKE_S))
	return _h.deke_across(spot.x, DEKE_S, DEKE_FORWARD_M_S)


# The keeper tracking a carrier driving straight in at DRIVE_M_S to a charge's
# skate short of `spot`; release(driven) skates the charge. Returns the release
# point.
func stage_drive(spot: Vector3) -> Vector3:
	var fwd: float = spot.z - GOAL_Z
	_h.settle_ready(Vector3(spot.x, 0.0, GOAL_Z + DRIVE_FROM_M))
	_h.drive_in(spot.x, DRIVE_FROM_M, fwd + CHARGE_M, DRIVE_M_S)
	return spot


# The keeper tracking a carrier driving straight in at DRIVE_M_S in the lane
# `across` metres to the side of `spot`, who then dekes across onto it as
# stage_deke's does. Returns where the puck ends up, the release point.
func stage_drive_deke(spot: Vector3, across: float) -> Vector3:
	var start := Vector3(spot.x - across, 0.0, spot.z + DEKE_FORWARD_M_S * DEKE_S)
	_h.settle_ready(Vector3(start.x, 0.0, GOAL_Z + DRIVE_FROM_M))
	_h.drive_in(start.x, DRIVE_FROM_M, start.z - GOAL_Z, DRIVE_M_S)
	return _h.deke_across(spot.x, DEKE_S, DEKE_FORWARD_M_S)


# The keeper set on a carrier who skated in to `at` straight from up the ice.
func _settle_on(at: Vector3) -> void:
	_h.approach_and_settle(at, at - Vector3(0.0, 0.0, signf(GOAL_Z) * APPROACH_M), APPROACH_M_S)


# The bot's release from the staged state: a one-timer leaves cold; everything
# else charges the wrister first, publishing its aim as it does. `caught`: the
# puck arrived loose and the receiver takes it before charging. `driven`: the
# charge is skated, the last CHARGE_M of a drive (stage_drive).
func release(release_pos: Vector3, one_timer: bool, caught: bool, aim: Vector3,
		loft: int, driven: bool = false) -> int:
	if one_timer:
		return _h.fire_at(release_pos, aim, loft, SHOT_SPEED, 0.0)
	if caught:
		_puck.set_carrier(_shooter)
	if driven:
		var fwd: float = release_pos.z - GOAL_Z
		_h.drive_in(release_pos.x, fwd + CHARGE_M, fwd, DRIVE_M_S, aim, loft, SHOT_SPEED)
	else:
		_h.hold_windup_at(release_pos, aim, loft, SHOT_SPEED, CHARGE_TICKS)
	return _h.fire_release_at(release_pos, aim, loft, SHOT_SPEED, 0.0)


# The goalie's open set for a staged state: FLAT / LOW / HIGH, each AIM_POINTS
# outcome characters post to post, then the same three lofts' goal intervals
# with their edges bisected (open_set_edges.gd, encoded). `stage` stages the
# keeper and returns the release point. It runs once, and every shot is fired
# from the world it left, restored: a staging is the same whatever ran before it
# (test_shot_field_cells_are_order_free.gd), so this is the world re-staging
# would give, at a staging per open set rather than one a shot.
func open_set(stage: Callable, one_timer: bool, caught: bool,
		driven: bool = false) -> PackedStringArray:
	var sweeps: PackedStringArray = []
	var intervals: PackedStringArray = []
	var staged_at: Vector3 = stage.call()
	_capture_staged()
	for loft: int in LOFTS:
		var shoot: Callable = func(aim: float) -> String:
			var at: Vector3 = staged_at
			if restage_every_shot:
				at = stage.call()
			else:
				_restore_staged()
			return OUTCOME_CHARS[release(at, one_timer, caught, Vector3(aim, 0.0, GOAL_Z), loft,
					driven)]
		var p: String = ""
		for i: int in AIM_POINTS:
			p += shoot.call(aim_x(i))
		sweeps.append(p)
		intervals.append(Edges.encode(Edges.refine(p, shoot)))
	return sweeps + intervals


# The keeper, the puck and the shooter as the staging left them.
func _capture_staged() -> void:
	_staged_keeper = _cloner.capture(_ctrl as KeeperController)
	_staged_puck.clear()
	for p: Dictionary in _puck.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = _puck.get(String(p["name"]))
			if typeof(v) not in [TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
				_staged_puck[String(p["name"])] = _own(v)
	_staged_puck["global_transform"] = (_puck as Node3D).global_transform
	_staged_shooter.clear()
	for f: String in SHOOTER_STAGED:
		_staged_shooter[f] = _shooter.get(f)


func _restore_staged() -> void:
	_cloner.restore(_staged_keeper, _ctrl as KeeperController)
	for f: String in _staged_puck:
		_puck.set(f, _own(_staged_puck[f]))
	for f: String in _staged_shooter:
		_shooter.set(f, _staged_shooter[f])


# `v`, a container copied so the capture and the live node never share one.
static func _own(v: Variant) -> Variant:
	if v is Array:
		return (v as Array).duplicate(true)
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if Cloner.is_packed(v):
		return v.duplicate()
	return v


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
	return Edges.aim_x(i, AIM_POINTS)


static func read_fields(gs: GoalieNetworkState) -> String:
	var v: Array[float] = [gs.position_x, gs.position_z, gs.rotation_y,
			float(gs.state_enum), gs.five_hole_openness, gs.velocity_x, gs.velocity_z]
	var parts: PackedStringArray = []
	for f: float in v:
		parts.append("%.4f" % f)
	return "\t".join(parts)
