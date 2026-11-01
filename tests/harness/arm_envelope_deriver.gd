extends RefCounted

# How the carry's envelope (ArmEnvelope) is derived from the model, one build
# and trunk state at a time: a real skater of that height carrying, standing or
# skating, his body read into the model, and each blade position round him asked
# of ArmAnatomySearch with technique on, his trunk read as gameplay holds it
# with the puck there (the fold, the crouch, the lean toward the hand that
# buys a far reach its reach). The
# derivation instrument (tests/instruments/actors/test_derive_arm_envelope.gd)
# writes the table with it; test_arm_envelope_is_current.gd re-derives a few
# cells with it to hold the table to the model.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SETTLE_TICKS: int = 120


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var controller: SkaterController
var _body: ArmAnatomyBody
var _trunk: ArmAnatomySearch.TrunkState
var _hips: Transform3D
var _root: Transform3D
var _forehand: float = 1.0
var _skating: bool = false
var _search: ArmAnatomySearch
var _pose := ArmAnatomySearch.Pose.new()


# A skater `height` inches tall settled into a carry, standing or skating, his
# nodes added under `parent` through `add` (a GutTest's add_child_autofree).
func _init(height: int, skating: bool, add: Callable) -> void:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add.call(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add.call(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add.call(gs)
	controller = SkaterController.new()
	add.call(controller)
	controller.setup(skater, puck, gs)
	controller.apply_attributes(PlayerAttributes.new(height))
	# The closed-form carry: the trunk the table is derived in must not depend on
	# the table.
	controller._ik.derived_carry_enabled = false
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater._process(DT)
	_body = SkaterAnatomyCapture.capture(controller)
	_forehand = signf(_body.bottom_shoulder.x)
	_skating = skating
	controller.has_puck = true
	controller._sm.set_state(SkaterStateMachine.State.SKATING_WITH_PUCK)
	_search = ArmAnatomySearch.new(_body)
	_search.technique = true


# The table's cell for the blade `radius` m out at `angle_deg` off the facing (+
# forehand): [held, top hand x (+ forehand), y, z, bottom hand spacing], the
# hand in the skater's root frame.
func cell(angle_deg: float, radius: float) -> Array:
	var a: float = deg_to_rad(angle_deg)
	_settle(Vector2(sin(a) * radius * _forehand, -cos(a) * radius))
	var skater: Skater = controller.skater
	_trunk = SkaterAnatomyCapture.trunk_state(skater, _body)
	_hips = SkaterAnatomyCapture.hips_frame(skater)
	_root = skater.global_transform
	var heel: Vector3 = _root * Vector3(sin(a) * radius * _forehand, 0.0, -cos(a) * radius)
	heel.y = controller.blade_height
	_search.solve(_trunk, _hips.affine_inverse() * heel, _pose)
	if not _pose.feasible():
		return [0, 0.0, 0.0, 0.0, 0.0]
	var hand: Vector3 = _root.affine_inverse() * (_hips * _pose.top.hand)
	return [1, snappedf(hand.x * _forehand, 0.0001), snappedf(hand.y, 0.0001),
			snappedf(hand.z, 0.0001), snappedf(_pose.spacing, 0.0001)]


# The carry settled with the cursor `cursor` off him (facing frame, m).
func _settle(cursor: Vector2) -> void:
	var c: SkaterController = controller
	var skater: Skater = c.skater
	var skating: bool = _skating
	for _i: int in SETTLE_TICKS:
		skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		if not skating:
			skater.velocity = Vector3.ZERO
		c._pose.facing = Vector2(0.0, -1.0)
		skater.set_facing(c._pose.facing)
		var input := InputState.new()
		input.delta = DT
		input.move_vector = Vector2(0.0, -1.0) if skating else Vector2.ZERO
		input.mouse_world_pos = skater.global_position + Vector3(cursor.x, 0.0, cursor.y)
		input.mouse_world_pos.y = 0.0
		skater.capture_prev_blade_contact()
		c._process_input(input, DT)
		skater._physics_process(DT)
		skater._process(DT)
