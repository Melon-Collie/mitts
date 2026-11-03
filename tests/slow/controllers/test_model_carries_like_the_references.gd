extends GutTest

# The arm anatomy model's own carry for each reference's puck
# (tests/harness/arm_reference_carries.gd) is held as a player holds it, as the
# user accepted on the sheets (.claude/hooks/render-references.sh, bottom rows):
# the top hand near the reference's, the hands apart rather than glove to
# glove, and the bottom arm come down to the shaft with its elbow back and
# down, not raised across the chest. The envelope table is derived from these
# picks, so they are what the carry draws. docs/arm-anatomy-plan.md §16.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const Carries := preload("res://tests/harness/arm_reference_carries.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# How far the model's top hand may sit from the reference's (m), how far its
# hands' spacing from the reference's, and the closest its hands may come.
const TOP_HAND_M: float = 0.35
const SPACING_M: float = 0.15
const HANDS_APART_MIN_M: float = 0.2
# The bottom elbow's bend off the shoulder-to-hand line, unit: no further ahead
# than this (it points back), no higher than this (it hangs).
const ELBOW_AHEAD_MAX: float = -0.5
const ELBOW_UP_MAX: float = 0.1


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


# Which way `arm`'s elbow points off the line from its shoulder to its hand, in
# the hips' frame: (out to its own side, up, ahead).
static func _elbow_points(arm: ArmAnatomy.ArmPose) -> Vector3:
	var chord: Vector3 = (arm.hand - arm.root).normalized()
	var bend: Vector3 = arm.elbow - arm.root
	bend = (bend - chord * bend.dot(chord)).normalized()
	return Vector3(bend.x * signf(arm.root.x), bend.y, -bend.z)


func test_the_models_own_carries_are_the_references() -> void:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater._process(DT)
	var body: ArmAnatomyBody = SkaterAnatomyCapture.capture(c)
	var trunk: ArmAnatomySearch.TrunkState = SkaterAnatomyCapture.trunk_state(skater, body)
	trunk.crouch_max = ArmAnatomySearch.DEEPEST_STANCE_M
	var search := ArmAnatomySearch.new(body)
	search.technique = true
	var pivot: float = SkaterAnatomyCapture.pivot_height(skater)
	var own := ArmAnatomySearch.Pose.new()
	for carry: Dictionary in Carries.CARRIES:
		var what: String = carry["name"]
		var s: Dictionary = Carries.setup(carry, body, pivot, c.blade_height)
		search.solve(trunk, s["heel"], own)
		assert_true(own.feasible(), what + ": held")
		var hand: Vector3 = own.top.hand - Vector3.UP * own.crouch
		assert_lt(hand.distance_to(s["hand"]), TOP_HAND_M, what + ": the top hand near the reference's")
		assert_gte(own.spacing, HANDS_APART_MIN_M, what + ": the hands apart")
		assert_almost_eq(own.spacing, float(carry["spacing_m"]), SPACING_M,
				what + ": as far apart as the reference's")
		var elbow: Vector3 = _elbow_points(own.bottom)
		assert_lt(elbow.z, ELBOW_AHEAD_MAX, what + ": the bottom elbow back, %s" % elbow)
		assert_lt(elbow.y, ELBOW_UP_MAX, what + ": the bottom elbow not raised, %s" % elbow)
