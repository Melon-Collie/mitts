class_name AITipPoint

# Where a man tips a shot coming at him: the one solve the tipper plays
# (AIRoleFinisher's reactive tip) and the shooter prices (AIActionScoring.tip_ev).
# All in the ice plane; times from the puck's position now.

# The most a deliberate tip turns the puck (Puck.deflect_max_turn_deg, held by
# test_bot_mirrors.gd), with the blade square beside the body.
const MAX_TURN_RAD: float = deg_to_rad(25.0)
# How far out from the body the tipper's blade sits: the ring the agent's FACE
# cursor snaps to (AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M), so standing this
# far back of the tip point along the blade's bearing puts the blade on it.
const BLADE_OUT_M: float = AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M


# When the puck (at `puck_pos`, `puck_vel`) is tipped by a man at `me` skating
# `me_vel`, NAN if he cannot tip it. The tip point is where the puck's path
# comes nearest his blade in his own frame, the body BLADE_OUT_M back of it
# along the bearing, so that standing there he reads the same point; else, when
# his stick cannot be there in time, where it comes nearest his body, the stick
# reached out to it. Never where it crosses his z-plane: a rip across the slot
# crosses it metres to his side while passing in reach.
static func meet_time(puck_pos: Vector3, puck_vel: Vector3, me: Vector3, me_vel: Vector3,
		max_speed: float, max_accel: float, blade_reach: float, opp_goal_z: float) -> float:
	var t: float = _candidate(puck_pos, puck_vel, me, me_vel, max_speed, max_accel, blade_reach,
			opp_goal_z, BLADE_OUT_M)
	if is_nan(t):
		t = _candidate(puck_pos, puck_vel, me, me_vel, max_speed, max_accel, blade_reach,
				opp_goal_z, 0.0)
	return t


# The body→blade bearing that tips a puck travelling `travel` at `tip` toward the
# middle of the net, as far as a tip turns: PuckCollisionRules.tip_turn turns it
# by MAX_TURN_RAD × the cross of the puck's travel with this bearing.
static func bearing(travel: Vector2, tip: Vector2, opp_goal_z: float) -> Vector2:
	var turn: float = clampf(travel.angle_to(Vector2(0.0, opp_goal_z) - tip),
			-MAX_TURN_RAD, MAX_TURN_RAD)
	return (-travel).rotated(-asin(turn / MAX_TURN_RAD))


# When the puck's path meets his blade held `blade_out` up the tip's bearing in
# his frame, if he can tip it there; NAN if not. The tip holds until the puck is
# past that point in his frame by the blade's catch radius
# (AIPuckLane.LANE_BLADE_CATCH_M): dropped at the meet, the deflect is let go on
# the contact.
static func _candidate(puck_pos: Vector3, puck_vel: Vector3, me: Vector3, me_vel: Vector3,
		max_speed: float, max_accel: float, blade_reach: float, opp_goal_z: float,
		blade_out: float) -> float:
	var pv := Vector2(puck_vel.x, puck_vel.z)
	var speed: float = pv.length()
	var rel_v := Vector2(puck_vel.x - me_vel.x, puck_vel.z - me_vel.z)
	var w2: float = rel_v.length_squared()
	if speed < 0.001 or w2 < 0.000001 or absf(puck_vel.z) < 0.001:
		return NAN
	var travel: Vector2 = pv / speed
	var puck_at := Vector2(puck_pos.x, puck_pos.z)
	var me2 := Vector2(me.x, me.z)
	var t: float = (me2 - puck_at).dot(rel_v) / w2
	if blade_out > 0.0:
		# Re-read from the bearing the first read gives, then from its own.
		for _pass: int in 2:
			t = (me2 + bearing(travel, puck_at + pv * t, opp_goal_z) * blade_out - puck_at).dot(
					rel_v) / w2
	if t < -AIPuckLane.LANE_BLADE_CATCH_M / sqrt(w2) or t > 2.0:
		return NAN
	var tip: Vector2 = puck_at + pv * t
	if (opp_goal_z - tip.y) * puck_vel.z <= 0.0:
		return NAN
	# A tip turns the puck at most MAX_TURN_RAD, so a shot is tipped when that
	# reaches the mouth from the tip point: on net already, or wide by no more
	# than that. A shot wider than a tip can bring back, or a teammate's pass
	# running at the net, is left alone.
	var mouth: float = GameRules.NET_ENTRY_HALF_WIDTH
	var x_at_goal: float = puck_pos.x + puck_vel.x * ((opp_goal_z - puck_pos.z) / puck_vel.z)
	if absf(x_at_goal) > mouth and absf(travel.angle_to(
			Vector2(signf(x_at_goal) * mouth, opp_goal_z) - tip)) > MAX_TURN_RAD:
		return NAN
	# A shot he can hold is received, not tipped: only one arriving in his frame
	# faster than he holds a catch on the line goes off the face.
	var tip3 := Vector3(tip.x, 0.0, tip.y)
	if AIFeedReception.arrival_closing_speed(puck_pos, tip3, speed, me_vel) \
			<= AIFeedReception.RECEIVE_HOLD_CEILING_M_S:
		return NAN
	# A tip his blade cannot be on before the puck gets there, stick out, is no
	# tip: the crash is his play instead.
	if AIArrival.reach_eta(me, tip3, me_vel, max_speed, max_accel, blade_reach) > maxf(t, 0.0):
		return NAN
	return t
