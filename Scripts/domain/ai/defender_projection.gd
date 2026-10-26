class_name AIDefenderProjection
extends RefCounted

# Where a defender will be, for the reads that price a carry, a feed or an entry
# against the defence as it will stand rather than as it stands now.

# at()'s other result: the projected man's velocity.
static var vel_then: Vector3 = Vector3.ZERO


# Where a defender at `pos` skating at `vel`, built as `caps` (null: the league
# build), is `t` from now, against a carrier now at `carrier_now` and at
# `carrier_then` `t` from now, attacking the net at `goal`. Ahead of the carrier
# means goal-side of him along his line to that net (a man level in depth but in
# the middle is between a wide carrier and the net):
#
#   ahead, not closing on him, outside the carrier's own zone — standing up at
#     his line or backing off the carry: he holds his gap, giving ground down
#     the carrier's line as the carrier gains it — a carrier who waits gains no
#     ice by it — down to the top of his house, the floor a defender with a gap
#     retreats to (AIRoleRushD.set_retreat_floor), as far as his skate gets him
#     there;
#   ahead otherwise — closing on him, or forechecking in the carrier's own zone,
#     where he holds his ice: he carries on as he is until he is level with the
#     carrier on that line, and is behind him from then;
#   behind him — he backchecks (_backcheck).
#
# His velocity then is left in vel_then.
static func at(pos: Vector3, vel: Vector3, t: float, carrier_now: Vector3,
		carrier_then: Vector3, goal: Vector3, caps: AISkaterCaps = null) -> Vector3:
	vel_then = vel
	if t <= 0.0:
		return pos
	var d: Vector3 = _line_to(carrier_now, goal)
	var ahead: float = (pos.x - carrier_now.x) * d.x + (pos.z - carrier_now.z) * d.z
	if ahead > 0.0:
		var toward: float = vel.x * d.x + vel.z * d.z
		if toward >= 0.0 and not AIActionScoring.in_offensive_zone(
				pos, Vector3(0.0, 0.0, -goal.z)):
			return _hold_gap(pos, vel, t, carrier_now, carrier_then, goal, caps)
		var t_level: float = ahead / -toward if toward < 0.0 else INF
		if t <= t_level:
			return AITrajectory.predict_at(pos, vel, t)
		pos = pos + vel * t_level
		t -= t_level
	return _backcheck(pos, vel, t, goal.z, caps)


# The unit direction from `from` to `goal` on the ice.
static func _line_to(from: Vector3, goal: Vector3) -> Vector3:
	var line := Vector3(goal.x - from.x, 0.0, goal.z - from.z)
	var line_len: float = line.length()
	return line / line_len if line_len > 0.001 else Vector3(0.0, 0.0, signf(goal.z))


# at()'s gap-holder: he gives ground down the carrier's line as the
# carrier gains it, from `carrier_now` to `carrier_then` over `t` (and closes as
# the carrier gives it), keeping his place across the ice, no deeper than the top
# of the house, as far as his skate from `pos` gets him there.
static func _hold_gap(pos: Vector3, vel: Vector3, t: float, carrier_now: Vector3,
		carrier_then: Vector3, goal: Vector3, caps: AISkaterCaps) -> Vector3:
	var d: Vector3 = _line_to(carrier_now, goal)
	var gained: float = (carrier_then.x - carrier_now.x) * d.x \
			+ (carrier_then.z - carrier_now.z) * d.z
	var stand: Vector3 = pos + d * gained
	var sign_z: float = signf(goal.z)
	var gate_z: float = goal.z - sign_z * AIZoneCoverage.HOUSE_TOP_DEPTH_M
	var past: float = (stand.z - gate_z) * sign_z
	if past > 0.0 and absf(d.z) > 0.001:
		stand -= d * minf(past / absf(d.z), maxf(gained, 0.0))
	var carrier_vel: Vector3 = (carrier_then - carrier_now) / t
	var t_stand: float = AIArrival.time_to_arrive_caps(pos, stand, vel, caps)
	if t_stand <= t:
		vel_then = Vector3(carrier_vel.x, 0.0, carrier_vel.z)
		return stand
	vel_then = (stand - pos) / t_stand
	return pos.lerp(stand, t / t_stand)




# A man behind the play `t` from now: he brakes out what speed he has away from
# home, the rest carrying on, then skates for the top of his house on the
# arrival clock, the share of the trip he has made by then along the way.
static func _backcheck(pos: Vector3, vel: Vector3, t: float, goal_z: float,
		caps: AISkaterCaps) -> Vector3:
	var home := Vector3(0.0, 0.0, goal_z - signf(goal_z) * AIZoneCoverage.HOUSE_TOP_DEPTH_M)
	var to_home := Vector3(home.x - pos.x, 0.0, home.z - pos.z)
	var dist: float = to_home.length()
	if dist < 0.01:
		vel_then = Vector3.ZERO
		return home
	var h: Vector3 = to_home / dist
	var away: float = maxf(0.0, -(vel.x * h.x + vel.z * h.z))
	var brake: float = AIArrival.REVERSAL_BRAKE_DECEL_M_S2
	var t_shed: float = minf(t, away / brake)
	var v_rest: Vector3 = Vector3(vel.x, 0.0, vel.z) + h * away
	var m: Vector3 = pos + v_rest * t_shed - h * (away * t_shed - 0.5 * brake * t_shed * t_shed)
	var rest: float = t - t_shed
	if rest <= 0.0:
		vel_then = v_rest - h * (away - brake * t_shed)
		return m
	var t_home: float = AIArrival.time_to_arrive_caps(m, home, v_rest, caps)
	if t_home <= rest:
		vel_then = Vector3.ZERO
		return home
	vel_then = (home - m) / t_home
	return m.lerp(home, rest / t_home)
