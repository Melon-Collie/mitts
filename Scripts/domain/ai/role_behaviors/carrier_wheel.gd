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


func _init(field: AICarrierField) -> void:
	_field = field


# EV of the wheel to `dest`, its value on arrival left in `arrival`: the
# two-leg carry self → the apex → the far half-wall exit, priced as
# AICarrierCarrySearch prices a carry but PER LEG with the defense projected
# through leg one, because a straight-line read for this route would sample the
# inside of the cage. The escape gate (apply_escape) makes a committed same-side chaser
# read as beaten, while a body already waiting on the far side kills leg two.
func score(ctx: RoleContext, dest: Vector3,
		our_goalie: Vector3, best_so_far: float) -> float:
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
	var lane1: float = AICarrySpace.carry_lane_clearance(
			self_pos, apex, t1, _field.opponents, _field.opponent_vels,
			ctx.self_max_speed)
	if lane1 <= 0.0 or lane1 * decay <= best_so_far:
		return -INF
	var cur_puck: Vector3 = AICarrierField.puck_pos_at(self_pos, ctx.attacking_goal_pos)
	var apex_puck: Vector3 = AICarrierField.puck_pos_at(apex, ctx.attacking_goal_pos)
	var dest_puck: Vector3 = AICarrierField.puck_pos_at(dest, ctx.attacking_goal_pos)
	var safety1: float = AICarrySpace.carry_safety(
			cur_puck, apex_puck, t1, _field.opponents,
			_field.opponent_vels, _field.opponent_caps, true)
	if lane1 * decay * safety1 <= best_so_far:
		return -INF
	# Leg two starts where the defense has skated to during leg one.
	_field.project_opponents(t1, _scratch_opponents)
	var lane2: float = AICarrySpace.carry_lane_clearance(
			apex, dest, t2, _scratch_opponents, _field.opponent_vels,
			ctx.self_max_speed)
	if lane2 <= 0.0:
		return -INF
	var safety2: float = AICarrySpace.carry_safety(
			apex_puck, dest_puck, t2, _scratch_opponents,
			_field.opponent_vels, _field.opponent_caps, true)
	var keep: float = safety1 * safety2
	var ceiling: float = lane1 * lane2 * decay * keep
	if ceiling <= best_so_far:
		return -INF
	_field.project_opponents(t1 + t2, _scratch_opponents)
	var dest_score: float = _field.value_at(ctx, dest, self_pos, _scratch_opponents)
	arrival = dest_score
	var benefit: float = dest_score * ceiling
	if keep >= 1.0:
		return benefit
	# The strip is priced on whichever leg is the unsafe one.
	var strip_point: Vector3
	if safety1 <= safety2:
		strip_point = AICarrySpace.carry_strip_point(
				cur_puck, apex_puck, t1, _field.opponents,
				_field.opponent_vels, _field.opponent_caps, true)
	else:
		_field.project_opponents(t1, _scratch_opponents)
		strip_point = AICarrySpace.carry_strip_point(
				apex_puck, dest_puck, t2, _scratch_opponents,
				_field.opponent_vels, _field.opponent_caps, true)
	var cost: float = _field.turnover_cost(strip_point,
			1.0 - keep)
	cost += _field.counter_exposure_cost(ctx, strip_point, 1.0 - keep, dest, our_goalie)
	return benefit - cost

