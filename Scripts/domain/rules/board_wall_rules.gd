class_name BoardWallRules
extends RefCounted

# The boards as a party to body contact. A check that drives a skater into the
# wall lands harder: the wall takes the recoil his skates would have. And a man
# pressed into it is held there by the squeeze (PressRules): the push that
# cannot move him into the wall grips him against it, so he gets out by pushing
# back to unload it, not by skating off along the glass.

# A body this close to the boards (body edge to board) has nowhere to recoil.
const BACKSTOP_MARGIN_M: float = 0.15
# The hit, or the push, has to be driving into the wall, not along it: within
# 45° of square.
const BACKSTOP_MIN_INTO_WALL: float = 0.7071
# A pressed body counts as against the boards with its edge within this of them:
# the resolver leaves a pair a few centimetres apart as it separates them.
const SQUEEZE_MARGIN_M: float = 0.25
# What the squeeze grips of the force pressing him in, along the wall. Over 1:
# he is gripped on two faces, the glass and the man leaning on him, so an equal
# man square on him holds his whole stride.
const SQUEEZE_GRIP: float = 1.1


# Outward unit normal (XZ) of the boards when a body of `body_radius` at `pos` has
# its edge within `margin` of them, else ZERO.
static func wall_normal(pos: Vector3, body_radius: float, margin: float) -> Vector2:
	var xz := Vector2(pos.x, pos.z)
	var inner: Vector2 = GameRules.clamp_to_rink_inner(xz, body_radius + margin)
	var out: Vector2 = xz - inner
	if out.length_squared() < 1e-8:
		return Vector2.ZERO
	return out.normalized()


# How far `a` is from `b` along the wall whose outward normal is `wall_out`
# (signed, m).
static func along_wall_offset(a: Vector3, b: Vector3, wall_out: Vector2) -> float:
	return Vector2(a.x - b.x, a.z - b.z).dot(Vector2(-wall_out.y, wall_out.x))


# How hard a hit landed, for the stagger and the puck strip: the victim's
# open-ice Δv, or, driven square into the boards, the attacker's whole delivered
# impulse (closing × transfer × his mass) on the victim's mass alone — the wall
# stops him, so none of it goes into his recoil and none is shared with it. The
# knockdown does not read this: being knocked off his feet is being moved, and
# the wall is what stops the moving. `drive_kick` (m/s) is the attacker's leg
# drive, already on the victim's mass alone and inside open_ice_dv.
static func backstop_hit_strength(open_ice_dv: float, closing_speed: float,
		transfer: float, hit_dir: Vector2, wall_out: Vector2, attacker_mass: float,
		victim_mass: float, drive_kick: float = 0.0) -> float:
	if wall_out == Vector2.ZERO or hit_dir.dot(wall_out) < BACKSTOP_MIN_INTO_WALL:
		return open_ice_dv
	return maxf(open_ice_dv,
			closing_speed * transfer * attacker_mass / maxf(victim_mass, 0.001) + drive_kick)


# The most (m/s²) the squeeze takes off a pressed body's speed along the wall.
# `net_push` is the acceleration (m/s², on his own mass) the pair's drives press
# him toward the other body's far side with, `push_dir` (unit XZ) the way it
# pushes him and `wall_out` his boards' normal (ZERO off them). Nothing unless
# he is pushed into the wall, within 45° of square; then SQUEEZE_GRIP of the
# push's share into it.
static func squeeze_grip(net_push: float, push_dir: Vector2, wall_out: Vector2) -> float:
	if wall_out == Vector2.ZERO or net_push <= 0.0:
		return 0.0
	var into: float = push_dir.dot(wall_out)
	if into < BACKSTOP_MIN_INTO_WALL:
		return 0.0
	return SQUEEZE_GRIP * net_push * into


# `vel` with its speed along the wall cut by up to `grip_dv` (m/s) toward rest;
# the component across the wall untouched.
static func gripped(vel: Vector3, wall_out: Vector2, grip_dv: float) -> Vector3:
	if wall_out == Vector2.ZERO or grip_dv <= 0.0:
		return vel
	var along := Vector3(-wall_out.y, 0.0, wall_out.x)
	var slide: float = vel.dot(along)
	return vel - along * (slide - move_toward(slide, 0.0, grip_dv))
