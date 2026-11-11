extends GutTest

# One non-finite frame must cost one frame. The drawn stick and both arms hang
# from render-rate state carried frame to frame — the shaft's clearance spring
# (SkaterIKCoordinator._shaft_clearance) and the shaft's own transform, which
# the gloves take their axis from (SkaterStickRig.grip_axis) — so a NaN that
# reaches either is kept, and the skater skates the rest of the match with no
# stick and no arms. This poisons the top hand marker for one frame and holds
# that every drawn piece is back the frame after.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _controller: SkaterController
var _input: InputState


func _stand_up(native: bool) -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	_skater._arms.native_enabled = native
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_input = InputState.new()


# Skating ahead with the blade out to the forehand, so the stick, both hands and
# the clearance spring are all live.
func _tick(poison: bool = false) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = Vector2(0.0, -1.0)
	_input.mouse_world_pos = _skater.global_position + Vector3(1.0, 0.0, -2.0)
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)
	if poison:
		_skater.top_hand.position = Vector3(NAN, NAN, NAN)
	_skater._process(DT)


static func _finite(xf: Transform3D) -> bool:
	return xf.origin.is_finite() and xf.basis.x.is_finite() \
			and xf.basis.y.is_finite() and xf.basis.z.is_finite()


func _poisoned_bones() -> String:
	var body: Skeleton3D = _skater._arms._skeleton
	var bad: String = ""
	for b: int in body.get_bone_count():
		if not _finite(body.get_bone_pose(b)):
			bad += body.get_bone_name(b) + " "
	return bad


func _one_bad_frame(native: bool) -> void:
	_stand_up(native)
	for t: int in 60:
		_tick()
	_tick(true)
	assert_false(_skater.drawn_top_hand().is_finite(), "the poison reached the drawn hand")
	# The bad frame's own complaints are the point of it; any after it are not.
	for err: Variant in get_errors():
		err.handled = true
	_tick()
	assert_true(_skater.drawn_top_hand().is_finite(), "the drawn top hand is back")
	assert_true(_skater.bottom_hand.position.is_finite(), "the bottom hand is back")
	assert_true(_finite(_skater.stick_mesh.transform), "the shaft is back")
	assert_eq(_poisoned_bones(), "", "every bone is back")


func test_one_bad_frame_costs_one_frame() -> void:
	_one_bad_frame(true)


func test_one_bad_frame_costs_one_frame_on_the_gdscript_arms() -> void:
	_one_bad_frame(false)
