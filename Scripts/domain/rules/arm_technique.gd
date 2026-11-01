class_name ArmTechnique
extends RefCounted

# What hockey players do with a carried stick, inside what a body can do
# (ArmAnatomy): limits that only ever remove a pose anatomy allows.
# docs/arm-anatomy-plan.md §4. Each number is PROVISIONAL until held against
# footage; the map (tests/instruments/actors/test_arm_anatomy_map.gd) shows
# what each one removes.
#
# The HIPS frame throughout (ArmAnatomySearch): +Y up, -Z the way the hips face,
# the origin the trunk's pivot at the hip joints.

# The top hand is the pivot and is held in front of the body, between the hips
# and the chest: no lower than this under the hip joints (the top of the
# thigh), no higher than this under the top shoulder (the chest), and no
# further behind the hips than this.
const TOP_HAND_BELOW_HIP_M: float = 0.15
const TOP_HAND_BELOW_SHOULDER_M: float = 0.2
const TOP_HAND_BEHIND_HIP_M: float = 0.05
# And held in front of the body across it: out on its own side no further than
# the hip and a fist, across the body no further than this past the middle
# (round the forehand it comes across to there).
const TOP_HAND_OUT_M: float = 0.3
const TOP_HAND_ACROSS_M: float = 0.15
# The hands are held apart no wider than the shoulders.
const HANDS_APART_SHOULDERS: float = 1.0
# The knob stands this far clear of the jersey: a stick pulled in until the
# knob digs into the stomach is not a carry.
const KNOB_CLEAR_M: float = 0.02
# The puck is not carried under the body: the blade's middle stays out of the
# skates' footprint, this far either side of the hips and from this far behind
# them to this far ahead (toe drags reach just past it).
const FOOTPRINT_HALF_WIDTH_M: float = 0.3
const FOOTPRINT_BACK_M: float = 0.25
const FOOTPRINT_AHEAD_M: float = 0.2
# The blade rides flat, or a little on its heel or its toe: the shaft's angle
# to the ice within this of the stick's lie.
const LIE_RIDE: float = deg_to_rad(15.0)

enum Limit {
	NONE,
	TOP_HAND_LOW,
	TOP_HAND_HIGH,
	TOP_HAND_BEHIND,
	TOP_HAND_OUT,
	TOP_HAND_ACROSS,
	HANDS_APART,
	KNOB_IN_BODY,
	PUCK_UNDER_BODY,
	LIE,
}


# A stick held: the top hand, the shaft's way to the blade and the bottom
# hand's place down it, the blade's heel and the blade's way along the ice,
# the top shoulder and the jersey (hips frame).
class Hold:
	var top_hand := Vector3.ZERO
	var shaft := Vector3.DOWN
	var spacing: float = 0.0
	var heel := Vector3.ZERO
	var blade_dir := Vector3.FORWARD
	var top_shoulder := Vector3.ZERO
	var torso := Transform3D.IDENTITY


class Verdict:
	# The worst excess past a rule (radians, or ArmAnatomy.METRE_AS_RADIANS per
	# metre); 0 when every rule holds.
	var violation: float = 0.0
	var binding: Limit = Limit.NONE

	func holds() -> bool:
		return violation <= 0.0


# How `hold` sits against every rule, for `body`, into `out`.
static func assess(body: ArmAnatomyBody, hold: Hold, out: Verdict) -> void:
	out.violation = 0.0
	out.binding = Limit.NONE
	var hand: Vector3 = hold.top_hand
	_over(out, Limit.TOP_HAND_LOW, -TOP_HAND_BELOW_HIP_M - hand.y)
	_over(out, Limit.TOP_HAND_HIGH, hand.y - (hold.top_shoulder.y - TOP_HAND_BELOW_SHOULDER_M))
	_over(out, Limit.TOP_HAND_BEHIND, hand.z - TOP_HAND_BEHIND_HIP_M)
	var own_side: float = hand.x * signf(body.top_shoulder.x)
	_over(out, Limit.TOP_HAND_OUT, own_side - TOP_HAND_OUT_M)
	_over(out, Limit.TOP_HAND_ACROSS, -own_side - TOP_HAND_ACROSS_M)
	var apart: float = body.top_shoulder.distance_to(body.bottom_shoulder) * HANDS_APART_SHOULDERS
	_over(out, Limit.HANDS_APART, hold.spacing - apart)
	var knob: Vector3 = hand - hold.shaft * body.knob_extend
	var clear: float = TorsoSection.clearance(hold.torso.affine_inverse() * knob,
			body.torso_profile, body.torso_sway, body.torso_xz_scale) \
			* hold.torso.basis.get_scale().x
	_over(out, Limit.KNOB_IN_BODY, KNOB_CLEAR_M - clear)
	var mid: Vector3 = hold.heel + hold.blade_dir * (body.blade_length * 0.5)
	var into_x: float = FOOTPRINT_HALF_WIDTH_M - absf(mid.x)
	var into_z: float = minf(mid.z + FOOTPRINT_AHEAD_M, FOOTPRINT_BACK_M - mid.z)
	_over(out, Limit.PUCK_UNDER_BODY, minf(into_x, into_z))
	var lie: float = asin(clampf(-hold.shaft.y, -1.0, 1.0))
	var off: float = absf(lie - body.blade_lie) - LIE_RIDE
	if off > out.violation:
		out.violation = off
		out.binding = Limit.LIE


# A metre past a rule weighs as ArmAnatomy weighs a metre.
static func _over(out: Verdict, limit: Limit, metres: float) -> void:
	var v: float = metres * ArmAnatomy.METRE_AS_RADIANS
	if v > out.violation:
		out.violation = v
		out.binding = limit
