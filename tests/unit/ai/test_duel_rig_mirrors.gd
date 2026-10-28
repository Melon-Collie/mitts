extends GutTest

# The duel harness's arm (duel_rig.gd) resolves a cursor to the blade it reaches
# for as the live SkaterIKCoordinator does, on the same set-up body: the range of
# motion, the carry's two hands and backhand stop, and the rest reach without a
# puck to reach for. At rest, so the twist and lean are the coordinator's own
# zeros. Its release keeps the skater's motion as the controller's does, and its
# body blocks a loose puck in the band the live skater's does.

const DuelRig := preload("res://tests/unit/ai/duel_rig.gd")
const DuelHarness := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = 1.0 / 120.0

var _skater: Skater
var _puck: Puck
var _ctrl: SkaterController
var _rig: RefCounted


func before_each() -> void:
	_skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	_puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	var state := DuelHarness.StubGameState.new()
	_ctrl = SkaterController.new()
	_skater.is_left_handed = false
	for n: Node in [_puck, _skater, state, _ctrl]:
		add_child_autofree(n)
		n.set_process(false)
		n.set_physics_process(false)
	_ctrl.setup(_skater, _puck, state)
	# A skater's origin rides at FACEOFF_SPAWN_HEIGHT in play.
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_rig = DuelRig.capture(_skater, _ctrl)


func _resolves_alike(carrying: bool, puck_at: Vector3) -> void:
	_ctrl.has_puck = carrying
	_puck.global_position = puck_at
	var pos := Vector3(_skater.global_position.x, 0.0, _skater.global_position.z)
	var body := Basis.IDENTITY
	var worst: float = 0.0
	var worst_at := Vector3.ZERO
	for deg: int in range(-170, 171, 20):
		for dist: float in [0.8, 1.5, 3.0]:
			var a: float = deg_to_rad(float(deg))
			var cursor: Vector3 = pos + Vector3(sin(a), 0.0, -cos(a)) * dist
			_ctrl._ik.apply_blade_toward(cursor, DT)
			var live: Vector3 = _ctrl._ik.last_target_blade_world
			var arm: DuelRig.Arm = DuelRig.Arm.new()
			var ub: Transform3D = _rig.ub_transform(arm, pos, body)
			var purpose: float = 1.0 if carrying else _ctrl._ik.reach_purpose
			var mine: Vector3 = _rig.resolve(arm, ub, body, pos, cursor, carrying, purpose,
					1.0, _skater.get_carry_forehand_factor())
			var gap: float = Vector2(live.x - mine.x, live.z - mine.z).length()
			if gap > worst:
				worst = gap
				worst_at = cursor
	assert_lt(worst, 0.01, "carrying %s, puck at %s: worst %.3f m at cursor %s" % [
			carrying, puck_at, worst, worst_at])


func test_an_empty_stick_reaching_for_a_puck_resolves_as_the_coordinator_does() -> void:
	_resolves_alike(false, Vector3(0.5, 0.0, -1.0))


func test_an_empty_stick_at_rest_resolves_as_the_coordinator_does() -> void:
	_resolves_alike(false, Vector3(0.0, 0.0, -20.0))


func test_a_carried_blade_resolves_as_the_coordinator_does() -> void:
	_resolves_alike(true, Vector3.ZERO)


func test_a_release_keeps_the_skaters_motion_as_the_controller_does() -> void:
	for body_vel: Vector3 in [Vector3(0, 0, -7), Vector3(5, 0, -3), Vector3(-6, 0, 2)]:
		for is_pass: bool in [false, true]:
			var dir := Vector3(0.8, 0.12, -0.6).normalized()
			var ctrl_result := ShotMechanics.ShotResult.make(dir, 14.0)
			var harness_result := ShotMechanics.ShotResult.make(dir, 14.0)
			_skater.velocity = body_vel
			_ctrl._carry_momentum(ctrl_result, is_pass)
			DuelHarness._carry_momentum(harness_result, body_vel, is_pass)
			assert_almost_eq(harness_result.direction * harness_result.power,
					ctrl_result.direction * ctrl_result.power, Vector3.ONE * 0.0001,
					"skating %s, pass %s" % [body_vel, is_pass])


func test_the_body_blocks_in_the_band_the_skater_does() -> void:
	var body: RefCounted = (load("res://tests/unit/ai/duel_body.gd") as GDScript).capture(
			_skater, _ctrl, _puck)
	var band: Vector2 = _skater.get_body_block_y_range()
	var reach: float = _skater.get_body_block_radius() + GameRules.PUCK_COLLISION_RADIUS
	var at := Vector3(_skater.global_position.x, 0.0, _skater.global_position.z)
	for y: float in [band.x - 0.02, band.x + 0.02, band.y - 0.02, band.y + 0.02]:
		for off: float in [reach - 0.02, reach + 0.02]:
			var prev := Vector3(at.x + off, 0.0, at.z - 1.0)
			var curr := Vector3(at.x + off, 0.0, at.z + 1.0)
			var live: bool = PuckInteractionRules.check_body_block(Vector3(prev.x, y, prev.z),
					Vector3(curr.x, y, curr.z), Vector2(at.x, at.z), reach, band.x, band.y)
			assert_eq(body.blocks(prev, curr, y, y, at), live,
					"a puck %.2f m up, %.2f m off his axis" % [y, off])
