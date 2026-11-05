class_name PuckReceptionRules

# Pure decision: when a loose puck overlaps a blade, does the skater receive it
# (set as carrier) or deflect it (bounce off via PuckCollisionRules)?
#
# The decision reads the puck's speed RELATIVE to the receiver (puck_velocity −
# receiver_velocity), not its world-frame speed. Catching is momentum
# absorption, and the momentum the hands must soak is set by the closing speed
# between blade and puck: a stretch pass leading a streaking receiver arrives
# gently in their frame (easy catch at any angle), skating hard INTO the same
# pass steepens it, and retreating with a hard shot cushions it back under the
# catchable ceiling — "giving with the puck" re-emerges as a skating read
# instead of a stick gesture.
#
#   pickup_max_speed:    relative speed below which pickup always succeeds
#   deflect_min_speed:   relative-speed threshold for a blade reaching off the line
#   offset:              how far off the puck's path in the receiver's frame
#                        the blade sits (path_offset: 0 on it, 1 at the rim)
#   alignment_bonus:     extra m/s tolerated at offset 0 — getting the blade
#                        onto the line is what lets it corral a hard puck,
#                        whichever way the face happens to point.
#
# Calibration (relative frame, grounded in real reception, not game constants):
# a catch means the blade isn't blown open while the hands absorb ~m·v²/2d over
# d ≈ 0.25 m of natural give against the ~150–250 N a wrist-held blade can
# resist (170 g puck: ~136 N at 22 m/s, ~267 N at 28 — blown open). That force
# ceiling matches observed hockey: pros routinely handle ~45–50 mph feeds
# (20–22 m/s) and treat ~60+ mph contact as a knock-down even on the line, and
# real receivers usually close a few m/s on the pass, so the world-frame
# anecdotes sit slightly BELOW the relative-frame capability. Hence the
# defaults: deflect_min 22 (a blade at the rim of its reach ≈ 49 mph closing) +
# bonus 8 (on the line, 30 ≈ 67 mph closing).
#
# Reception is still REACTIVE: relative speed and where the blade sits against
# the puck's path at contact, nothing else — deliberately no blade-velocity /
# cushion term (a preemptive backswing gesture felt fiddly and unintuitive). The
# skater's own velocity is a frame correction, not a gesture: it changes what
# "incoming speed" means, it doesn't reward stick wind-up.
static func should_receive(
		puck_velocity: Vector3,
		receiver_velocity: Vector3,
		offset: float,
		pickup_max_speed: float,
		deflect_min_speed: float,
		alignment_bonus: float) -> bool:
	if (puck_velocity - receiver_velocity).length() <= pickup_max_speed:
		return true
	return reception_load(puck_velocity, receiver_velocity, offset,
			deflect_min_speed, alignment_bonus) < 1.0


# Pure: the share of the blade's catch capacity this contact uses —
# (relative speed / catch ceiling)², squared because the hands soak the puck's
# energy (the model should_receive is calibrated on). Below 1 the blade holds
# it; 1 is the ceiling. The ceiling is should_receive's: the floor plus the
# alignment bonus by how near the blade is to the puck's path (`offset`).
static func reception_load(
		puck_velocity: Vector3,
		receiver_velocity: Vector3,
		offset: float,
		deflect_min_speed: float,
		alignment_bonus: float) -> float:
	var relative_speed: float = (puck_velocity - receiver_velocity).length()
	if relative_speed < 0.001:
		return 0.0
	var threshold: float = deflect_min_speed \
			+ alignment_bonus * (1.0 - clampf(offset, 0.0, 1.0))
	if threshold <= 0.0:
		return INF
	var ratio: float = relative_speed / threshold
	return ratio * ratio


# Pure: seconds a catch at `catch_load` leaves the receiver settling — unable to act
# with the puck. Zero up to `clean_load`, then linear in load (energy) to `max_s`
# at the ceiling. Grounding and calibration: docs/stick-settling-plan.md.
static func settle_time(catch_load: float, clean_load: float, max_s: float) -> float:
	if catch_load <= clean_load or clean_load >= 1.0:
		return 0.0
	return max_s * clampf((catch_load - clean_load) / (1.0 - clean_load), 0.0, 1.0)


# Pure: horizontal unit vector perpendicular to the stick shaft (top_hand →
# blade_contact), picking the face that opposes reference_velocity (i.e. faces
# an incoming puck). `fallback_stick_dir` is used as the shaft direction when the
# hand and blade are coincident (degenerate). The face a deflect or a bobble
# comes off (Skater.get_blade_face_normal); whether the blade catches is read
# off the path instead (path_offset).
static func blade_face_normal(
		blade_contact: Vector3,
		top_hand: Vector3,
		reference_velocity: Vector3,
		fallback_stick_dir: Vector3) -> Vector3:
	var stick_horiz: Vector3 = blade_axis(blade_contact, top_hand, fallback_stick_dir)
	var face_normal := Vector3(-stick_horiz.z, 0.0, stick_horiz.x)
	if face_normal.dot(reference_velocity) > 0.0:
		face_normal = -face_normal
	return face_normal


# Pure: the blade's heel→toe direction on the ice — the shaft's horizontal
# run (top_hand → blade_contact), which the blade continues. The face normal
# above is its perpendicular. `fallback_stick_dir` stands in when hand and
# blade are coincident.
static func blade_axis(blade_contact: Vector3, top_hand: Vector3,
		fallback_stick_dir: Vector3) -> Vector3:
	var stick_horiz: Vector3 = blade_contact - top_hand
	stick_horiz.y = 0.0
	if stick_horiz.length() < 0.001:
		stick_horiz = fallback_stick_dir
		stick_horiz.y = 0.0
	return stick_horiz.normalized()


# Pure: how far the puck's path passes from the blade's middle, as a share of
# the reach past the blade — 0 while the path, in the receiver's frame, passes
# within `half_length` of the middle (it meets the blade, whichever way the
# blade lies), rising linearly to 1 at `reach` (the pickup radius: the blade only
# just got to it). Read off the path's line, never off the contact point: the
# pickup sweep registers at the rim of its radius, wherever the blade was aimed.
static func path_offset(puck_pos: Vector3, relative_velocity: Vector3,
		blade_mid: Vector3, half_length: float, reach: float) -> float:
	var speed: float = Vector2(relative_velocity.x, relative_velocity.z).length()
	if speed < 0.001 or reach <= half_length:
		return 0.0
	var miss: float = absf((puck_pos.x - blade_mid.x) * relative_velocity.z
			- (puck_pos.z - blade_mid.z) * relative_velocity.x) / speed
	return clampf((miss - half_length) / (reach - half_length), 0.0, 1.0)


# Pure: the reception load past which a catch at `offset` (path_offset) bobbles
# instead of holding. A blade reaching off the line meets the puck on its toe or heel,
# where the impact twists it in the hands, so a reach holds less: `bobble_load`
# on the line, less `edge_share` of it at the rim of the reach.
static func bobble_load_at(offset: float, bobble_load: float,
		edge_share: float) -> float:
	return bobble_load * (1.0 - edge_share * offset * offset)


# Pure on-ice/off-ice gate: a blade only interacts with pucks on its own
# vertical plane. A lifted blade (off the ice) handles airborne pucks; a
# grounded blade handles grounded pucks. This is what lets a saucer pass fly
# over a stationary, grounded blade instead of being corralled out of the air,
# and is what limits a fully lifted blade (a stick lift, a tie, a forced pop) to
# airborne pucks. A committed deflect (Q held) skips it: its blade rises to the
# puck's own height (DeflectReachRules), so it has no plane to keep to.
static func blade_can_interact(blade_up: bool, puck_airborne: bool) -> bool:
	return blade_up == puck_airborne
