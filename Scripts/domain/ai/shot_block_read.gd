class_name AIShotBlockRead
extends RefCounted

# Whether a defender gets in front of a shot, standing or in a dive. Everything
# here is something a defender sees: where the shooter is releasing from, that he
# is winding up, the loft he has dialled (replicated, a goalie reads the same
# tell), where his own goalie stands, and how far a pass has to travel.

# The standing block's cylinder: Skater.block_body_radius and block_seal_height
# (test_shot_block_read.gd holds the pair).
const BLOCK_RADIUS_M: float = 0.9
const BLOCK_SEAL_HEIGHT_M: float = 1.45
# A block this close to the shooter is a body on his stick, not a block.
const MIN_FROM_RELEASE_M: float = 1.0
# The carrier is inside shooting range below the tops of our circles: the
# defensive-zone dots plus the 4.57 m circle radius.
const SHOOTING_RANGE_Z: float = GameRules.ICING_FACEOFF_DOT_Z - 4.572


# Our body is on the line from the release to the middle of our net, between
# them and clear of the shooter's stick.
static func in_lane(self_pos: Vector3, release: Vector3, goal_center: Vector3) -> bool:
	var a := Vector2(release.x, release.z)
	var b := Vector2(goal_center.x, goal_center.z)
	var p := Vector2(self_pos.x, self_pos.z)
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 1e-6:
		return false
	var t: float = (p - a).dot(ab) / len_sq
	if t <= 0.0 or t >= 1.0 or (p - a).length() < MIN_FROM_RELEASE_M:
		return false
	return (a + ab * t).distance_to(p) <= BLOCK_RADIUS_M


# How high the shot is at `dist` from the release: the loft rung's launch angle
# (the league ladder, not the shooter's own) under gravity at `speed`.
static func shot_height_at(dist: float, elevation_level: int, speed: float) -> float:
	var tan_a: float = 0.0
	match elevation_level:
		ShotMechanics.ELEVATION_LOW:
			tan_a = GameRules.DEFAULT_LOFT_TAN_LOW
		ShotMechanics.ELEVATION_MID:
			tan_a = GameRules.DEFAULT_LOFT_TAN_MID
		ShotMechanics.ELEVATION_HIGH:
			tan_a = GameRules.DEFAULT_LOFT_TAN_HIGH
	if tan_a == 0.0:
		return 0.0
	var t: float = dist / maxf(speed, 0.1)
	return maxf(dist * tan_a - 0.5 * GameRules.GRAVITY_M_S2 * t * t, 0.0)


# The block owns the ice and concedes the air: worth it only for a shot still
# under the seal when it reaches us.
static func stays_low(self_pos: Vector3, release: Vector3, elevation_level: int,
		speed: float) -> bool:
	var dist: float = Vector2(self_pos.x - release.x, self_pos.z - release.z).length()
	return shot_height_at(dist, elevation_level, speed) < BLOCK_SEAL_HEIGHT_M


# A block close enough in front of our goalie that it fills his view
# (a body on his own eyes, plus the body's own half-width): what
# gets past it is a puck he never saw, where without us he would have looked
# around us and made the save.
static func screens_own_goalie(self_pos: Vector3, goalie_pos: Vector3,
		cfg: GoalieScreenRules.ScreenConfig) -> bool:
	var reach: float = cfg.min_along + cfg.peek_clearance + cfg.torso_half_width
	return Vector2(self_pos.x - goalie_pos.x, self_pos.z - goalie_pos.z).length() < reach


# A shot already off the stick is coming through us: moving at us and its line
# passes within the block.
static func puck_coming_through(self_pos: Vector3, puck_pos: Vector3,
		puck_vel: Vector3) -> bool:
	var v := Vector2(puck_vel.x, puck_vel.z)
	var to_me := Vector2(self_pos.x - puck_pos.x, self_pos.z - puck_pos.z)
	var speed_sq: float = v.length_squared()
	if speed_sq < 1.0 or to_me.dot(v) <= 0.0:
		return false
	var along: float = to_me.dot(v) / speed_sq
	return (to_me - v * along).length() <= BLOCK_RADIUS_M


# Where a 2-on-1 defender dives to take away the pass from `carrier` to
# `receiver`, or INF when he should not: the lane is past what he can reach on
# his feet before the pass gets there, and inside what the dive lays across
# (DiveRules.reach_m()). Standing he has his stick plus what he can skate
# toward the lane while the pass travels to it, from rest across it.
static func dive_point(self_pos: Vector3, self_vel: Vector3, carrier: Vector3,
		receiver: Vector3, stick_reach: float, accel: float, pass_speed: float) -> Vector3:
	var a := Vector2(carrier.x, carrier.z)
	var ab := Vector2(receiver.x, receiver.z) - a
	var len_sq: float = ab.length_squared()
	if len_sq < 1e-6:
		return Vector3.INF
	var p := Vector2(self_pos.x, self_pos.z)
	var t: float = (p - a).dot(ab) / len_sq
	if t <= 0.0 or t >= 1.0:
		return Vector3.INF
	var q: Vector2 = a + ab * t
	var to_lane: Vector2 = q - p
	var d: float = to_lane.length()
	if d > DiveRules.reach_m():
		return Vector3.INF
	var t_pass: float = (q - a).length() / maxf(pass_speed, 0.1)
	var closing: float = 0.0 if d < 1e-4 \
			else maxf(Vector2(self_vel.x, self_vel.z).dot(to_lane / d), 0.0)
	var standing: float = stick_reach + closing * t_pass + 0.5 * accel * t_pass * t_pass
	if d <= standing:
		return Vector3.INF
	return Vector3(q.x, 0.0, q.y)
