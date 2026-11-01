extends GutTest

# The arm anatomy model holds the carries players hold
# (tests/harness/arm_reference_carries.gd): each reference, its hands, stick and
# stance as given, held by a body's arms within their ranges and as players
# hold a stick (ArmTechnique), only the arms' own freedoms (the elbows round
# their circles, the fists round the shaft) left to the model.
# .claude/hooks/render-references.sh draws what it makes of each.
#
# The model is being calibrated against them (docs/arm-anatomy-plan.md §14): a
# carry is held to it once it is in CALIBRATED, and until then reports what
# stops it as pending.
const CALIBRATED: Array[String] = []

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const Carries := preload("res://tests/harness/arm_reference_carries.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func test_the_model_holds_every_reference_carry() -> void:
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
	trunk.crouch_max = 1.0
	var search := ArmAnatomySearch.new(body)
	search.technique = true
	var pose := ArmAnatomySearch.Pose.new()
	for carry: Dictionary in Carries.CARRIES:
		var s: Dictionary = Carries.setup(carry, body, SkaterAnatomyCapture.pivot_height(skater),
				c.blade_height)
		search.hold(trunk, s["heel"], s["twist"], s["lie"], s["heading"], s["spacing"], pose,
				s["lean"], s["crouch"])
		var why: String = ArmAnatomySearch.Limit.keys()[pose.trunk_binding] \
				if pose.binding_arm < 0 else "%s %s" % ["top" if pose.binding_arm == 0
				else "bottom", ArmAnatomy.Limit.keys()[pose.arm_binding]]
		if pose.trunk_binding == ArmAnatomySearch.Limit.TECHNIQUE:
			why = ArmTechnique.Limit.keys()[pose.technique.binding]
		var what: String = "%s: held (%s +%.0f°)" % [carry["name"], why,
				rad_to_deg(pose.violation)]
		if CALIBRATED.has(String(carry["name"])):
			assert_true(pose.feasible(), what)
		elif not pose.feasible():
			pending(what)
