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
