extends GutTest

# The stick is one rigid piece: whatever the pose, the rendered shaft runs
# exactly along the blade's hosel — no bend at the joint. Driven through the
# real controller and render pass, because the bends lived between them: the
# blade's pitch was read in the upper body's frame while its marker is levelled
# to the world, so every degree of torso lean (the reach lean, the skating fold)
# bent the joint by a degree; a constant toe-lift and the loft's toe-lift bent it
# on purpose; and a clamp on the pitch bent it whenever the shaft steepened past
# it. Measured before: 12° standing, 17.5° tucked at the feet, 20° skating.
#
# What a rigid stick does instead where the shaft is steep — stand on its toe —
# is held too: the toe never goes through the ice.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const BEND_TOLERANCE_DEG: float = 0.5


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _worst_bend: float = 0.0
var _lowest_toe: float = INF


func _make_controller(with_puck: bool) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	if with_puck:
		puck.set_carrier(skater)
		c.on_puck_picked_up_network()
	_worst_bend = 0.0
	_lowest_toe = INF
	return c


# The angle between the drawn shaft (butt → tip) and the hosel (heel → up the
# shaft, reversed), and the toe's height above the ice.
func _measure(sk: Skater) -> void:
	var shaft: Vector3 = -sk.stick_mesh.global_transform.basis.z.normalized()
	var lie: float = deg_to_rad(sk.blade_lie_deg)
	var blade_mesh: MeshInstance3D = sk._blade_mesh_instance
	var hosel: Vector3 = blade_mesh.global_transform.basis * Vector3(0.0, sin(lie), cos(lie))
	_worst_bend = maxf(_worst_bend, rad_to_deg(shaft.angle_to(-hosel)))
	var toe: Vector3 = blade_mesh.global_transform * Vector3(0.0, 0.0, -sk.blade_length)
	_lowest_toe = minf(_lowest_toe, toe.y)


# Segments of [ticks, spec]; spec keys: aim (relative to the skater), move,
# loft, shoot, slap.
func _drive(c: SkaterController, segments: Array) -> void:
	var sk: Skater = c.skater
	var input := InputState.new()
	for seg: Array in segments:
		var spec: Dictionary = seg[1]
		for t: int in int(seg[0]):
			input.delta = DT
			input.host_timestamp += DT
			input.move_vector = spec.get("move", Vector2.ZERO)
			input.mouse_world_pos = sk.global_position + (spec.get("aim", Vector3(0.0, 0.0, 3.0)) as Vector3)
			input.mouse_world_pos.y = 0.0
			input.elevation_level = spec.get("loft", 0)
			var shoot: bool = spec.get("shoot", false)
			var slap: bool = spec.get("slap", false)
			input.shoot_held = shoot
			input.shoot_pressed = shoot and t == 0
			input.slap_held = slap
			input.slap_pressed = slap and t == 0
			c._process_input(input, DT)
			sk._physics_process(DT)
			sk._process(DT)
			_measure(sk)


func _assert_rigid(what: String) -> void:
	assert_lt(_worst_bend, BEND_TOLERANCE_DEG,
			"%s: the shaft bends %.2f° off the hosel" % [what, _worst_bend])
	assert_gt(_lowest_toe, -0.002, "%s: the toe went %.3f m into the ice" % [what, -_lowest_toe])


func test_standing_with_the_reach_lean() -> void:
	var c: SkaterController = _make_controller(false)
	_drive(c, [[90, {"aim": Vector3(0.0, 0.0, 4.0)}]])
	_assert_rigid("reaching out, torso leaned")


func test_tucked_in_at_the_feet() -> void:
	var c: SkaterController = _make_controller(true)
	_drive(c, [[90, {"aim": Vector3(-0.2, 0.0, 0.4)}]])
	_assert_rigid("tucked in tight")
	var sk: Skater = c.skater
	assert_gt(sk._blade_mesh_instance.position.length(), 0.03,
			"a shaft that steep stands the blade on its toe")


func test_dangling_with_the_loft_up() -> void:
	var c: SkaterController = _make_controller(true)
	var segments: Array = []
	for k: int in 8:
		segments.append([10, {"aim": Vector3(0.8 if k % 2 == 0 else -0.8, 0.0, 1.2), "loft": 3}])
	_drive(c, segments)
	_assert_rigid("dangling at the top loft level")


func test_skating_and_sweeping_the_cursor() -> void:
	var c: SkaterController = _make_controller(false)
	_drive(c, [[60, {"move": Vector2(0.0, 1.0)}],
			[40, {"move": Vector2(0.0, 1.0), "aim": Vector3(2.5, 0.0, 1.5)}],
			[40, {"move": Vector2(0.0, 1.0), "aim": Vector3(-2.5, 0.0, 1.5)}]])
	_assert_rigid("skating, torso folded")


func test_through_both_shots() -> void:
	var c: SkaterController = _make_controller(true)
	_drive(c, [[20, {"aim": Vector3(-0.4, 0.0, 1.6)}],
			[45, {"aim": Vector3(-1.4, 0.0, 3.0), "shoot": true}],
			[20, {"aim": Vector3(-1.4, 0.0, 3.0)}]])
	_assert_rigid("wrister")
	c = _make_controller(true)
	_drive(c, [[20, {"aim": Vector3(-0.4, 0.0, 1.6)}],
			[60, {"aim": Vector3(-0.8, 0.0, 3.2), "slap": true}],
			[25, {"aim": Vector3(-0.8, 0.0, 3.2)}]])
	_assert_rigid("slapshot")
