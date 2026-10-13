extends GutTest

# A diver against the puck (PuckController._check_interactions): his body, lying
# along his layout, blocks a puck along the ice and lets one over it go through;
# his stick knocks a loose puck away and catches nothing. Real Skater and Puck
# scenes, never ticked by a controller, as in test_stick_tie.gd.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")

var _puck: Puck = null
var _diver: Skater = null
var _pc: PuckController = null


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_diver = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_diver)
	_diver.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_diver.set_physics_process(false)
	_diver.set_process(false)
	_diver.is_diving = true
	_diver.is_knocked_down = true
	_diver.dive_layout = Vector2(1.0, 0.0)
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_pc.set_team_id_by_skater({_diver: 0})
	_pc.set_skater_getter(func() -> Array: return [_diver])
	_pc.set_peer_id_resolver(func(_s: Skater) -> int: return 2)


# A puck crossing the lying body a metre out along it, at `height` over the ice.
func _shot_across_the_body(height: float) -> Vector3:
	var y: float = _puck.ice_height + height
	_pc._prev_puck_pos = Vector3(1.0, y, -0.3)
	_puck.global_position = Vector3(1.0, y, 0.3)
	_puck.linear_velocity = Vector3(0.0, 0.0, 20.0)
	return _puck.linear_velocity


func test_the_lying_body_blocks_a_puck_along_the_ice() -> void:
	var v: Vector3 = _shot_across_the_body(0.0)
	_pc._check_interactions()
	assert_lt(_puck.linear_velocity.z, v.z * 0.5, "turned back and dampened")


func test_a_puck_over_the_lying_body_goes_through() -> void:
	var v: Vector3 = _shot_across_the_body(DiveRules.SEAL_HEIGHT_M + 0.15)
	_pc._check_interactions()
	assert_eq(_puck.linear_velocity, v, "the dive concedes the air")


func test_a_standing_skater_there_does_not_block_it() -> void:
	_diver.is_diving = false
	_diver.is_knocked_down = false
	var v: Vector3 = _shot_across_the_body(0.0)
	_pc._check_interactions()
	assert_eq(_puck.linear_velocity, v, "the control: a metre out, nothing is there")


func test_the_divers_stick_knocks_a_puck_away_and_catches_nothing() -> void:
	var drop: float = _diver.get_blade_contact_global().y - _puck.ice_height
	_diver.global_position.y -= drop
	var blade: Vector3 = _diver.get_blade_contact_global()
	var face: Vector3 = _diver.get_blade_face_normal(Vector3(0.0, 0.0, -6.0))
	_puck.global_position = blade
	_puck.linear_velocity = -face * 6.0
	_pc._prev_puck_pos = blade + face * 0.2
	var v: Vector3 = _puck.linear_velocity
	_pc._check_interactions()
	assert_null(_puck.carrier, "a diver catches nothing")
	assert_ne(_puck.linear_velocity, v, "his stick knocked it away")
