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
