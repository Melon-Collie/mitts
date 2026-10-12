class_name AIStickLiftRead
extends RefCounted

# Whether an on-puck defender lifts the carrier's stick rather than jabbing at
# the puck. The jab needs a blade path to the puck; a carrier who has the puck on
# the far side of his body has taken that path away. The lift needs only the
# shaft, which crosses in front of the body from his hands — so it is the answer
# exactly when the puck is shielded and the shaft is still in reach.

# Where a lifted blade's contact point sits: SkaterController.blade_height plus
# blade_lift_height (test_stick_lift_read.gd holds the pair).
const LIFT_CONTACT_Y_M: float = 0.55
# Room between the shaft and the blade under it: about a blade's own height, so
# a slewing cursor that lands a few centimetres off still ends up underneath.
const UNDER_CLEARANCE_M: float = 0.08


# The point on the carrier's shaft a lifted blade gets under: where the shaft
# runs at the lifted blade's height plus the clearance, walking down from the
# hands. A shaft never that high (a choked, low carry) offers only its top.
static func shaft_lift_point(hand: Vector3, blade: Vector3) -> Vector3:
	var target_y: float = LIFT_CONTACT_Y_M + UNDER_CLEARANCE_M
	var drop: float = hand.y - blade.y
	if drop <= 1e-4 or hand.y <= target_y:
		return hand
	var t: float = clampf((hand.y - target_y) / drop, 0.0, 1.0)
	return hand.lerp(blade, t)


# The carrier's body stands across the line from us to the puck, so a blade
# reaching for it goes through him.
static func puck_shielded(self_pos: Vector3, carrier_pos: Vector3, puck_pos: Vector3,
		body_radius: float) -> bool:
	var a := Vector2(self_pos.x, self_pos.z)
	var b := Vector2(puck_pos.x, puck_pos.z)
	var c := Vector2(carrier_pos.x, carrier_pos.z)
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 1e-8:
		return false
	var t: float = (c - a).dot(ab) / len_sq
	if t <= 0.0 or t >= 1.0:
		return false
	return (a + ab * t).distance_to(c) < body_radius


# Lift when the jab is blocked and the shaft point is within the blade's reach
# (`reach`, horizontal, from our body).
static func prefers_lift(self_pos: Vector3, carrier_pos: Vector3, puck_pos: Vector3,
		hand: Vector3, blade: Vector3, reach: float, body_radius: float) -> bool:
	if not puck_shielded(self_pos, carrier_pos, puck_pos, body_radius):
		return false
	var p: Vector3 = shaft_lift_point(hand, blade)
	var dx: float = p.x - self_pos.x
	var dz: float = p.z - self_pos.z
	return dx * dx + dz * dz <= reach * reach
