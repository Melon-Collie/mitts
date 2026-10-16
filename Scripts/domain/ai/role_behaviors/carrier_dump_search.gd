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

# Launch bearings tried per dump-in, as offsets from the aim axis. Spread wide
# enough to include the steep bank into the near boards, and dense enough that
# the corner it wraps into is resolved. Each bearing is one closed-form landing
# solve.
const DUMP_SEARCH_BEARINGS_RAD: Array = [
	-1.20, -0.90, -0.60, -0.30, 0.0, 0.30, 0.60, 0.90, 1.20,
]

# Launch PACES tried per bearing on the dump-IN, as fractions of the release
# band between the soft-touch floor (DEFAULT_WRISTER_POWER_MIN_M_S) and the pace
# the dumper can produce. Bearing alone cannot place a dump: every pace the bot
# can make out-slides the rink several times over, so where it stops is set by
# what the boards take out of it.
#
# Spaced toward the SOFT end, because runout goes as v² and the metre-scale
# placement lives in the first few m/s above the floor. Full pace stays as the
# last rung: a hard rim around the boards can genuinely beat a defender to the
# corner.
const DUMP_SEARCH_PACE_FRACS: Array = [0.0, 0.18, 0.45, 1.0]

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
# Where the dump-in landing solve leaves its resting spot.
var _landing: Array[Vector3] = [Vector3.ZERO]
# The landing solve's candidates, index-matched: launch, resting spot, our first
# arrival there, the race to it.
var _cand_vel: Array[Vector3] = []
var _cand_spot: Array[Vector3] = []
var _cand_t: Array[float] = []
var _cand_race: Array[float] = []


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
	var concede: float = _field.turnover_cost(spot, loss)
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
	var launch: Vector3 = _solve_dump_in(origin, attacking_goal, ctx.self_wrister_shot_speed,
			AICarrierField.goalie_now(ctx))
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
	var gain: float = priced.y * _field.our_possession_at(rest, chase_t)

	value = gain - priced.x
	# Down the launch line, not at the resting spot (see DUMP_AIM_STANDOFF_M).
	aim = origin + launch.normalized() * DUMP_AIM_STANDOFF_M
	settle = rest
	launch_speed = launch.length()


# The NZ dump-in: search launches — BEARING x PACE — and take the one whose
# RESTING spot is worth most to win: the race there × our possession of it, our
# first man there when he arrives. Leaves the spot in _landing[0]; the returned
# velocity's LENGTH is the pace that won, which the release then has to actually
# fire at. `max_launch_speed` bounds the pace ladder (the top of the dumper's own
# release band). No icing branch: this dump is only offered past the red line,
# and icing requires a release from our own half.
#
# Every landing is raced first and priced best race first: possession is at most
# 1, so once a spot is worth more than the next race, nothing after it can win
# (exact).
func _solve_dump_in(origin: Vector3, attacking_goal: Vector3, max_launch_speed: float,
		keeper_pos: Vector3) -> Vector3:
	var goal_dir: float = signf(attacking_goal.z)
	var axis := Vector3(0.0, 0.0, goal_dir)
	var floor_speed: float = GameRules.DEFAULT_WRISTER_POWER_MIN_M_S
	var band: float = maxf(max_launch_speed - floor_speed, 0.0)
	_cand_vel.clear()
	_cand_spot.clear()
	_cand_t.clear()
	_cand_race.clear()
	for offset: float in DUMP_SEARCH_BEARINGS_RAD:
		var dir: Vector3 = axis.rotated(Vector3.UP, offset)
		for frac: float in DUMP_SEARCH_PACE_FRACS:
			var vel: Vector3 = dir * (floor_speed + band * frac)
			var spot: Vector3 = AITrajectory.puck_release_landing(origin, vel)
			# A dump-in that does not get the puck deeper than we already are is
			# not a dump-in; it is a giveaway in the neutral zone.
			if goal_dir * (spot.z - origin.z) <= 0.0:
				continue
			if AIActionScoring.keeper_collects_first(spot, keeper_pos, _chasers,
					AIArrival.SKATER_REF_SPEED_M_S):
				continue
			var our_t: float = AIActionScoring.first_arrival(spot, _chasers, _chaser_vels)
			_cand_vel.append(vel)
			_cand_spot.append(spot)
			_cand_t.append(our_t)
			_cand_race.append(AIActionScoring.arrival_race(
					spot, our_t, _field.opponents, _field.opponent_vels))
	var best_vel: Vector3 = Vector3.ZERO
	var best_score: float = -INF
	var best_spot: Vector3 = origin
	while true:
		var k: int = -1
		var race: float = -INF
		for i: int in _cand_race.size():
			if _cand_race[i] > race:
				race = _cand_race[i]
				k = i
		if k == -1 or race <= best_score:
			break
		_cand_race[k] = -INF
		var score: float = race * _field.our_possession_at(_cand_spot[k], _cand_t[k])
		if score > best_score:
			best_score = score
			best_spot = _cand_spot[k]
			best_vel = _cand_vel[k]
	_landing[0] = best_spot
	return best_vel
