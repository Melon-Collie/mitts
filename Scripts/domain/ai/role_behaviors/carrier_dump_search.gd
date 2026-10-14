class_name AICarrierDumpSearch
extends RefCounted

# The carrier's last-resort DUMP: which delivery to fire when nothing else is
# worth keeping the puck for — the DZ clear (a pure concession) or the NZ
# dump-in (priced on the race to where it settles). AIRoleCarrier owns one,
# calls search() from its commit phase and reads the result fields; it never
# writes them.

# How far down the chosen launch line the dump's aim point is placed. Distance
# is not direction, but it has to clear the blade: the quick release aims
# blade->cursor and the blade is the ROM-projection of that same cursor, so a
# cursor inside the stick's reach carries no direction at all. Comfortably
# outside any reach.
const DUMP_AIM_STANDOFF_M: float = 20.0

# ── Result (valid after search) ──────────────────────────────────────────────
var value: float = -INF
# Where the stick points: a standoff down the launch line.
var aim: Vector3 = Vector3.INF
# The NZ dump-in's soft flip; false for the DZ clear's HIGH chip.
var is_soft: bool = false
# Where the puck comes to rest — every term is priced here.
var settle: Vector3 = Vector3.INF
var launch_speed: float = 0.0

# ── Scratch ──────────────────────────────────────────────────────────────────
# Our chasers for the race: our defenders plus ourselves (we dump and chase),
# velocities index-matched — the race is run on ETAs, so momentum is part of it.
var _chasers: Array[Vector3] = []
var _chaser_vels: Array[Vector3] = []
# Legal DZ-clear launches and where each comes to rest, index-matched
# (AIActionScoring.dump_clear_candidates fills them), and each one's recovery
# odds, so the ranking pass doesn't re-race the same bodies to the same spots.
var _clear_vels: Array[Vector3] = []
var _clear_spots: Array[Vector3] = []
var _clear_recovery: Array[float] = []
# Out-param for the dump-in landing solve, so it returns its resting spot
# without allocating.
var _landing: Array[Vector3] = [Vector3.ZERO]


# Two clears priced within this of each other are the same clear, so depth
# breaks the tie (see search). Sized well under the shot-threat scale the
# prices are denominated in.
const CLEAR_PRICE_TIE_BAND: float = 0.001


# What handing the puck over at `spot` costs us: the immediate threat there, plus
# the counter-rush the loss opens (5v5). Returns (concede, recovery) packed into
# a Vector2 — a value type, so pricing a whole candidate set allocates nothing.
# The clear's search ranks its candidates with this and search reports the
# winner with it, so the chosen delivery is the one the compete is told about.
func _concession(ctx: RoleContext, field: AICarrierField, spot: Vector3, our_goalie: Vector3,
		known_recovery: float = -1.0) -> Vector2:
	var recovery: float = known_recovery
	if recovery < 0.0:
		recovery = AIActionScoring.chase_recovery(
				spot, _chasers, field.opponents,
				_chaser_vels, field.opponent_vels)
	var loss: float = 1.0 - recovery
	var concede: float = field.turnover_cost(ctx, spot, loss, our_goalie)
	concede += field.counter_exposure_cost(ctx, spot, loss, ctx.self_pos, our_goalie)
	return Vector2(concede, recovery)


# Searches the last-resort dump into the result fields; `value` is -INF when no
# dump applies: the own-side neutral zone or the OZ, a delayed offside or an
# icing release, no legal clear, or no dump-in solution. The caller reads the
# value only as availability and for the debug label.
#
# The aim (a standoff down the launch line, where the stick points) and the
# settle (where the puck comes to rest) are DIFFERENT, and every term is priced
# at the settle. Both dumps are searched releases — see
# Scripts/domain/ai/CLAUDE.md → "Dumps are searched RELEASES":
#   DZ CLEAR — the legal launch we concede LEAST by; a pure concession.
#   NZ DUMP-IN — offensive, priced on the race to the resting spot; never icing,
#     since it is offered only past the red line.
func search(ctx: RoleContext, field: AICarrierField, our_goalie: Vector3) -> void:
	value = -INF
	var self_pos: Vector3 = ctx.self_pos
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	var defending_goal: Vector3 = ctx.defending_goal_pos
	var in_own_zone: bool = AIActionScoring.in_offensive_zone(self_pos, defending_goal)
	var past_center: bool = AIActionScoring.past_center_toward_attack(
			self_pos, attacking_goal)
	if not in_own_zone and not (past_center
			and not AIActionScoring.in_offensive_zone(self_pos, attacking_goal)):
		return

	var origin: Vector3 = AICarrierField.pass_origin(ctx)
	if not in_own_zone:
		# Icing reads the PUCK, which sits a stick off the body: a dump-in from a
		# body past centre can still leave from behind the red line. And with a
		# teammate owing a tag-up, a dumped puck is one nobody may touch.
		if ctx.zone_entry_blocked or (ctx.icing_enforced and InfractionRules.behind_red_line(
				origin.z, signf(attacking_goal.z))):
			return
	# Our chasers = teammates + ourselves (we dump and chase).
	_chasers.clear()
	_chaser_vels.clear()
	for i: int in field.our_defenders.size():
		_chasers.append(field.our_defenders[i])
		_chaser_vels.append(field.our_defender_vels[i])
	_chasers.append(self_pos)
	_chaser_vels.append(ctx.self_velocity)

	var launch: Vector3
	var rest: Vector3
	var soft: bool
	# (concede, recovery) for the delivery finally chosen.
	var priced := Vector2.ZERO
	if in_own_zone:
		# HIGH is doctrine, not a searched axis: the loft buys passage over the
		# sticks between us and the blue line, not time.
		soft = false
		var n: int = AIActionScoring.dump_clear_candidates(
				origin, -ctx.own_goal_dir, AIPuckLane.PASS_SPEED_M_S,
				ShotMechanics.ELEVATION_HIGH, defending_goal,
				_clear_vels, _clear_spots)
		if n == 0:
			# Every launch either ices or dies in our own zone: decline rather than
			# fire one.
			return
		# Rank the legal launches by concession, depth (nearness to their blue
		# line) only as the tie-break. The race runs first: every concession term
		# scales by the loss probability, so a certain recovery concedes exactly
		# zero — the best any clear can score — and once a free clear exists the
		# dearer ones are skipped unpriced (an exact prune).
		_clear_recovery.resize(n)
		var free_exists: bool = false
		for i: int in n:
			var rec: float = AIActionScoring.chase_recovery(
					_clear_spots[i], _chasers, field.opponents,
					_chaser_vels, field.opponent_vels)
			_clear_recovery[i] = rec
			free_exists = free_exists or rec >= 1.0
		var target_z: float = -ctx.own_goal_dir * GameRules.BLUE_LINE_Z
		var best_price: float = -INF
		var best_miss: float = INF
		for i: int in n:
			var rec: float = _clear_recovery[i]
			if free_exists and rec < 1.0:
				continue
			var spot: Vector3 = _clear_spots[i]
			var spot_priced := Vector2(0.0, rec)
			if rec < 1.0:
				spot_priced = _concession(ctx, field, spot, our_goalie, rec)
			var price: float = -spot_priced.x
			var miss: float = absf(spot.z - target_z)
			if price <= best_price - CLEAR_PRICE_TIE_BAND:
				continue
			if price < best_price + CLEAR_PRICE_TIE_BAND and miss >= best_miss:
				continue
			best_price = maxf(price, best_price)
			best_miss = miss
			launch = _clear_vels[i]
			rest = spot
			priced = spot_priced
	else:
		soft = true
		_landing[0] = origin
		# The pace ladder runs over the dumper's OWN release band, and the winning
		# pace must be carried out to the release (dump_launch_speed), or the
		# placement is lost.
		launch = AIActionScoring.solve_dump_in(
				origin, attacking_goal, ctx.self_wrister_shot_speed,
				ShotMechanics.ELEVATION_FLAT,
				_chasers, field.opponents, AICarrierField.goalie_now(ctx),
				_landing, _chaser_vels,
				field.opponent_vels)
		if launch == Vector3.ZERO:
			return
		rest = _landing[0]
		priced = _concession(ctx, field, rest, our_goalie)

	# Everything below prices the RESTING spot.
	var recovery: float = priced.y
	var concede: float = priced.x
	# Only the DUMP-IN earns a gain, for the race it is trying to win. The clear
	# stays a pure concession; its recovery race reaches it through `concede`.
	var gain: float = 0.0
	if soft:
		# MOMENTUM-HONEST chase clock; never `nearest_distance / max_speed`, an
		# instant full-speed sprint from a standstill. Nearest by ETA, not by
		# metres: the man already moving that way is the chaser even when someone
		# flat-footed stands closer.
		var chase_t: float = AIArrival.time_to_arrive(
				self_pos, rest, ctx.self_velocity, ctx.self_max_speed,
				ctx.self_max_accel, ctx.self_lateral_grip)
		for i: int in field.our_defenders.size():
			var mate_caps: AISkaterCaps = field.our_defender_caps[i]
			chase_t = minf(chase_t, AIArrival.time_to_arrive(
					field.our_defenders[i], rest, field.our_defender_vels[i],
					mate_caps.max_speed if mate_caps != null else ctx.self_max_speed,
					mate_caps.max_accel if mate_caps != null else ctx.self_max_accel))
		var chase_decay: float = AIActionScoring.delay_discount(chase_t)
		# The resting spot's potential is FUTURE value, so it pays the realization
		# discount like every other future-value read.
		gain = recovery * AIActionScoring.position_potential(
				rest, attacking_goal, field.opponents) * chase_decay \
				* AIActionScoring.potential_realization_discount(
						rest, attacking_goal)

	value = gain - concede
	# Down the launch line, not at the resting spot (see DUMP_AIM_STANDOFF_M).
	aim = origin + launch.normalized() * DUMP_AIM_STANDOFF_M
	is_soft = soft
	settle = rest
	launch_speed = launch.length()
