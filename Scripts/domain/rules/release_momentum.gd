class_name ReleaseMomentum

# A released puck keeps the skater's motion: its velocity is the skater's plus
# the blade's push. The shooter aims at the target, so the hands push partly
# against the motion across the aim to keep the puck on it, and that correction
# comes out of the push. While the push can cancel the cross motion the puck
# goes exactly along the aim; past it the rest drifts. A blade can always leave
# the puck behind, so the pace along the aim never goes negative.
#
# Momentum is horizontal. A shot keeps the blade's launch angle (the loft
# ladder's set angles), so its vertical scales with the horizontal pace. A pass
# keeps its vertical launch speed (the saucer and flip are calibrated in it),
# no steeper than the host's direction check allows.
# docs/release-momentum-plan.md.

# The steepest legal direction's rise over run (ShotReleaseRules.MAX_DIRECTION_Y),
# a hair inside it so the host's check never moves a release that sits on it.
const _MAX_LOFT_TAN: float = 0.999 * ShotReleaseRules.MAX_DIRECTION_Y \
		/ sqrt(1.0 - ShotReleaseRules.MAX_DIRECTION_Y * ShotReleaseRules.MAX_DIRECTION_Y)


# The release velocity for a push of `power` along `direction` (the standing
# release, loft included) from a body moving at `skater_velocity` (only its XZ
# counts). `keep_vertical_speed` is a pass's loft rule, else a shot's. Returns
# the velocity; direction × power when the aim has no horizontal part.
static func release_velocity(direction: Vector3, power: float,
		skater_velocity: Vector3, keep_vertical_speed: bool = false) -> Vector3:
	var d := Vector2(direction.x, direction.z)
	var d_len: float = d.length()
	if d_len < 0.0001:
		return direction * power
	var loft_tan: float = direction.y / d_len
	var push_h: float = power * d_len / direction.length()
	d /= d_len
	var v := Vector2(skater_velocity.x, skater_velocity.z)
	var v_par: float = v.dot(d)
	var v_perp: Vector2 = v - d * v_par
	var perp_len: float = v_perp.length()
	var cancel: float = minf(push_h, perp_len)
	var along: float = maxf(v_par + sqrt(maxf(push_h * push_h - cancel * cancel, 0.0)), 0.0)
	var drift: Vector2 = v_perp * (1.0 - cancel / perp_len) if perp_len > 0.0001 else Vector2.ZERO
	var h: Vector2 = d * along + drift
	var vertical: float = h.length() * loft_tan
	if keep_vertical_speed:
		vertical = minf(power * direction.y / direction.length(), h.length() * _MAX_LOFT_TAN)
	return Vector3(h.x, vertical, h.y)


# The horizontal push a release needs for a pace of `pace` along the unit XZ
# `aim_dir` from a body moving at `skater_velocity`: the inverse of
# release_velocity where the push can cancel the cross motion. 0 when the body's
# own motion already carries the puck at that pace or more.
static func push_for_pace(pace: float, aim_dir: Vector2, skater_velocity: Vector3) -> float:
	var v := Vector2(skater_velocity.x, skater_velocity.z)
	var v_par: float = v.dot(aim_dir)
	var perp_sq: float = maxf(v.length_squared() - v_par * v_par, 0.0)
	if pace <= v_par:
		return 0.0
	return sqrt((pace - v_par) * (pace - v_par) + perp_sq)


# The softest push a release along `direction` (loft included) can be asked for,
# when the softest a standing release goes is `min_push`: the push that lands that
# same pace on the ice from a body moving at `skater_velocity`, never more than
# `min_push`. A blade can always take pace off a puck, so skating at the target
# softens the floor; it cannot add pace without a harder push, so skating away
# leaves it where it is.
static func floor_push(min_push: float, direction: Vector3, skater_velocity: Vector3) -> float:
	var d := Vector2(direction.x, direction.z)
	var d_len: float = d.length()
	if d_len < 0.0001:
		return min_push
	var cos_loft: float = d_len / direction.length()
	var pace: float = min_push * cos_loft
	return minf(min_push, push_for_pace(pace, d / d_len, skater_velocity) / cos_loft)
