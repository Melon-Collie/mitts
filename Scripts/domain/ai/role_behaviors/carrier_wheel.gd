class_name AICarrierWheel
extends RefCounted

# The 5v5 wheel (breakout plan §B) priced for AICarrierCarrySearch: from behind
# our own goal line, round the back of the cage and out the far half-wall. Reads
# the carrier's field, never writes it.

# The middle of the behind-net alley the wheel is skated through: cage back +
# half the gap to the boards.
const APEX_CLEARANCE_M: float = 0.75

var arrival: float = 0.0

var _field: AICarrierField
# Opponents projected to a later leg's start.
var _scratch_opponents: Array[Vector3] = []
var _scratch_vels: Array[Vector3] = []


func _init(field: AICarrierField) -> void:
	_field = field


# EV of the wheel to `dest`, its value on arrival left in `arrival`: the
# two-leg carry self → the apex → the far half-wall exit, priced as
# AICarrierCarrySearch prices a carry but PER LEG with the defense projected
# through leg one, because a straight-line read for this route would sample the
# inside of the cage. The escape gate (apply_escape) makes a committed same-side chaser
# read as beaten, while a body already waiting on the far side kills leg two.
func score(ctx: RoleContext, dest: Vector3, best_so_far: float) -> float:
	var self_pos: Vector3 = ctx.self_pos
	var apex := Vector3(0.0, 0.0, ctx.own_goal_dir
			* (GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH + APEX_CLEARANCE_M))
	var t1: float = AIArrival.time_to_arrive(
			self_pos, apex, ctx.self_velocity, ctx.self_max_speed,
			ctx.self_max_accel, ctx.self_lateral_grip)
	# Carry pace through the apex, consistent with the arrival model.
	var to_dest: Vector3 = dest - apex
	to_dest.y = 0.0
	var apex_speed: float = minf(
			self_pos.distance_to(apex) / maxf(t1, 0.001), ctx.self_max_speed)
	var v_apex: Vector3 = to_dest.normalized() * apex_speed \
			if to_dest.length_squared() > 0.0001 else Vector3.ZERO
	var t2: float = AIArrival.time_to_arrive(
			apex, dest, v_apex, ctx.self_max_speed, ctx.self_max_accel, ctx.self_lateral_grip)
	# The same exact ceiling ladder as _score_move_candidate_base, per leg.
	var decay: float = AIActionScoring.delay_discount(t1 + t2)
	if decay <= best_so_far:
		return -INF
	var cur_puck: Vector3 = AICarrierField.puck_pos_at(self_pos, ctx.attacking_goal_pos)
	var apex_puck: Vector3 = AICarrierField.puck_pos_at(apex, ctx.attacking_goal_pos)
	var dest_puck: Vector3 = AICarrierField.puck_pos_at(dest, ctx.attacking_goal_pos)
	var carrier_caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	var safety1: float = AICarrySpace.carry_safety(
			cur_puck, apex_puck, t1, _field.opponents,
			_field.opponent_vels, _field.opponent_caps, 0.0, 0.0, carrier_caps)
	if decay * safety1 <= best_so_far:
		return -INF
	# Leg two sets off when leg one ends.
	var safety2: float = AICarrySpace.carry_safety(
			apex_puck, dest_puck, t2, _field.opponents,
			_field.opponent_vels, _field.opponent_caps, 0.0, t1, carrier_caps)
	var keep: float = safety1 * safety2
	var ceiling: float = decay * keep
	if ceiling <= best_so_far:
		return -INF
	_field.project_opponents(t1 + t2, _scratch_opponents, _scratch_vels, dest)
	var dest_score: float = _field.value_at(ctx, dest, self_pos, _scratch_opponents,
			Vector3.INF, 0.0, 1.0, AIShotOdds.Stance.UPRIGHT, NAN, 0.0, Vector3.ZERO,
			ctx.caps_by_peer.get(ctx.peer_id))
	arrival = dest_score
	var benefit: float = dest_score * ceiling
	if keep >= 1.0:
		return benefit
	# The strip is priced on whichever leg is the unsafe one.
	var strip_point: Vector3
	var strip_s: float
	if safety1 <= safety2:
		strip_point = AICarrySpace.carry_strip_point(
				cur_puck, apex_puck, t1, _field.opponents,
				_field.opponent_vels, _field.opponent_caps, false, 0.0, 0.0, carrier_caps)
		strip_s = t1 * _leg_share(cur_puck, apex_puck, strip_point)
	else:
		strip_point = AICarrySpace.carry_strip_point(
				apex_puck, dest_puck, t2, _field.opponents,
				_field.opponent_vels, _field.opponent_caps, false, 0.0, t1, carrier_caps)
		strip_s = t1 + t2 * _leg_share(apex_puck, dest_puck, strip_point)
	var cost: float = _field.turnover_cost(strip_point,
			1.0 - keep, strip_s)
	return benefit - cost


# How far along the leg `from` → `to` the point `at` lies, as a share of its length.
static func _leg_share(from: Vector3, to: Vector3, at: Vector3) -> float:
	var length: float = from.distance_to(to)
	return clampf(from.distance_to(at) / length, 0.0, 1.0) if length > 0.001 else 0.0
