extends GutTest

# CellyPoseRules: every celly, sampled across its window, holds a stick of the
# stick's length off a hand the arm reaches, keeps the blade out of the ice,
# never jumps between ticks, and strikes the same pose mirrored for the other
# hand.

const WINDOW_S: float = 2.5
const DT: float = 1.0 / 120.0
# Generous per-tick bounds: a pose authored to move, not one that teleports.
const HAND_STEP_MAX_M: float = 0.05
const BLADE_STEP_MAX_M: float = 0.25

var _rig := CellyPoseRules.Rig.new()
var _arms := CellyPoseRules.Arms.new()


func before_each() -> void:
	_rig = CellyPoseRules.Rig.new()
	_rig.top_shoulder = Vector3(0.22, 0.4, 0.0)
	_rig.bottom_shoulder = Vector3(-0.22, 0.4, 0.0)
	_rig.arm = 0.66
	_rig.stick = 1.3
	_rig.ice_y = -1.04


func _sample(celly: int, s: float, rig: CellyPoseRules.Rig = _rig) -> void:
	CellyPoseRules.arms(celly, s / WINDOW_S, s, rig, _arms)
	CellyPoseRules.free_hand(celly, s / WINDOW_S, s, rig, _arms.hand, _arms.blade, _arms)


func test_every_celly_holds_a_whole_stick_out_of_the_ice() -> void:
	for celly: int in CellyRegistry.count():
		var s: float = 0.0
		while s <= WINDOW_S:
			_sample(celly, s)
			assert_almost_eq(_arms.hand.distance_to(_arms.blade), _rig.stick, 0.001,
					"%s at %.2f s: a full stick from the hand" % [CellyRegistry.NAME_KEYS[celly], s])
			assert_gt(_arms.blade.y, _rig.ice_y - 0.001,
					"%s at %.2f s: the blade stays on or over the ice" % [CellyRegistry.NAME_KEYS[celly], s])
			s += 0.05


func test_every_hand_is_within_the_arm() -> void:
	for celly: int in CellyRegistry.count():
		var s: float = 0.0
		while s <= WINDOW_S:
			_sample(celly, s)
			assert_lt(_arms.hand.distance_to(_rig.top_shoulder), _rig.arm + 0.001,
					"%s at %.2f s: top hand in reach" % [CellyRegistry.NAME_KEYS[celly], s])
			assert_lt(_arms.free.distance_to(_rig.bottom_shoulder), _rig.arm + 0.001,
					"%s at %.2f s: free hand in reach" % [CellyRegistry.NAME_KEYS[celly], s])
			assert_between(_arms.free_weight, 0.0, 1.0)
			s += 0.05


func test_no_celly_jumps_between_ticks() -> void:
	for celly: int in CellyRegistry.count():
		_sample(celly, 0.0)
		var hand: Vector3 = _arms.hand
		var blade: Vector3 = _arms.blade
		var free: Vector3 = _arms.free
		var s: float = DT
		while s <= WINDOW_S:
			_sample(celly, s)
			var key: String = String(CellyRegistry.NAME_KEYS[celly])
			assert_lt(_arms.hand.distance_to(hand), HAND_STEP_MAX_M, "%s hand at %.3f s" % [key, s])
			assert_lt(_arms.free.distance_to(free), HAND_STEP_MAX_M, "%s free hand at %.3f s" % [key, s])
			assert_lt(_arms.blade.distance_to(blade), BLADE_STEP_MAX_M, "%s blade at %.3f s" % [key, s])
			hand = _arms.hand
			blade = _arms.blade
			free = _arms.free
			s += DT


func test_the_other_hand_strikes_the_mirrored_pose() -> void:
	var lefty := CellyPoseRules.Rig.new()
	lefty.top_shoulder = Vector3(-0.22, 0.4, 0.0)
	lefty.bottom_shoulder = Vector3(0.22, 0.4, 0.0)
	lefty.arm = _rig.arm
	lefty.stick = _rig.stick
	lefty.ice_y = _rig.ice_y
	var flip := Vector3(-1.0, 1.0, 1.0)
	for celly: int in CellyRegistry.count():
		for s: float in [0.3, 1.1, 1.6, 2.2]:
			_sample(celly, s)
			var hand: Vector3 = _arms.hand
			var blade: Vector3 = _arms.blade
			var free: Vector3 = _arms.free
			_sample(celly, s, lefty)
			assert_almost_eq(_arms.hand, hand * flip, Vector3.ONE * 0.0001)
			assert_almost_eq(_arms.blade, blade * flip, Vector3.ONE * 0.0001)
			assert_almost_eq(_arms.free, free * flip, Vector3.ONE * 0.0001)


func test_only_the_knee_slide_kneels() -> void:
	var body := CellyPoseRules.Body.new()
	for celly: int in CellyRegistry.count():
		CellyPoseRules.body(celly, 0.5, 1.25, body)
		assert_eq(body.kneel > 0.0, celly == CellyRegistry.KNEE_SLIDE,
				String(CellyRegistry.NAME_KEYS[celly]))
		assert_true(body.crouch >= 0.0)


# The bow hand holds the shaft: on the line the arrow is drawn along, from the
# nock through the draw.
func test_the_bow_hand_rides_the_drawn_shaft() -> void:
	for s: float in [0.8, 1.1, 1.4, 1.65]:
		_sample(CellyRegistry.BOW_AND_ARROW, s)
		var shaft: Vector3 = (_arms.blade - _arms.hand).normalized()
		var to_bow: Vector3 = _arms.free - _arms.hand
		assert_almost_eq(to_bow.cross(shaft).length(), 0.0, 0.01, "on the shaft at %.2f s" % s)
		assert_gt(to_bow.dot(shaft), 0.0, "ahead of the drawing hand")
