extends GutTest

# ── THE STAND-UP SAVE ────────────────────────────────────────────────────────
# A low shot he has read onto a pad face is saved on his feet. Standing pads run
# from the ice to the pad-top seam; the butterfly would only add width he does
# not need there, and cost the height above it and a 0.2 s drop. The five-hole
# and the ice outside the pads still get the butterfly.
#
# ── WHAT IT MEASURED (2026-09) ───────────────────────────────────────────────
# 28 m/s flat and low shots, 9 aims across the mouth, centre lane and 3 m off it,
# 4-16 m. Upper case = down at contact.
#
#   cold release, 12 m centre, flat   before SSSSSSSSS   after SSSsSsSSS
#   telegraphed,  12 m centre, flat   before SSSSSSSSS   after SSSsSsSSS
#   late swing,    6 m centre, flat   before SSSSSGSSS   after SSSSSGSSS
#
# The two pad-face aims stay up once the read has converged. Across the cold
# grid goals go 11 -> 7 and none is added: the four he stops are pad-face shots
# at 4-6 m that used to score THROUGH the drop — the pads mid-rotation on a puck
# that was already on them. Everything left is the five-hole, the posts and the
# 9 m low corners, as before. The late swing reads exactly as before: a stale
# belief is not a converged one, so he hedges into the butterfly and deception
# pays what it paid.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const MAX_AIM: float = GameRules.NET_HALF_WIDTH \
		- GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
const SPEED: float = 28.0
const PAD_FACE_AIM: float = 0.25

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_ctrl)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)


func _cold(spot: Vector3, aim_x: float, loft: int) -> int:
	_h.settle_ready(spot)
	return _h.fire_release_at(spot, Vector3(aim_x, 0.0, GOAL_Z), loft, SPEED, 0.0)


func _stayed_up() -> bool:
	return _ctrl._sm.is_upright()


func test_a_long_shot_into_his_pad_is_saved_standing() -> void:
	var spot := Vector3(0.0, 0.0, GOAL_Z + 12.0)
	for aim_x: float in [-PAD_FACE_AIM, PAD_FACE_AIM]:
		for loft: int in [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW]:
			assert_eq(_cold(spot, aim_x, loft), Harness.SAVE)
			assert_true(_stayed_up(), "aim %.2f loft %d: on the pad, no drop" % [aim_x, loft])


func test_the_five_hole_and_the_corners_still_get_the_butterfly() -> void:
	var spot := Vector3(0.0, 0.0, GOAL_Z + 12.0)
	for aim_x: float in [0.0, -MAX_AIM * 0.8, MAX_AIM * 0.8]:
		_cold(spot, aim_x, ShotMechanics.ELEVATION_FLAT)
		assert_false(_stayed_up(), "aim %.2f is not on a pad face" % aim_x)


func test_a_late_swing_onto_the_pad_still_drops_him() -> void:
	# Declared at the far post for the whole wind-up, released onto the pad. His
	# belief is stale at the drop, so he hedges wide — the read is not converged.
	var spot := Vector3(0.0, 0.0, GOAL_Z + 6.0)
	_h.settle_ready(spot)
	_h.hold_windup_at(spot, Vector3(-MAX_AIM, 0.0, GOAL_Z), ShotMechanics.ELEVATION_FLAT,
			SPEED, 60)
	_h.fire_release_at(spot, Vector3(PAD_FACE_AIM, 0.0, GOAL_Z),
			ShotMechanics.ELEVATION_FLAT, SPEED, 0.0)
	assert_false(_stayed_up())


# Standing up for the pad-face shots must not open anything: the grid concedes
# no more with the rule than without it.
func test_standing_up_opens_nothing() -> void:
	var goals := {false: 0, true: 0}
	for flag: bool in [false, true]:
		_ctrl.stand_up_low_saves = flag
		for dist: float in [4.0, 6.0, 9.0, 12.0, 16.0]:
			for lane: float in [0.0, 3.0]:
				var spot := Vector3(lane, 0.0, GOAL_Z + dist)
				for loft: int in [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW]:
					for ai: int in 9:
						if _cold(spot, lerpf(-MAX_AIM, MAX_AIM, ai / 8.0), loft) == Harness.GOAL:
							goals[flag] += 1
	gut.p("low-shot goals: always drop %d, stand-up %d" % [goals[false], goals[true]])
	assert_lte(goals[true], goals[false])
