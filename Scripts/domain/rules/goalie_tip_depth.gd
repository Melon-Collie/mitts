class_name GoalieTipDepth

# How far out he can challenge a shooter with a stick waiting at the net front.
#
# A tip beats the read: the redirect's flight from a net-front blade is shorter
# than his read delay, so he cannot move after it and the only save is the body
# already being on the new line. And he does not get to move BEFORE it either —
# the shot is a shot until it is touched, and he is frozen reading it. So unlike
# the backdoor pass there is no race to run: what covers the tip is where he
# already stands.
#
# The geometry is the backdoor cap's. Standing on the goal→threat ray at radius
# `r`, he sits `r·sin θ` off the goal→tipper ray (θ between the two), so his body
# is still on the tip's line while
#     r · sin θ  <=  cover_half_width        =>     r <= cover / sin θ
# Challenging a point shot further out than that buys angle on a shot he can
# react to from range and sells the redirect he cannot. It is the A-vs-B call
# made from what he can see: A for a clean look, less for traffic.
#
# Returns INF when nothing binds: a stick he could still react to, one on the
# shooter's own line (challenging the shooter covers it), one his defenceman
# ties up before the shot gets there, or one not between the shooter and the net.

static func tip_cap(threat: Vector3, tipper: Vector3, goal_line_z: float,
		goal_center_x: float, direction_sign: int, cover_half_width: float,
		max_tip_distance: float, shot_speed: float,
		defender_arrival_time: float) -> float:
	if (tipper.z - goal_line_z) * direction_sign <= 0.0:
		return INF
	var kx: float = tipper.x - goal_center_x
	var kz: float = tipper.z - goal_line_z
	var tip_dist: float = sqrt(kx * kx + kz * kz)
	if tip_dist > max_tip_distance or tip_dist < 0.001:
		return INF
	var tx: float = threat.x - goal_center_x
	var tz: float = threat.z - goal_line_z
	var threat_dist: float = sqrt(tx * tx + tz * tz)
	if threat_dist <= tip_dist:
		return INF
	var sx: float = threat.x - tipper.x
	var sz: float = threat.z - tipper.z
	if defender_arrival_time <= sqrt(sx * sx + sz * sz) / maxf(shot_speed, 0.001):
		return INF
	var sin_theta: float = absf((tx * kz - tz * kx) / (threat_dist * tip_dist))
	if sin_theta < 0.01:
		return INF
	return cover_half_width / sin_theta
