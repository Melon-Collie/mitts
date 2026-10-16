class_name AICarrierDumpSearch
extends RefCounted

# The carrier's last-resort DUMP-IN: which delivery to fire past the red line
# when nothing else is worth keeping the puck for, priced on the race to where
# it settles. AIRoleCarrier owns one over its AICarrierField, calls search() from
# its commit phase and reads the result fields; it never writes them.

# How far down the chosen launch line the dump's aim point is placed. The
# charged release converges its blade's side offset onto this point, so a far
# point keeps the puck parallel to the searched launch line.
const DUMP_AIM_STANDOFF_M: float = 20.0

var _field: AICarrierField

# ── Result (valid after search) ──────────────────────────────────────────────
var value: float = -INF
# Where the stick points: a standoff down the launch line.
var aim: Vector3 = Vector3.INF
# Where the puck comes to rest — every term is priced here.
var settle: Vector3 = Vector3.INF
var launch_speed: float = 0.0

# ── Scratch ──────────────────────────────────────────────────────────────────
# Our chasers for the race: our defenders plus ourselves (we dump and chase),
# velocities index-matched — the race is run on ETAs, so momentum is part of it.
var _chasers: Array[Vector3] = []
var _chaser_vels: Array[Vector3] = []
# Out-param for the dump-in landing solve, so it returns its resting spot
# without allocating.
var _landing: Array[Vector3] = [Vector3.ZERO]


func _init(field: AICarrierField) -> void:
	_field = field


# What handing the puck over at `spot` costs us: the immediate threat there, plus
# the counter-rush the loss opens (5v5). Returns (concede, recovery) packed into
# a Vector2 — a value type, so pricing allocates nothing.
func _concession(ctx: RoleContext, spot: Vector3, our_goalie: Vector3) -> Vector2:
	var recovery: float = AIActionScoring.chase_recovery(
			spot, _chasers, _field.opponents,
			_chaser_vels, _field.opponent_vels)
	var loss: float = 1.0 - recovery
	var concede: float = _field.turnover_cost(ctx, spot, loss, our_goalie)
	concede += _field.counter_exposure_cost(ctx, spot, loss, ctx.self_pos, our_goalie)
	return Vector2(concede, recovery)


# Searches the dump-in into the result fields; `value` is -INF when none
# applies: short of the red line or in the OZ, a delayed offside or an icing
# release, or no solution. The caller reads the value only as availability and
# for the debug label.
#
# The aim (a standoff down the launch line, where the stick points) and the
# settle (where the puck comes to rest) are DIFFERENT, and every term is priced
# at the settle — see Scripts/domain/ai/CLAUDE.md → "The dump-in is a
# searched RELEASE". Never icing, since it is offered only past the red line.
func search(ctx: RoleContext, our_goalie: Vector3) -> void:
	value = -INF
	var self_pos: Vector3 = ctx.self_pos
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	if not AIActionScoring.past_center_toward_attack(self_pos, attacking_goal) \
			or AIActionScoring.in_offensive_zone(self_pos, attacking_goal):
		return
	var origin: Vector3 = AICarrierField.pass_origin(ctx)
	# Icing reads the PUCK, which sits a stick off the body: a dump-in from a body
	# past centre can still leave from behind the red line. And with a teammate
	# owing a tag-up, a dumped puck is one nobody may touch.
	if ctx.zone_entry_blocked or (ctx.icing_enforced and InfractionRules.behind_red_line(
			origin.z, signf(attacking_goal.z))):
		return
	# Our chasers = teammates + ourselves (we dump and chase).
	_chasers.clear()
	_chaser_vels.clear()
	for i: int in _field.our_defenders.size():
		_chasers.append(_field.our_defenders[i])
		_chaser_vels.append(_field.our_defender_vels[i])
	_chasers.append(self_pos)
	_chaser_vels.append(ctx.self_velocity)

	_landing[0] = origin
	# The pace ladder runs over the dumper's OWN release band, and the winning
	# pace must be carried out to the release (dump_launch_speed), or the
	# placement is lost.
	var launch: Vector3 = AIActionScoring.solve_dump_in(
			origin, attacking_goal, ctx.self_wrister_shot_speed,
			_chasers, _field.opponents, AICarrierField.goalie_now(ctx),
			_landing, _chaser_vels, _field.opponent_vels)
	if launch == Vector3.ZERO:
		return
	var rest: Vector3 = _landing[0]
	var priced: Vector2 = _concession(ctx, rest, our_goalie)

	# MOMENTUM-HONEST chase clock; never `nearest_distance / max_speed`, an
	# instant full-speed sprint from a standstill. Nearest by ETA, not by metres:
	# the man already moving that way is the chaser even when someone flat-footed
	# stands closer.
	var chase_t: float = AIArrival.time_to_arrive(
			self_pos, rest, ctx.self_velocity, ctx.self_max_speed,
			ctx.self_max_accel, ctx.self_lateral_grip)
	for i: int in _field.our_defenders.size():
		var mate_caps: AISkaterCaps = _field.our_defender_caps[i]
		chase_t = minf(chase_t, AIArrival.time_to_arrive(
				_field.our_defenders[i], rest, _field.our_defender_vels[i],
				mate_caps.max_speed if mate_caps != null else ctx.self_max_speed,
				mate_caps.max_accel if mate_caps != null else ctx.self_max_accel))
	# The resting spot's potential is FUTURE value, so it pays the realization
	# discount like every other future-value read; XG_SLOT_REF puts it in the odds
	# the carry and the pass are priced in.
	var gain: float = priced.y * AIActionScoring.position_potential(
			rest, attacking_goal, _field.opponents) \
			* AIActionScoring.delay_discount(chase_t) \
			* AIActionScoring.potential_realization_discount(rest, attacking_goal) \
			* AIActionScoring.XG_SLOT_REF

	value = gain - priced.x
	# Down the launch line, not at the resting spot (see DUMP_AIM_STANDOFF_M).
	aim = origin + launch.normalized() * DUMP_AIM_STANDOFF_M
	settle = rest
	launch_speed = launch.length()
