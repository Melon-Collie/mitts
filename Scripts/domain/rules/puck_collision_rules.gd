class_name PuckCollisionRules

# Pure math for puck interactions. The Puck node computes contact points and
# velocities from physics state, then calls these to produce the resulting
# velocity. No engine or signal dependencies here — fully unit-testable.

# Domain rule: an opponent can always attempt a poke check; teammates cannot.
static func can_poke_check(carrier_team_id: int, checker_team_id: int) -> bool:
	return carrier_team_id != checker_team_id

# Billiard-style reflection off the blade. contact_normal is the blade-to-puck
# unit vector at overlap time. Returns new horizontal velocity (no Y component).
#   deflect_blend ∈ [0, 1]: 0 = pure pass-through, 1 = pure reflection
#   speed_retain ∈ [0, 1]: energy retained after deflection
static func deflect_velocity(
		incoming_velocity: Vector3,
		contact_normal: Vector3,
		deflect_blend: float,
		speed_retain: float) -> Vector3:
	var horiz := Vector3(incoming_velocity.x, 0.0, incoming_velocity.z)
	var speed: float = incoming_velocity.length()
	var reflected: Vector3 = horiz - 2.0 * horiz.dot(contact_normal) * contact_normal
	var new_dir: Vector3 = horiz.normalized().lerp(reflected.normalized(), deflect_blend).normalized()
	return new_dir * speed * speed_retain

# Adds upward Y component to a horizontal deflection direction. Used when the
# deflecting skater is elevated.
static func apply_deflection_elevation(horizontal_dir: Vector3, elevation_angle_deg: float) -> Vector3:
	var rad: float = deg_to_rad(elevation_angle_deg)
	return Vector3(
		horizontal_dir.x * cos(rad),
		sin(rad),
		horizontal_dir.z * cos(rad)
	).normalized()

# Loose puck bouncing off a skater's body (passive body-block). Reflect +
# dampen. If the reflection collapses to zero, fall back to the contact normal.
static func body_block_velocity(
		incoming_velocity: Vector3,
		contact_normal: Vector3,
		dampen: float) -> Vector3:
	var horiz := Vector3(incoming_velocity.x, 0.0, incoming_velocity.z)
	var reflected: Vector3 = horiz - 2.0 * horiz.dot(contact_normal) * contact_normal
	if reflected.length() < 0.001:
		reflected = contact_normal
	return reflected.normalized() * horiz.length() * dampen

# Body-check strip: transfers the checker's horizontal momentum into the puck,
# scaled by the strip speed. Trivial but extracted for consistency.
static func body_check_strip_velocity(hit_direction: Vector3, puck_speed: float) -> Vector3:
	return hit_direction * puck_speed

# Poke-check strip velocity. If the checker's blade has meaningful horizontal
# motion, the strip direction is the checker's momentum plus a fraction of the
# carrier's. Otherwise the puck is pushed away from the checker (carrier_pos -
# checker_pos). If both collapse to zero, the caller-supplied fallback_direction
# is used so the rule stays deterministic under test.
static func poke_strip_velocity(
		checker_blade_vel: Vector3,
		carrier_blade_vel: Vector3,
		carrier_pos: Vector3,
		checker_pos: Vector3,
		carrier_vel_blend: float,
		strip_speed: float,
		fallback_direction: Vector3) -> Vector3:
	var checker_horiz := Vector3(checker_blade_vel.x, 0.0, checker_blade_vel.z)
	var carrier_horiz := Vector3(carrier_blade_vel.x, 0.0, carrier_blade_vel.z)
	var strip_dir: Vector3
	if checker_horiz.length() > 0.5:
		strip_dir = checker_horiz + carrier_horiz * carrier_vel_blend
	else:
		strip_dir = Vector3(carrier_pos.x - checker_pos.x, 0.0, carrier_pos.z - checker_pos.z)
	strip_dir.y = 0.0
	if strip_dir.length() > 0.001:
		strip_dir = strip_dir.normalized()
	else:
		strip_dir = fallback_direction.normalized()
	return strip_dir * strip_speed
