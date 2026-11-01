extends RefCounted

# Carries we know players hold, the ground truth the arm anatomy model is
# calibrated on (docs/arm-anatomy-plan.md §12): for a 6'1" player, where the
# puck is, where the top hand is, how far down the shaft the bottom hand holds,
# and how the body sits. Agreed with the user, adjustable by eye against
# .claude/hooks/render-references.sh. test_arm_reference_carries.gd holds the
# model to them.
#
# Distances off the middle of the body in his facing frame: +x toward his
# top hand's side (his backhand), y up off the ice, +z ahead. Angles round
# from straight ahead, + toward the forehand.

const CARRIES: Array[Dictionary] = [
	{"name": "forehand", "puck_deg": 30.0, "puck_m": 0.9, "fold_deg": 30.0,
		"crouch_m": 0.1, "twist_deg": 15.0, "top_hand": Vector3(0.1, 0.95, 0.25),
		"spacing_m": 0.35},
	{"name": "ahead", "puck_deg": 0.0, "puck_m": 1.0, "fold_deg": 30.0,
		"crouch_m": 0.1, "twist_deg": 0.0, "top_hand": Vector3(0.0, 0.95, 0.3),
		"spacing_m": 0.35},
	{"name": "backhand", "puck_deg": -60.0, "puck_m": 0.8, "fold_deg": 30.0,
		"crouch_m": 0.1, "twist_deg": -30.0, "top_hand": Vector3(0.3, 0.95, 0.1),
		"spacing_m": 0.3},
	{"name": "wide_forehand", "puck_deg": 60.0, "puck_m": 1.3, "fold_deg": 40.0,
		"crouch_m": 0.1, "twist_deg": 30.0, "top_hand": Vector3(0.0, 1.05, 0.3),
		"spacing_m": 0.45},
	{"name": "tight", "puck_deg": 20.0, "puck_m": 0.6, "fold_deg": 20.0,
		"crouch_m": 0.1, "twist_deg": 10.0, "top_hand": Vector3(0.15, 1.05, 0.15),
		"spacing_m": 0.2},
	{"name": "long_reach", "puck_deg": 0.0, "puck_m": 1.5, "fold_deg": 45.0,
		"crouch_m": 0.15, "twist_deg": 0.0, "top_hand": Vector3(0.0, 0.8, 0.45),
		"spacing_m": 0.4},
]


# One carry as the model's search takes it (ArmAnatomySearch.hold), for `body`
# standing with its trunk's pivot `pivot_m` above the ice and its blade
# `blade_m` above it: the heel (hips frame), the stick's lie and heading, the
# twist, the lean (the whole fold, from upright), the crouch, the spacing, and
# where the puck the reference names is, for the heel's distance off it. The
# stick runs from the top hand toward the puck at its own length, so the heel
# lands where a rigid stick from that hand puts it.
static func setup(carry: Dictionary, body: ArmAnatomyBody, pivot_m: float,
		blade_m: float) -> Dictionary:
	var top_side: float = signf(body.top_shoulder.x)
	var h: Vector3 = carry["top_hand"]
	var hand := Vector3(h.x * top_side, h.y - pivot_m, -h.z)
	var a: float = deg_to_rad(float(carry["puck_deg"]))
	var puck := Vector3(-sin(a) * float(carry["puck_m"]) * top_side, blade_m - pivot_m,
			-cos(a) * float(carry["puck_m"]))
	var drop: float = minf(hand.y - puck.y, body.stick_length * 0.999)
	var across := Vector2(puck.x - hand.x, puck.z - hand.z).normalized()
	var reach: float = sqrt(body.stick_length * body.stick_length - drop * drop)
	var heel := Vector3(hand.x + across.x * reach, puck.y, hand.z + across.y * reach)
	var shaft: Vector3 = (heel - hand).normalized()
	return {"heel": heel, "lie": asin(-shaft.y), "heading": atan2(shaft.x, -shaft.z),
		# A turn about +Y turns the chest toward -X, the forehand's side when the
		# top hand is on +X.
		"twist": deg_to_rad(float(carry["twist_deg"])) * top_side,
		"lean": Vector2(deg_to_rad(float(carry["fold_deg"])), 0.0),
		"crouch": float(carry["crouch_m"]), "spacing": float(carry["spacing_m"]),
		"puck": puck, "hand": hand}
