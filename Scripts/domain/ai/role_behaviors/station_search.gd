class_name AIStationSearch

# How a role searches for its spot: the candidate ring around a station, the
# legality and anti-crowd filters, and the switch hysteresis that keeps an
# argmax from flickering between near-ties. A role's own differentiator is its
# scoring function; this is the sampling it scores.


# Polar candidate ring radius. A sampling parameter, not a behavioral knob.
const SEARCH_STEP_M: float = 3.0


# Candidates this close to a teammate are filtered out: the physical-overlap
# distance, at blade-reach scale.
const ANTI_CROWD_RADIUS_M: float = 1.8


# Beyond this distance from a role's analytic station center, sampled roles skate
# at the calculated station instead of running the argmax: the ring spans
# ±SEARCH_STEP_M, so from three ring-radii out the heading to "center" vs
# "refined spot" differs by under ~20°, and the role re-refines from closer.
const STATION_ARGMAX_LOD_M: float = SEARCH_STEP_M * 3.0


# True when the bot is close enough to its station center that the
# candidate argmax's refinement affects the path it actually skates.
static func station_needs_refinement(self_pos: Vector3, center: Vector3) -> bool:
	return self_pos.distance_squared_to(center) \
			< STATION_ARGMAX_LOD_M * STATION_ARGMAX_LOD_M


# Margins inside the boards / goal lines that a legal candidate keeps.
const RINK_INSET_M: float = 0.5


const GOAL_LINE_BUFFER_M: float = 1.0


# Pre-baked rotations for the 8 polar cardinal candidates.
const POLAR_ANGLES: Array[float] = [
		0.0, PI * 0.25, PI * 0.5, PI * 0.75,
		PI, -PI * 0.75, -PI * 0.5, -PI * 0.25,
]


# The standard 10-candidate set: `center`, `self_pos` (stand still), and 8 polar
# samples around `center` at SEARCH_STEP_M.
#
# `with_inner_ring` adds 8 more at half step, so an argmax whose pick is steered
# on directly every dispatch (PRESSURE) can make small corrections instead of
# jumping in SEARCH_STEP_M quanta.
static func generate_candidates_around(self_pos: Vector3,
		center: Vector3, with_inner_ring: bool = false) -> Array[Vector3]:
	var result: Array[Vector3] = []
	result.append(center)
	result.append(self_pos)
	for angle: float in POLAR_ANGLES:
		result.append(Vector3(
				center.x + SEARCH_STEP_M * cos(angle),
				0.0,
				center.z + SEARCH_STEP_M * sin(angle)))
	if with_inner_ring:
		var inner: float = SEARCH_STEP_M * 0.5
		for angle: float in POLAR_ANGLES:
			result.append(Vector3(
					center.x + inner * cos(angle),
					0.0,
					center.z + inner * sin(angle)))
	return result


# Rejects candidates outside the playable rink, in either crease, or past either
# goal line.
static func is_legal_position(c: Vector3) -> bool:
	if absf(c.x) > GameRules.RINK_HALF_WIDTH - RINK_INSET_M:
		return false
	if absf(c.z) > GameRules.GOAL_LINE_Z - GOAL_LINE_BUFFER_M:
		return false
	if CreaseRules.is_in_crease(Vector2(c.x, c.z)):
		return false
	return true


# `teammate_positions` must exclude self (AIRoleReads.collect_teammates_excluding_self).
static func too_close_to_teammate(c: Vector3,
		teammate_positions: Array[Vector3]) -> bool:
	var r2: float = ANTI_CROWD_RADIUS_M * ANTI_CROWD_RADIUS_M
	for tp: Vector3 in teammate_positions:
		var dx: float = c.x - tp.x
		var dz: float = c.z - tp.z
		if dx * dx + dz * dz < r2:
			return true
	return false


# ── What a spot adds to the attack ───────────────────────────────────────────
# Two attackers closer than this are one option to the defence: a defender
# standing between them gets his stick to a feed to either.
const ONE_DEFENDER_SPAN_M: float = 2.0 * AIBotMechanics.BLADE_REACH_M

# Off-puck teammates' feed values, refilled by fill_feed_values (one worker).
static var _mate_values: Array[float] = []


# The one-timer off our carrier's feed at each of `teammates` (0 for the
# carrier himself), into this file's scratch for shared_cover.
static func fill_feed_values(ctx: RoleContext, carrier_pos: Vector3,
		goalie_pos: Vector3, opp_positions: Array[Vector3],
		teammates: Array[Vector3]) -> void:
	_mate_values.clear()
	for t: Vector3 in teammates:
		if Vector2(t.x - carrier_pos.x, t.z - carrier_pos.z).length() < 0.5:
			_mate_values.append(0.0)
			continue
		_mate_values.append(AIActionScoring.score_pass_value(carrier_pos, t,
				ctx.attacking_goal_pos, goalie_pos, opp_positions,
				AIPuckLane.expected_pass_speed(carrier_pos, t), ctx.scratch_opp_caps, true))


# The best feed value (fill_feed_values) of a teammate within ONE_DEFENDER_SPAN_M
# of `c`: what the carrier already has in the option a spot at `c` would share
# with him. A spot is worth its own value less this. 0 with nobody in reach.
static func shared_cover(c: Vector3, teammates: Array[Vector3]) -> float:
	var r2: float = ONE_DEFENDER_SPAN_M * ONE_DEFENDER_SPAN_M
	var best: float = 0.0
	for i: int in mini(teammates.size(), _mate_values.size()):
		var dx: float = c.x - teammates[i].x
		var dz: float = c.z - teammates[i].z
		if dx * dx + dz * dz < r2:
			best = maxf(best, _mate_values[i])
	return best


# Our shots a body in front of their keeper could screen, refilled by
# fill_screen_plays (one worker): each one's release, the keeper square on it,
# and the odds it is taken and saved. The carrier's own is his miss; a
# teammate's is the lane to him times his one-timer's miss off the feed.
static var _play_release: Array[Vector3] = []
static var _play_keeper: Array[Vector3] = []
static var _play_weight: Array[float] = []
static var _screen_cfg := GoalieScreenRules.ScreenConfig.new()
static var _no_vels: Array[Vector3] = []


# The shots a screen could help: our carrier's from where he stands, the keeper
# as he is, and each of `teammates` off a feed to him, the keeper square on him.
static func fill_screen_plays(ctx: RoleContext, carrier_pos: Vector3,
		goalie_pos: Vector3, opp_positions: Array[Vector3],
		teammates: Array[Vector3]) -> void:
	_play_release.clear()
	_play_keeper.clear()
	_play_weight.clear()
	var goal: Vector3 = ctx.attacking_goal_pos
	var release: Vector3 = AIPuckLane.release_point_toward(carrier_pos, goal)
	_play_release.append(release)
	_play_keeper.append(goalie_pos if goalie_pos.is_finite() else _keeper_square_on(goal, release))
	_play_weight.append(1.0 - AIShotValue.set_keeper(release, goal))
	for t: Vector3 in teammates:
		if Vector2(t.x - carrier_pos.x, t.z - carrier_pos.z).length() < 0.5 \
				or (t.z - goal.z) * signf(goal.z) >= 0.0:
			continue
		var speed: float = AIPuckLane.expected_pass_speed(carrier_pos, t)
		var lane: float = AIPuckLane.lane_clear(carrier_pos, t, opp_positions, speed, _no_vels,
				ctx.scratch_opp_caps)
		if lane <= 0.0:
			continue
		_play_release.append(t)
		_play_keeper.append(_keeper_square_on(goal, t))
		_play_weight.append(lane * (1.0 - AIShotValue.feed(carrier_pos, t, speed, goal,
				goalie_pos, true)))


# Where a screener stands for each play (fill_screen_plays): on its release's
# line to the net, as far out as the screen field measured a body worth most.
static func append_screen_stations(ctx: RoleContext, candidates: Array[Vector3]) -> void:
	var goal: Vector3 = ctx.attacking_goal_pos
	for i: int in _play_release.size():
		var along: float = AIScreenField.best_station_along(_play_release[i], goal)
		var line: Vector3 = _play_release[i] - goal
		line.y = 0.0
		if is_finite(along) and line.length() > along:
			candidates.append(goal + line * (along / line.length()))


# What a body at `c` adds to our attack by screening (fill_screen_plays): the
# best of the plays it hides, one puck being one shot.
static func screen_value(ctx: RoleContext, c: Vector3) -> float:
	var best: float = 0.0
	for i: int in _play_release.size():
		best = maxf(best, _play_weight[i] * AIScreenField.uplift(_play_release[i],
				ctx.attacking_goal_pos, _play_keeper[i], c, _screen_cfg))
	return best


# Where their keeper stands set for a shot from `release` (AIGoalieModel
# .keeper_depth along its line); in his net for one behind the goal line.
static func _keeper_square_on(goal: Vector3, release: Vector3) -> Vector3:
	var forward: float = (release.z - goal.z) * -signf(goal.z)
	var depth: float = AIGoalieModel.keeper_depth(goal, release)
	if not is_finite(depth):
		return goal
	var at: Vector3 = goal + (release - goal) * (depth / forward)
	at.y = 0.0
	return at


# ── Target switch-hysteresis ─────────────────────────────────────────────────
#
# Along an argmax's tie ridge two spots trade the lead on noise, and the off-puck
# cursor SNAPS to the role target, so a per-dispatch hop whips the blade. The
# incumbent (ctx.prev_role_target) is injected as one extra candidate and scored
# by the role's own scoring and filters — so an illegal or crowded incumbent is
# dropped rather than camped — plus this bonus.
#
# In threat-surface units (the 0..1 currency of score_shoot / score_pass). Feel
# tunable: raise toward 0.08 if a role wobbles between spots, lower toward 0.02
# if it camps a stale one.
const TARGET_SWITCH_MARGIN: float = 0.04


# No-op when there is no incumbent. Pair with incumbent_bonus in the scoring loop.
static func append_incumbent(ctx: RoleContext, candidates: Array[Vector3]) -> void:
	if ctx.prev_role_target.is_finite():
		candidates.append(ctx.prev_role_target)


# Add to the role's own score inside its argmax. Exact equality is safe: the
# incumbent is the same Vector3 append_incumbent injected.
static func incumbent_bonus(ctx: RoleContext, c: Vector3) -> float:
	if ctx.prev_role_target.is_finite() and c == ctx.prev_role_target:
		return TARGET_SWITCH_MARGIN
	return 0.0
