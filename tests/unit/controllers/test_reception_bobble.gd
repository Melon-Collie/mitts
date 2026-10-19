extends GutTest

# The near-miss bobble through the host's real present-time detection
# (PuckController._check_interactions): a puck fired square at a standing
# receiver's blade, through its middle or its toe. The middle holds what the
# toe can't; past the bobble line the puck dies by his stick, nobody's.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")

var _pc: PuckController = null
var _puck: Puck = null
var _receiver: Skater = null


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_receiver = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_receiver)
	_receiver.global_position = Vector3(0.0, 0.0, -8.0)
	_receiver.set_physics_process(false)
	_receiver.set_process(false)
	_receiver.capture_prev_blade_contact()   # a still blade
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_pc.set_team_id_by_skater({_receiver: 0})
	_pc.set_skater_getter(func() -> Array: return [_receiver])
	_pc.set_peer_id_resolver(func(_s: Skater) -> int: return 2)


# Fires the puck square onto the blade at `speed`, along the face normal, with
# its line `along` metres toward the toe from the blade's middle.
func _fire(speed: float, along: float) -> void:
	var mid: Vector3 = _receiver.get_blade_contact_global()
	var axis: Vector3 = PuckReceptionRules.blade_axis(mid,
			_receiver.top_hand.global_position, Vector3.FORWARD)
	var normal := Vector3(-axis.z, 0.0, axis.x)
	var line: Vector3 = Vector3(mid.x, _puck.ice_height, mid.z) + axis * along
	_pc._prev_puck_pos = line + normal * 0.8
	_puck.set_puck_position(line + normal * 0.05)
	_puck.set_puck_velocity(-normal * speed)
	_pc._check_interactions()


func test_a_hard_pass_held_at_the_middle() -> void:
	_fire(20.0, 0.0)
	assert_eq(_puck.carrier, _receiver, "square at 20 m/s, the middle holds it")


func test_the_same_pass_off_the_toe_bobbles_by_his_stick() -> void:
	_fire(20.0, 0.14)
	assert_null(_puck.carrier, "off the toe it bobbles")
	var exit: float = _puck.get_puck_velocity().length()
	assert_between(exit, _puck.bobble_exit_min - 0.01, _puck.bobble_exit_max + 0.01,
			"it dies by his stick")
	assert_true(_puck.is_on_cooldown(_receiver), "his hands are blown open: he can't play it yet")


func test_harder_still_bobbles_even_at_the_middle() -> void:
	_fire(26.0, 0.0)
	assert_null(_puck.carrier)
	assert_lt(_puck.get_puck_velocity().length(), _puck.bobble_exit_max + 0.01)


func test_a_soft_pass_holds_anywhere_on_the_blade() -> void:
	_fire(12.0, 0.14)
	assert_eq(_puck.carrier, _receiver)
