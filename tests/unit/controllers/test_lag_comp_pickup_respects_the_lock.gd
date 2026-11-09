extends GutTest

# A client's pickup claim resolves after the 50 ms contest window, on the host's
# tick — after a goal crossing or a goalie's cover may already have locked the
# puck. The grant must honour that lock, as the deflect and bobble verdicts do.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")

var _pc: PuckController = null
var _puck: Puck = null
var _skater: Skater = null


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_physics_process(false)
	_skater.set_process(false)
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_puck.global_position = _skater.get_blade_contact_global()


func test_an_unlocked_puck_is_granted() -> void:
	_pc.apply_lag_comp_pickup(_skater)
	assert_eq(_puck.carrier, _skater)


func test_a_locked_puck_is_not_granted() -> void:
	_puck.pickup_locked = true
	_pc.apply_lag_comp_pickup(_skater)
	assert_null(_puck.carrier, "a claim resolving after the lock must not take the puck")
