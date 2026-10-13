class_name WristerLoad

# How much of a wrist shot the torso can put into the puck, from where the puck
# sits off the body and which way it is aimed. Two factors, multiplied:
#
#   ALIGNMENT — turning the torso carries the puck AROUND the body, so it drives
#   the puck along the tangent at the puck's bearing. A shot along that tangent
#   takes all of it; one straight out from the body, or back through it, takes
#   none. Which sense of the tangent the shot follows is the hand: a forehand
#   sweeps from the stick side across the front, a backhand the other way.
#
#   COIL — the blade is frozen on the puck while the torso winds up, so the
#   torso can only turn through the yaws that keep the puck inside that hand's
#   reach off the torso, and inside the hips' twist limit. The width of that
#   range is the wind-up available. A forehand cannot hold a puck far across the
#   body (the arms cross), which is what leaves a cross-body forehand weak; a
#   backhand can.
#
# Everything is in the hips' frame, as YAWS off forward with the stick side
# positive, so one set of numbers serves both hands.

class Config:
	# Half-width of the arc about the tangent that still takes the full load.
	var full_arc_rad: float = deg_to_rad(45.0)
	# Torso yaw limit off the hips.
	var max_twist_rad: float = deg_to_rad(67.0)
	# How far round the stick side, off the torso, either hand holds the puck.
	var stick_side_reach_rad: float = deg_to_rad(90.0)
	# How far across the body, off the torso, each hand holds the puck.
	var forehand_cross_reach_rad: float = deg_to_rad(30.0)
	var backhand_cross_reach_rad: float = deg_to_rad(90.0)


# Caller-owned result: filled, never allocated, so the per-tick aim path is free.
class Result:
	var is_backhand: bool = false
	# 0..1, alignment × coil: the share of the full shot this release can carry.
	var load: float = 1.0
	# The torso yaw off the hips that holds the full wind-up for this shot, in
	# upper_body_angle's convention (left positive).
	var wound_yaw: float = 0.0


# puck_local and aim_local are in the skater's local frame (forward −Z, right
# +X): the puck's offset from the body and the release direction.
static func solve(out: Result, puck_local: Vector3, aim_local: Vector3,
		is_left_handed: bool, cfg: Config) -> void:
	if Vector2(aim_local.x, aim_local.z).length_squared() < 0.000001:
		out.is_backhand = false
		out.load = 1.0
		out.wound_yaw = 0.0
		return
	# Left-positive yaw, flipped for a right-handed shooter so the stick side
	# is positive for both.
	var stick_sign: float = 1.0 if is_left_handed else -1.0
	var puck_bearing: float = stick_sign * atan2(-puck_local.x, -puck_local.z)
	var aim_bearing: float = stick_sign * atan2(-aim_local.x, -aim_local.z)

	# A forehand moves the puck toward the off side (decreasing bearing), so its
	# tangent at the puck is the bearing a quarter-turn back.
	var forehand_alignment: float = -sin(aim_bearing - puck_bearing)
	out.is_backhand = forehand_alignment < 0.0
	out.load = alignment_share(absf(forehand_alignment), cfg.full_arc_rad) \
			* coil_share(puck_bearing, out.is_backhand, cfg)
	out.wound_yaw = stick_sign * wound_bearing(puck_bearing, out.is_backhand, cfg)


# |cos| of the angle between the shot and the tangent → 0..1: full inside the
# arc, linear to nothing on the line through the puck.
static func alignment_share(tangent_cos: float, full_arc_rad: float) -> float:
	var off_tangent: float = acos(clampf(tangent_cos, 0.0, 1.0))
	var taper: float = PI * 0.5 - full_arc_rad
	if taper <= 0.0:
		return 1.0
	return clampf((PI * 0.5 - off_tangent) / taper, 0.0, 1.0)


# Wind-up available, as a share of the hips' twist limit — the turn a forehand
# from straight beside the body gets.
static func coil_share(puck_bearing: float, is_backhand: bool, cfg: Config) -> float:
	if cfg.max_twist_rad <= 0.0:
		return 1.0
	var width: float = _torso_hi(puck_bearing, is_backhand, cfg) \
			- _torso_lo(puck_bearing, cfg)
	return clampf(width / cfg.max_twist_rad, 0.0, 1.0)


# The end of the torso's range the hand winds to: a forehand winds toward the
# stick side, a backhand toward the off side.
static func wound_bearing(puck_bearing: float, is_backhand: bool, cfg: Config) -> float:
	var lo: float = _torso_lo(puck_bearing, cfg)
	var hi: float = _torso_hi(puck_bearing, is_backhand, cfg)
	if hi < lo:
		return 0.0
	return lo if is_backhand else hi


# Torso yaws that keep the puck within reach: the puck sits at
# (puck_bearing − torso) off the torso, which must lie inside
# [−cross_reach, stick_side_reach].
static func _torso_lo(puck_bearing: float, cfg: Config) -> float:
	return maxf(-cfg.max_twist_rad, puck_bearing - cfg.stick_side_reach_rad)


static func _torso_hi(puck_bearing: float, is_backhand: bool, cfg: Config) -> float:
	var cross: float = cfg.backhand_cross_reach_rad if is_backhand \
			else cfg.forehand_cross_reach_rad
	return minf(cfg.max_twist_rad, puck_bearing + cross)
