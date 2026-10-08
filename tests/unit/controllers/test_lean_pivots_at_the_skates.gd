extends GutTest

# The balance lean tips the body about the ice under the skater, so the blades
# stay where they are and the body goes over them — and the hands and stick go
# with it, because the gameplay frames translate with the lean (docs/
# skater-animation-plan.md §16). Stepped in the tick and replicated, so it is
# gameplay geometry and holds the rules that come with that.

const DT: float = 1.0 / 120.0
const UpperBone = SkaterMeshBuilder.UpperBone
const LegBone = SkaterMeshBuilder.LegBone


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _input := InputState.new()


func _rig(z: float) -> SkaterController:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(50.0, 0.0, 50.0)
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, z)
	sk.set_process(false)
	sk.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(sk, puck, state)
	c.set_process(false)
	c.set_physics_process(false)
	return c


func _tick(c: SkaterController, move: Vector2, count: int) -> void:
	for _i: int in count:
		_input.delta = DT
		_input.host_timestamp += DT
		_input.move_vector = move
		var v: Vector3 = c.skater.velocity
		var ahead: Vector3 = Vector3(v.x, 0.0, v.z).normalized() * 3.0 \
				if v.length() > 0.5 else Vector3(0.0, 0.0, -3.0)
		_input.mouse_world_pos = c.skater.global_position + ahead
		c._process_input(_input, DT)
		c.skater._physics_process(DT)
		c.skater._process(DT)


# Lateral offset (toward the turn's inside, +) of a skeleton-space point from
# the skater's own position.
func _inside(c: SkaterController, p: Vector3, turn_right: bool) -> float:
	var vl: Vector3 = c.skater.global_transform.basis.inverse() * c.skater.velocity
	var right: Vector3 = Vector3(vl.x, 0.0, vl.z).normalized().cross(Vector3.UP)
	return p.dot(right) * (1.0 if turn_right else -1.0)


func _bone(c: SkaterController, bone: int) -> Vector3:
	var body: Skeleton3D = c.skater.mesh_root.get_node("BodyRig") as Skeleton3D
	return body.get_bone_global_pose(bone).origin


func test_a_hard_turn_leans_the_body_over_planted_skates() -> void:
	var c: SkaterController = _rig(20.0)
	_tick(c, Vector2(0.0, -1.0), 240)
	_tick(c, Vector2(1.0, 0.0), 80)
	var off: int = SkaterBodySkeleton.LEG_BONE_OFFSET
	var skates: Vector3 = (_bone(c, off + LegBone.FOOT_L) + _bone(c, off + LegBone.FOOT_R)) * 0.5
	var chest: Vector3 = _bone(c, UpperBone.TORSO)
	var lean: float = rad_to_deg(c.skater.balance_tilt().length())
	gut.p("hard turn: lean %.0f°, skates %+.2f m, chest %+.2f m into the turn" % [
			lean, _inside(c, skates, true), _inside(c, chest, true)])
	assert_gt(lean, 20.0, "a hard turn leans")
	assert_lt(absf(_inside(c, skates, true)), 0.2, "the skates stay under the skater")
	assert_gt(_inside(c, chest, true), 0.35, "and the body goes over into the turn")


func test_the_hands_go_with_the_shoulders() -> void:
	var c: SkaterController = _rig(20.0)
	_tick(c, Vector2(0.0, -1.0), 240)
	_tick(c, Vector2(1.0, 0.0), 80)
	var sk: Skater = c.skater
	var spine: Transform3D = (sk.mesh_root.get_node("BodyRig") as Skeleton3D) \
			.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	for marker: Marker3D in [sk.shoulder, sk.bottom_shoulder]:
		var gameplay: Vector3 = sk.upper_body.transform * marker.position
		var visible: Vector3 = spine * marker.position
		assert_lt(gameplay.distance_to(visible), 0.16,
				"the shoulder the arm is drawn from sits on the frame the hand hangs from")


func test_the_blade_stays_on_the_ice_through_the_lean() -> void:
	var c: SkaterController = _rig(20.0)
	_tick(c, Vector2(0.0, -1.0), 240)
	for _i: int in 80:
		_tick(c, Vector2(1.0, 0.0), 1)
		assert_almost_eq(c.skater.get_blade_contact_global().y, c.blade_height, 0.03,
				"the blade is on the ice under a leaned frame")


func test_a_body_check_does_not_lean_the_body() -> void:
	var c: SkaterController = _rig(20.0)
	_tick(c, Vector2(0.0, -1.0), 240)
	var before: Vector2 = c.skater.balance_tilt()
	# An impulse lands between ticks, the way the skater's collision pass applies it.
	c.skater.velocity += Vector3(6.0, 0.0, 0.0)
	_tick(c, Vector2(0.0, -1.0), 1)
	assert_lt((c.skater.balance_tilt() - before).length(), 0.02,
			"a shove is not something a body leans into")


# The balance and torso leans off the wire must place the frame where the
# shooter has it — the wire's blade is local to that frame.
func test_a_remote_rebuilds_the_blade_from_the_wire() -> void:
	var shooter: SkaterController = _rig(20.0)
	_tick(shooter, Vector2(0.0, -1.0), 240)
	_tick(shooter, Vector2(1.0, 0.0), 80)
	assert_gt(shooter.skater.balance_tilt().length(), 0.3, "leaned into the turn")
	var wire := SkaterNetworkState.new()
	shooter.fill_network_state(wire)
	var received: SkaterNetworkState = WorldStateCodec._decode_skater_quantized(
			WorldStateCodec._encode_skater_quantized(wire))
	var viewer: SkaterController = _rig(-20.0)
	viewer.apply_replay_state(received, DT)
	var a: Skater = shooter.skater
	var b: Skater = viewer.skater
	assert_gt(absf(a.upper_body.rotation.x) + absf(a.upper_body.rotation.z), 0.1,
			"the shooter's torso leans")
	assert_almost_eq(b.upper_body.rotation.x, a.upper_body.rotation.x, 0.001, "the torso pitch")
	assert_almost_eq(b.upper_body.rotation.z, a.upper_body.rotation.z, 0.001, "the torso roll")
	assert_lt(b.upper_body.position.distance_to(a.upper_body.position), 0.01,
			"the receiver's frame sits where the shooter's does")
	var expected: Vector3 = a.get_blade_contact_global() - a.global_position
	var rebuilt: Vector3 = b.get_blade_contact_global() - b.global_position
	assert_lt(rebuilt.distance_to(expected), 0.03,
			"and the blade with it (off by %.3f m)" % rebuilt.distance_to(expected))
	# Without the lean on the wire the frame would sit upright under the body.
	b.set_balance_tilt(Vector2.ZERO)
	assert_gt(b.upper_body.position.distance_to(a.upper_body.position), 0.3,
			"the lean is what carries the frame")
