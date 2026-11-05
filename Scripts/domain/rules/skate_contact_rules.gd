class_name SkateContactRules

# A loose puck on the ice against a skater's two skates. The torso band
# (Skater.get_body_block_y_range) leaves the ice open under the body; the boots
# close all of it but the gap between them, so a nutmeg goes through the gap.
#
# Frame: the ice plane as Vector2 (x, z), relative to the skater's origin, the
# boots set out along the facing's right and laid along the facing. Collision
# reads tick state only — the facing and the stance — never the gait's drawn
# feet, which move at render rate with the stride: the boots are where the feet
# stand at rest.

# Each skate under its hip (GaitPose.HIP_HALF_WIDTH), and in the stance set out
# a further stance_width_m (SkaterController). test_skate_contact_rules holds
# both against their sources.
const REST_HALF_SPACING_M: float = 0.13
const STANCE_EXTRA_SPACING_M: float = 0.125
# A senior skate's holder runs ~0.29 m heel to toe; the boot is ~0.10 m across.
const BOOT_LENGTH_M: float = 0.30
const BOOT_HALF_WIDTH_M: float = 0.05
# Ice to the top of the boot at the ankle: a puck whose bottom is below it meets
# the boot.
const BOOT_HEIGHT_M: float = 0.20

# Receiver-relative pace a boot can still turn to the stick: half the blade's
# any-angle catch ceiling (Puck.deflect_min_speed, 22 m/s). A boot is a narrow
# face angled from the ankle, with no hands to give with the puck.
const KICK_MAX_SPEED_M_S: float = 11.0
# The push off the boot is paced to reach the blade in about this long — a
# touch, not a pass — inside these bounds, in the receiver's frame.
const KICK_ARRIVAL_S: float = 0.25
const KICK_MIN_PUSH_M_S: float = 1.0
const KICK_MAX_PUSH_M_S: float = 4.0
# An opponent's body this close has a stick on the puck before the kick reaches
# the blade: his ~1.6 m reach plus the ~0.4 m he skates in KICK_ARRIVAL_S.
const PRESSURE_RADIUS_M: float = 2.0
# Gathering a puck off the skate costs the catch this much settle (the lock a
# hard catch leaves, PuckReceptionRules.settle_time): eyes down, stick to it.
const KICK_SETTLE_S: float = 0.25
# A catch this soon after the kick is the kick's puck arriving.
const KICK_CATCH_WINDOW_S: float = 0.6
# A boot not turned to the play: a hard shell over a foot that gives a little —
# livelier than the body's padding (Puck.body_block_cor_scale, 0.40).
const BOOT_COR_SCALE: float = 0.55
const BOOT_FRICTION: float = 0.30


# Where the puck met a boot: the outward normal at the closest approach and the
# puck's centre there, both in the skater's frame. Caller-owned scratch.
class Contact:
	var normal: Vector2 = Vector2.ZERO
	var point: Vector2 = Vector2.ZERO


static func half_spacing(in_stance: bool) -> float:
	return REST_HALF_SPACING_M + (STANCE_EXTRA_SPACING_M if in_stance else 0.0)


# Reach from a boot's long axis to the puck's centre at contact.
static func reach() -> float:
	return BOOT_HALF_WIDTH_M + GameRules.PUCK_COLLISION_RADIUS


static func puck_below_boot_top(puck_y: float) -> bool:
	return puck_y - GameRules.PUCK_COLLISION_HALF_HEIGHT < BOOT_HEIGHT_M


# Whether the puck's swept path `rel_prev`→`rel_curr` (skater's frame) meets
# either boot; on a hit, fills `out` from the nearer one. `forward` is the unit
# facing on the ice. Each boot is a capsule BOOT_LENGTH_M long, end to end.
static func find_contact(rel_prev: Vector2, rel_curr: Vector2, forward: Vector2,
		spacing: float, out: Contact) -> bool:
	var right := Vector2(-forward.y, forward.x)
	var hit_l: float = _boot_approach(rel_prev, rel_curr, -right * spacing, forward, out)
	var n_l: Vector2 = out.normal
	var p_l: Vector2 = out.point
	var hit_r: float = _boot_approach(rel_prev, rel_curr, right * spacing, forward, out)
	if hit_l < 0.0 and hit_r < 0.0:
		return false
	if hit_r < 0.0 or (hit_l >= 0.0 and hit_l <= hit_r):
		out.normal = n_l
		out.point = p_l
	return true


# The puck's distance from one boot's axis at the closest approach, or −1 when it
# stays out of reach. Fills `out` either way.
static func _boot_approach(rel_prev: Vector2, rel_curr: Vector2, centre: Vector2,
		forward: Vector2, out: Contact) -> float:
	var half: Vector2 = forward * (BOOT_LENGTH_M * 0.5 - BOOT_HALF_WIDTH_M)
	var st: Vector2 = PuckInteractionRules.segment_closest_params(
			Vector3(rel_prev.x, 0.0, rel_prev.y), Vector3(rel_curr.x, 0.0, rel_curr.y),
			Vector3(centre.x - half.x, 0.0, centre.y - half.y),
			Vector3(centre.x + half.x, 0.0, centre.y + half.y))
	var puck_at: Vector2 = rel_prev.lerp(rel_curr, st.x)
	var axis_at: Vector2 = (centre - half).lerp(centre + half, st.y)
	var offset: Vector2 = puck_at - axis_at
	var dist: float = offset.length()
	out.point = puck_at
	# Dead on the axis (the path ran through it) the side it came from is back
	# along the path.
	if dist > 1e-5:
		out.normal = offset / dist
	elif rel_prev.distance_squared_to(rel_curr) > 1e-10:
		out.normal = (rel_prev - rel_curr).normalized()
	else:
		out.normal = Vector2(-forward.y, forward.x)
	return dist if dist <= reach() else -1.0


# Moving into the boot in the skater's frame — a puck leaving a boot it just
# came off never meets it again.
static func approaching(relative_velocity: Vector2, normal: Vector2) -> bool:
	return relative_velocity.dot(normal) < 0.0


# The skate turned to the stick: a puck the skater's own team last played
# (`puck_team` −1 is nobody's), slow enough for a boot, with the stick free to
# take it and no opponent on him.
static func can_kick(relative_speed: float, puck_team: int, kicker_team: int,
		stick_free: bool, pressured: bool) -> bool:
	if not stick_free or pressured or relative_speed > KICK_MAX_SPEED_M_S:
		return false
	return puck_team == -1 or puck_team == kicker_team


static func pressures(kicker_pos: Vector3, opponent_pos: Vector3) -> bool:
	var dx: float = opponent_pos.x - kicker_pos.x
	var dz: float = opponent_pos.z - kicker_pos.z
	return dx * dx + dz * dz <= PRESSURE_RADIUS_M * PRESSURE_RADIUS_M


# The kick: the boot takes the puck and pushes it on to the blade, flat, paced to
# arrive in KICK_ARRIVAL_S. `contact` and `blade` are in the skater's frame; a
# blade already over the contact sends it along the facing.
static func kick_velocity(skater_velocity: Vector3, contact: Vector2, blade: Vector2,
		forward: Vector2) -> Vector3:
	var to_blade: Vector2 = blade - contact
	var dist: float = to_blade.length()
	var dir: Vector2 = to_blade / dist if dist > 1e-4 else forward
	var push: float = clampf(dist / KICK_ARRIVAL_S, KICK_MIN_PUSH_M_S, KICK_MAX_PUSH_M_S)
	return Vector3(skater_velocity.x + dir.x * push, 0.0, skater_velocity.z + dir.y * push)


# Any other boot contact: the puck comes off the boot's face in the skater's
# frame, the same contact model as the body block and the goalie's gear.
static func bounce_velocity(puck_velocity: Vector3, skater_velocity: Vector3,
		normal: Vector2) -> Vector3:
	var rel := Vector3(puck_velocity.x - skater_velocity.x, puck_velocity.y,
			puck_velocity.z - skater_velocity.z)
	var out: Vector3 = PuckCollisionRules.deflect_velocity_3d(
			rel, Vector3(normal.x, 0.0, normal.y), BOOT_COR_SCALE, BOOT_FRICTION)
	return Vector3(skater_velocity.x + out.x, out.y, skater_velocity.z + out.z)
