extends GutTest

# The tutorial teleports the puck two ways: a grant onto a carrier who may be
# across the rink (tutorial_give_puck), and parking it loose somewhere
# (tutorial_place_puck). The host's swept interaction tests read the puck's travel
# since last tick, so a teleport that leaves the sweep origin behind has the next
# tick sweep the whole jump — an opposing blade at the far end strips a grant
# straight back off, and any blade there collects a parked puck. This drives the
# real present-time detection (PuckController._check_interactions) with the puck
# starting on that blade.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")

var _pc: PuckController = null
var _puck: Puck = null
var _receiver: Skater = null
var _bystander: Skater = null


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)

	_receiver = _spawn_skater(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, -8.0))
	_bystander = _spawn_skater(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 5.0))

	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	# Opposing teams, so the bystander's blade is allowed to poke the receiver.
	_pc.set_team_id_by_skater({_receiver: 1, _bystander: 0})
	_pc.set_skater_getter(func() -> Array: return [_receiver, _bystander])
	_pc.set_peer_id_resolver(func(s: Skater) -> int: return 1 if s == _bystander else 2)

	# The puck was last seen on the bystander's blade (a shot they just caught).
	_puck.global_position = _bystander.get_blade_contact_global()
	_pc._prev_puck_pos = _puck.global_position


func _spawn_skater(pos: Vector3) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.global_position = pos
	s.set_physics_process(false)
	s.set_process(false)
	return s


func test_a_bare_grant_is_stripped_by_its_own_jump() -> void:
	# The control: grant without restarting the sweep, then pin the puck the way
	# the host drive does next tick. The swept segment starts on the bystander's
	# blade, so the poke lands — the assertion below is about the restart, not
	# about geometry that could never have hit.
	_pc.apply_lag_comp_pickup(_receiver)
	_puck.global_position = _puck.pinned_position()
	_pc._check_interactions()
	assert_null(_puck.carrier, "sweeping the jump should read as a poke off the bystander's blade")


func test_a_scripted_grant_survives_the_next_tick() -> void:
	_pc.apply_scripted_grant(_receiver)
	_pc._check_interactions()
	assert_eq(_puck.carrier, _receiver, "a teleport grant must not be stripped by blades along the jump")


func test_a_scripted_grant_lands_the_puck_on_the_blade() -> void:
	_pc.apply_scripted_grant(_receiver)
	assert_eq(_puck.get_puck_position(), _puck.pinned_position(),
			"the puck should land on the new carrier's blade in the same call")


# Far off-rink, where the tutorial parks the puck between steps.
const _PARKED: Vector3 = Vector3(100.0, 0.05, 100.0)


func test_a_bare_park_is_collected_along_its_jump() -> void:
	# The control for the park, same purpose as the grant's: the puck lands a
	# hundred metres from anyone, so only the swept jump can reach the bystander.
	_puck.stage_at(_PARKED)
	_pc._check_interactions()
	assert_eq(_puck.carrier, _bystander, "sweeping the jump should hand the puck to the bystander's blade")


func test_a_scripted_park_stays_parked() -> void:
	_pc.stage_scripted(_PARKED)
	_pc._check_interactions()
	assert_null(_puck.carrier, "a parked puck must not be collected by blades along the jump")
	assert_eq(_puck.get_puck_position(), _PARKED, "the puck should land where it was parked")


func test_a_scripted_park_drops_the_carrier() -> void:
	_pc.apply_scripted_grant(_receiver)
	_pc.stage_scripted(_PARKED)
	assert_null(_puck.carrier, "parking takes the puck off whoever held it")
