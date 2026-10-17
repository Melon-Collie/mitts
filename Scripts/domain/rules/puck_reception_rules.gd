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
#   deflect_min_speed:   relative-speed threshold for a poorly-angled blade
#   alignment_bonus:     extra m/s tolerated when the blade face is square to
#                        the incoming line (in the receiver's frame) — squaring
#                        up is what lets a blade corral a hard puck.
#
# Calibration (relative frame, grounded in real reception, not game constants):
# a catch means the blade isn't blown open while the hands absorb ~m·v²/2d over
# d ≈ 0.25 m of natural give against the ~150–250 N a wrist-held blade can
# resist (170 g puck: ~136 N at 22 m/s, ~267 N at 28 — blown open). That force
# ceiling matches observed hockey: pros routinely handle ~45–50 mph feeds
# (20–22 m/s) and treat ~60+ mph contact as a knock-down even when squared, and
# real receivers usually close a few m/s on the pass, so the world-frame
# anecdotes sit slightly BELOW the relative-frame capability. Hence the
# defaults: deflect_min 22 (any-angle ceiling ≈ 49 mph closing) + bonus 8
# (squared ceiling 30 ≈ 67 mph closing).
#
# Reception is still REACTIVE: relative speed and blade angle at contact,
# nothing else — deliberately no blade-velocity / cushion term (a preemptive
# backswing gesture felt fiddly and unintuitive). The skater's own velocity is
# a frame correction, not a gesture: it changes what "incoming speed" means,
# it doesn't reward stick wind-up.
# League-default reception thresholds (m/s, receiver frame) for readers with no
# Puck to ask — the bots' pass pricing. The live values are Puck's
# pickup_max_speed / deflect_min_speed / alignment_receive_bonus.
const LEAGUE_PICKUP_MAX_M_S: float = 8.0
const LEAGUE_DEFLECT_MIN_M_S: float = 22.0
const LEAGUE_ALIGNMENT_BONUS_M_S: float = 8.0

# Settle at the catch ceiling: a pro taking a touch on a feed he only just held.
const RECEPTION_SETTLE_MAX_S: float = 0.25
# Blade speed cap while settling — the hands are still soaking the catch, so the
# blade moves at about a quarter of the league dangle speed (max_blade_speed 10).
const SETTLE_BLADE_SPEED_M_S: float = 2.5


static func should_receive(
		puck_velocity: Vector3,
		receiver_velocity: Vector3,
		blade_normal: Vector3,
		pickup_max_speed: float,
		deflect_min_speed: float,
		alignment_bonus: float) -> bool:
	var relative_velocity: Vector3 = puck_velocity - receiver_velocity
	var relative_speed: float = relative_velocity.length()
	if relative_speed <= pickup_max_speed:
		return true
	var threshold: float = deflect_min_speed + alignment_bonus * alignment(relative_velocity, blade_normal)
	return relative_speed < threshold


# How head-on the approach is, in the receiver's frame: -relative_dir points
# from puck toward the blade; dot with the face normal = squareness. Negative
# (puck moving away from the face) clamps to 0, no bonus.
static func alignment(relative_velocity: Vector3, blade_normal: Vector3) -> float:
	if relative_velocity.length_squared() < 0.000001:
		return 0.0
	return maxf(0.0, -relative_velocity.normalized().dot(blade_normal))


# Seconds a caught puck ties up the receiver's hands before it can leave the
# blade again. The catch above is a force limit (blade not blown open, force ∝
# v²), so the settle is the share of that limit the catch used: nothing below
# the always-catch speed, the full RECEPTION_SETTLE_MAX_S at the ceiling for
# this blade angle. Squaring up raises the ceiling, so it shortens the settle
# exactly as it widens the catch. Pass the same (possibly ceiling-scaled)
# thresholds should_receive was judged with.
static func settle_seconds(
		relative_speed: float,
		blade_alignment: float,
		pickup_max_speed: float,
		deflect_min_speed: float,
		alignment_bonus: float) -> float:
	var ceiling: float = deflect_min_speed + alignment_bonus * clampf(blade_alignment, 0.0, 1.0)
	var floor_sq: float = pickup_max_speed * pickup_max_speed
	var span: float = ceiling * ceiling - floor_sq
	if span <= 0.0:
		return 0.0
	var used: float = clampf((relative_speed * relative_speed - floor_sq) / span, 0.0, 1.0)
	return RECEPTION_SETTLE_MAX_S * used


# Pure: horizontal unit vector perpendicular to the stick shaft (top_hand →
# blade_contact), picking the face that opposes reference_velocity (i.e. faces
# an incoming puck). `fallback_stick_dir` is used as the shaft direction when the
# hand and blade are coincident (degenerate). Shared by Skater.get_blade_face_normal
# (live geometry) and the lag-comp pickup resolver (rewound snapshot geometry) so
# the catch-vs-deflect decision judges against ONE definition of "blade face".
# For the receive decision, pass the RELATIVE velocity (puck − receiver) as the
# reference so the face opposes the approach in the receiver's frame.
static func blade_face_normal(
		blade_contact: Vector3,
		top_hand: Vector3,
		reference_velocity: Vector3,
		fallback_stick_dir: Vector3) -> Vector3:
	var stick_horiz: Vector3 = blade_contact - top_hand
	stick_horiz.y = 0.0
	if stick_horiz.length() < 0.001:
		stick_horiz = fallback_stick_dir
	stick_horiz = stick_horiz.normalized()
	var face_normal := Vector3(-stick_horiz.z, 0.0, stick_horiz.x)
	if face_normal.dot(reference_velocity) > 0.0:
		face_normal = -face_normal
	return face_normal


# Pure on-ice/off-ice gate: a blade only interacts with pucks on its own
# vertical plane. A lifted blade (off the ice) handles airborne pucks; a
# grounded blade handles grounded pucks. This is what lets a saucer pass fly
# over a stationary, grounded blade instead of being corralled out of the air,
# and is what limits a lifted blade to tipping airborne pucks. Shared by a
# passive receiver AND a committed deflect (Q held): blade_up already encodes the
# deflect level's plane — grounded at FLAT/LOW, lifted only at HIGH — so both go
# through this one gate. The loft level changes the redirect DIRECTION, not the
# plane (FLAT/LOW play the ice, HIGH plays the air).
static func blade_can_interact(blade_up: bool, puck_airborne: bool) -> bool:
	return blade_up == puck_airborne
