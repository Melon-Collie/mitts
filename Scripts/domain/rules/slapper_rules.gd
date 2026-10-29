class_name SlapperRules
extends RefCounted

# The slapshot's stance, in the skater's own frame: +X right, −Z forward, as an
# (x, z) Vector2. A slapshot is struck side-on: the puck lies in front of the
# body and the swing drives it across, toward the top hand's shoulder (the
# off-stick side), so the shot line runs along the shoulders rather than out
# from the chest. `blade_side_sign` is +1 when the blade is on the right.


# Where the blade meets the puck at the bottom of the swing. The top hand hangs
# under its shoulder at rest height and the stick runs a full length from it to
# the ice (`stick_horiz`, its horizontal span); the puck sits half a blade on
# from the heel. `front_m` is how far toward the front foot, off centre, the
# puck is played.
static func strike_spot_local(top_shoulder: Vector2, stick_horiz: float,
		blade_length: float, front_m: float, blade_side_sign: float) -> Vector2:
	var x: float = -blade_side_sign * front_m
	var dx: float = x - top_shoulder.x
	var heel_dz: float = sqrt(maxf(stick_horiz * stick_horiz - dx * dx, 0.0))
	var dir := Vector2(dx, -heel_dz)
	if dir.length_squared() < 0.000001:
		return top_shoulder
	return top_shoulder + dir.normalized() * (stick_horiz + blade_length * 0.5)


# The hips' facing for a shot along `shot_dir` (world XZ, unit): turned
# `open_rad` off the line toward the stick side, so at 90° the top hand's
# shoulder points straight down it.
static func stance_facing(shot_dir: Vector2, blade_side_sign: float, open_rad: float) -> Vector2:
	var right := Vector2(-shot_dir.y, shot_dir.x)
	return (shot_dir * cos(open_rad) + right * (blade_side_sign * sin(open_rad))).normalized()


# Within this of the spot its circle sets from, a body's shuffle has put the
# circle on the line: a fraction of the slapper zone's own radius.
const SET_ARRIVE_M: float = 0.1


# Seconds a body facing `facing` and moving at `velocity` (world XZ) takes to set
# for a slapshot along `shot_dir` (unit) from the spot `to_anchor` off it (not
# finite: wherever it is), for a feed arriving in `feed_s`: the hips pivot into
# the stance at `turn_rad_s` while the feet shuffle across at `shuffle_speed`, so
# the slower of the two. Loaded, a skater can do nothing else — the stride is
# gone — so his momentum glides him on across the line meanwhile, and a body
# still faster than a shuffle steers has to arrive on that glide alone (INF when
# it would not). An unreadable facing reads as set.
static func time_to_set(facing: Vector2, velocity: Vector2, to_anchor: Vector2,
		shot_dir: Vector2, feed_s: float, blade_side_sign: float, open_rad: float,
		turn_rad_s: float, shuffle_speed: float) -> float:
	var turn_s: float = 0.0
	if facing.length_squared() > 0.0001:
		turn_s = absf(facing.angle_to(stance_facing(shot_dir, blade_side_sign, open_rad))) \
				/ maxf(turn_rad_s, 0.001)
	if not to_anchor.is_finite():
		return turn_s
	# The anchor lies straight across the line from the body, so only the glide's
	# share across it moves the circle onto it.
	var across: Vector2 = to_anchor.normalized() if to_anchor.length_squared() > 0.000001 \
			else Vector2.ZERO
	var miss: float = absf(to_anchor.length() - velocity.dot(across) * feed_s)
	if velocity.length() > SkaterMovementRules.SHUFFLE_MAX_SPEED:
		return INF if miss > SET_ARRIVE_M else turn_s
	return maxf(turn_s, maxf(miss - SET_ARRIVE_M, 0.0) / maxf(shuffle_speed, 0.001))


# A point in a frame facing `facing` (world XZ, unit), as a world offset.
static func local_to_world(local: Vector2, facing: Vector2) -> Vector2:
	var right := Vector2(-facing.y, facing.x)
	return right * local.x - facing * local.y


# Where the puck is struck, off the skater's position, once the hips have set
# for a shot along `shot_dir`.
static func strike_offset(shot_dir: Vector2, strike_local: Vector2,
		blade_side_sign: float, open_rad: float) -> Vector2:
	return local_to_world(strike_local,
			stance_facing(shot_dir, blade_side_sign, open_rad))


# The shot line toward `target` FROM the strike spot, which itself moves with
# the line: a stance set for a different line strikes from a different spot.
# Two passes settle it to well under a degree at any range the spot can be off
# the body. ZERO when the target is on top of the skater.
static func aim_from_strike(skater_xz: Vector2, target_xz: Vector2,
		strike_local: Vector2, blade_side_sign: float, open_rad: float) -> Vector2:
	var to_target: Vector2 = target_xz - skater_xz
	if to_target.length_squared() < 0.0001:
		return Vector2.ZERO
	var dir: Vector2 = to_target.normalized()
	for _i: int in 2:
		var from_spot: Vector2 = to_target \
				- strike_offset(dir, strike_local, blade_side_sign, open_rad)
		if from_spot.length_squared() < 0.0001:
			return dir
		dir = from_spot.normalized()
	return dir


# Seconds to bring a raised stick back down to the puck after calling a
# slapshot off: from `min_s` with the backswing barely started to `max_s` from
# the top. The wind-up's height climbs linearly with `wind_up_t` (0..1), so the
# way back down does too.
static func recover_time(wind_up_t: float, min_s: float, max_s: float) -> float:
	return lerpf(min_s, max_s, clampf(wind_up_t, 0.0, 1.0))


# `aim` (unit, world XZ) held within `arc_rad` either side of `line`: how far the
# shoulders can turn a slapshot off the line the feet set up on.
static func clamp_aim(aim: Vector2, line: Vector2, arc_rad: float) -> Vector2:
	var off: float = line.angle_to(aim)
	return line.rotated(clampf(off, -arc_rad, arc_rad))


# The blade's restitution off a still puck struck at `power`: the deflect model's
# (PuckCollisionRules.deflect_velocity) at the swing's own speed B, where
# B(1 + e) = power. Read once per swing, so a feed's pace never deadens the face
# that drives it — the deflect model's falloff is a static blade smothering a
# hard puck, and a slapshot's face is moving.
static func swing_restitution(power: float, e_soft: float, e_hard: float, speed_ref: float) -> float:
	if e_hard < 0.0 or speed_ref <= 0.0001:
		return e_soft
	var e: float = e_soft
	# Each pass more than halves the error over the slapper's range, so six
	# settle it far under anything a shot's speed can show.
	for _i: int in 6:
		e = lerpf(e_soft, e_hard, clampf(power / (1.0 + e) / speed_ref, 0.0, 1.0))
	return e


# A slapshot struck off a moving puck. `shot` is what the swing gives a still puck
# (m/s, world); `feed` is the puck's velocity in the shooter's frame (world XZ).
# Along the line the blade adds `restitution` × the feed's pace at it, and takes
# as much off one running away; across it, the face keeps `grip` of the glance,
# so the shot pulls the way the pass was going. The lift is the blade's loft and
# is untouched. Never faster than `max_speed`, unless the swing alone already is.
static func one_timer_contact(shot: Vector3, feed: Vector2, restitution: float,
		grip: float, max_speed: float) -> Vector3:
	var h := Vector2(shot.x, shot.z)
	var speed_h: float = h.length()
	if speed_h < 0.0001:
		return shot
	var d: Vector2 = h / speed_h
	var u_n: float = feed.dot(d)
	var u_t: Vector2 = feed - d * u_n
	var out_h: Vector2 = d * maxf(speed_h - restitution * u_n, 0.0) + u_t * grip
	var out := Vector3(out_h.x, shot.y, out_h.y)
	return out.limit_length(maxf(max_speed, shot.length()))


# How much of a caught feed's pace the swing still meets, `held_s` after the
# catch: all of it inside `leniency_s`, none by `window_s`, when the window
# closes. A one-timer held on the blade becomes a slapshot off a still puck.
static func feed_transfer(held_s: float, leniency_s: float, window_s: float) -> float:
	if window_s <= leniency_s:
		return 1.0 if held_s <= leniency_s else 0.0
	return clampf(1.0 - (held_s - leniency_s) / (window_s - leniency_s), 0.0, 1.0)


# The swing line (unit, world XZ) that sends a one-timer off `feed` along
# `target` (unit): one_timer_contact pulls the shot toward the feed's cross
# speed, so the swing leads against it. Three passes settle it under a tenth of
# a degree; the pull barely changes over the few degrees it leads by.
static func aim_for_contact(target: Vector2, power: float, feed: Vector2,
		restitution: float, grip: float) -> Vector2:
	var d: Vector2 = target
	for _i: int in 3:
		var out: Vector3 = one_timer_contact(Vector3(d.x, 0.0, d.y) * power, feed,
				restitution, grip, INF)
		var out_h := Vector2(out.x, out.z)
		if out_h.length_squared() < 0.0001:
			return target
		d = d.rotated(out_h.angle_to(target))
	return d
