extends GutTest

# The body is one chain (SkaterSpineRig): hips, then the pelvis, then the spine,
# folded before it is twisted, and twisted no further than a spine turns. Each
# property below is one the old sibling rig broke — the shorts turning with the
# shoulders instead of the legs, a forward lean tipping sideways once the
# shoulders turned toward the stick — measured on the live rig rather than on
# the composition, so a reorder of the bone writes fails here.

const _SCENE: String = "res://Scenes/Skater.tscn"
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func is_faceoff_prep() -> bool:
		return false


func _bare_skater() -> Skater:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	return skater


func _rig(skater: Skater) -> Skeleton3D:
	return skater.mesh_root.get_node("BodyRig") as Skeleton3D


func _heading(basis: Basis) -> float:
	var fwd: Vector3 = -basis.z
	return atan2(-fwd.x, -fwd.z)


# ── Structure ────────────────────────────────────────────────────────────────

func test_the_shorts_and_the_legs_hang_from_the_same_hips() -> void:
	var rig: Skeleton3D = _rig(_bare_skater())
	var hips: int = SkaterBodySkeleton.HIPS_BONE
	var waist: int = SkaterBodySkeleton.WAIST_BONE
	assert_eq(rig.get_bone_parent(SkaterMeshBuilder.UpperBone.PELVIS), waist)
	assert_eq(rig.get_bone_parent(waist), hips)
	for leg: int in [SkaterMeshBuilder.LegBone.LEG_L, SkaterMeshBuilder.LegBone.LEG_R]:
		assert_eq(rig.get_bone_parent(SkaterBodySkeleton.LEG_BONE_OFFSET + leg), hips,
				"each leg roots on the hips, so the seat cannot turn away from them")
	assert_eq(rig.get_bone_parent(SkaterBodySkeleton.SPINE_BONE), waist)
	for shell: int in [SkaterMeshBuilder.UpperBone.TORSO,
			SkaterMeshBuilder.UpperBone.SHOULDER_L, SkaterMeshBuilder.UpperBone.SHOULDER_R]:
		assert_eq(rig.get_bone_parent(shell), SkaterBodySkeleton.SPINE_BONE)
	assert_eq(rig.get_bone_parent(SkaterMeshBuilder.UpperBone.HELMET), SkaterBodySkeleton.NECK_BONE)
	assert_eq(rig.get_bone_parent(SkaterBodySkeleton.NECK_BONE), SkaterBodySkeleton.SPINE_BONE)


# ── Fold, then twist ─────────────────────────────────────────────────────────

# The skating posture bends the trunk forward over the HIPS. Applied after the
# shoulders turn toward the stick — the gameplay frame's own euler order — the
# same pitch tips the chest sideways, off the hips, by the sine of the twist.
func test_a_forward_fold_stays_forward_of_the_hips_when_the_shoulders_turn() -> void:
	var skater: Skater = _bare_skater()
	var fold: float = deg_to_rad(-20.0)
	skater.set_upper_body_rotation(deg_to_rad(45.0))
	skater.set_upper_body_lean(fold, 0.0, fold)
	skater.update_arm_mesh()
	var spine_up: Vector3 = _rig(skater).get_bone_global_pose(
			SkaterBodySkeleton.SPINE_BONE).basis.y
	assert_almost_eq(spine_up.x, 0.0, 0.001,
			"the fold must not lean the trunk across the hips")
	assert_almost_eq(spine_up.z, sin(fold), 0.001,
			"it must lean it forward over them by the whole fold")
	# The contrast that makes the assertion mean something: the gameplay frame
	# composed the old way does lean sideways here.
	assert_gt(absf(skater.upper_body.transform.basis.y.x), 0.15)


# ── Twist limit ──────────────────────────────────────────────────────────────

# The shoulders always point where gameplay put them — the arms must reach the
# hands — so a twist past the spine's range is paid by the hips coming round.
func test_past_the_spine_s_range_the_hips_come_round() -> void:
	var skater: Skater = _bare_skater()
	var trunk_yaw: float = deg_to_rad(80.0)
	skater.set_upper_body_rotation(trunk_yaw)
	skater.update_arm_mesh()
	var rig: Skeleton3D = _rig(skater)
	var hips: float = _heading(rig.get_bone_global_pose(SkaterBodySkeleton.HIPS_BONE).basis)
	var spine: float = _heading(rig.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE).basis)
	assert_almost_eq(spine, trunk_yaw, 0.001, "the shoulders keep the gameplay heading")
	assert_almost_eq(angle_difference(hips, spine), SkaterSpineRig.TWIST_LIMIT, 0.001,
			"and sit no further from the hips than the spine turns")


# ── Live: swinging the cursor while skating ──────────────────────────────────

# The symptom the chain exists to fix, measured the way it was found: skate
# forward at speed and sweep the cursor across the body. The head has to stay
# over the pelvis across the line of travel; what is left is the reach lean
# toward the hand. Measured before the chain: ±0.18 m.
func _live_controller() -> SkaterController:
	var state := StubGameState.new()
	add_child_autofree(state)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.set_process(false)
	var skater: Skater = _bare_skater()
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.set_physics_process(false)
	c.set_process(false)
	c.setup(skater, puck, state)
	c.apply_attributes(PlayerAttributes.new())
	return c


# The tick order of a live frame at 120 fps: controller, physics, render.
func _tick(c: SkaterController, input: InputState, move: Vector2, aim: Vector3) -> void:
	input.host_timestamp += DT
	input.move_vector = move
	input.mouse_world_pos = c.skater.global_position + aim
	c._process_input(input, DT)
	c.skater._physics_process(DT)
	c.skater._process(DT)


# Face up the ice and build to cruising speed.
func _skate_up_the_ice(c: SkaterController, input: InputState) -> void:
	for _i: int in 40:
		_tick(c, input, Vector2.ZERO, Vector3(3.0, 0.0, 0.0))
	for _i: int in 40:
		_tick(c, input, Vector2.ZERO, Vector3(0.0, 0.0, -3.0))
	for _i: int in 240:
		_tick(c, input, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -3.0))


func test_sweeping_the_cursor_at_speed_keeps_the_head_over_the_pelvis() -> void:
	var c: SkaterController = _live_controller()
	var skater: Skater = c.skater
	var input := InputState.new()
	input.delta = DT
	var worst: float = 0.0
	# Turn to face up the ice, build speed, then sweep the cursor side to side.
	_skate_up_the_ice(c, input)
	var segments: Array = [[40, Vector2(0.0, -1.0), Vector3(2.5, 0.0, -1.5)],
			[40, Vector2(0.0, -1.0), Vector3(-2.5, 0.0, -1.5)],
			[40, Vector2(0.0, -1.0), Vector3(2.5, 0.0, -1.5)],
			[40, Vector2(0.0, -1.0), Vector3(-2.5, 0.0, -1.5)]]
	for seg: Array in segments:
		for _i: int in int(seg[0]):
			_tick(c, input, seg[1], seg[2])
			worst = maxf(worst, absf(_head_across_travel(skater)))
	assert_gt(Vector2(skater.velocity.x, skater.velocity.z).length(), 7.0,
			"the sweep has to happen at speed to mean anything")
	assert_lt(worst, 0.08,
			"the head drifted %.2f m across the line of travel off the pelvis" % worst)


func _head_across_travel(skater: Skater) -> float:
	var rig: Skeleton3D = _rig(skater)
	var v: Vector3 = skater.global_transform.basis.inverse() * skater.velocity
	var right: Vector3 = Vector3(v.x, 0.0, v.z).normalized().cross(Vector3.UP)
	var head: Vector3 = rig.get_bone_global_pose(SkaterMeshBuilder.UpperBone.HELMET).origin
	var pelvis: Vector3 = rig.get_bone_global_pose(SkaterMeshBuilder.UpperBone.PELVIS).origin
	return (head - pelvis).dot(right)


# ── Live: the balance lean ───────────────────────────────────────────────────

# A held turn leans the body by what balances it; steering taps a quarter second
# apart do not, because the centre of mass cannot be moved over the edges that
# fast. Measured before the balance spring: the trunk swung +24° / -14° per tap.
# The first two taps are skipped: the first is a step, and a quarter second of
# hard steering genuinely does lean a skater half way.
func test_a_held_turn_leans_and_steering_taps_do_not() -> void:
	var c: SkaterController = _live_controller()
	var input := InputState.new()
	input.delta = DT
	_skate_up_the_ice(c, input)
	var tap_worst: float = 0.0
	for k: int in 8:
		var move := Vector2(0.7 if k % 2 == 0 else -0.7, -0.7)
		for _i: int in 30:
			_tick(c, input, move, Vector3(0.0, 0.0, -3.0))
			if k >= 2:
				tap_worst = maxf(tap_worst, c.skater.balance_tilt().length())
	assert_lt(rad_to_deg(tap_worst), 10.0,
			"steering taps leaned the body %.1f°" % rad_to_deg(tap_worst))

	for _i: int in 90:
		_tick(c, input, Vector2(1.0, 0.0), Vector3(2.2, 0.0, -2.2))
	assert_gt(rad_to_deg(c.skater.balance_tilt().length()), 15.0,
			"a held hard turn must lean the body into it")


# The neck takes back part of the trunk's lean, so the head reads the lean but
# the eyes stay nearer level than the shoulders. Measured as roll across the line
# of travel: the forward fold is posture, which the neck leaves alone.
func test_the_head_leans_less_than_the_trunk() -> void:
	var c: SkaterController = _live_controller()
	var input := InputState.new()
	input.delta = DT
	_skate_up_the_ice(c, input)
	for _i: int in 90:
		_tick(c, input, Vector2(1.0, 0.0), Vector3(2.2, 0.0, -2.2))
	var rig: Skeleton3D = _rig(c.skater)
	var v: Vector3 = c.skater.global_transform.basis.inverse() * c.skater.velocity
	var right: Vector3 = Vector3(v.x, 0.0, v.z).normalized().cross(Vector3.UP)
	var trunk_roll: float = _roll(rig, SkaterBodySkeleton.SPINE_BONE, right)
	var head_roll: float = _roll(rig, SkaterBodySkeleton.NECK_BONE, right)
	assert_gt(rad_to_deg(absf(trunk_roll)), 5.0,
			"the trunk must be leaning for this to mean anything")
	assert_lt(absf(head_roll), absf(trunk_roll) * 0.6,
			"the head must lean well short of the trunk")


func _roll(rig: Skeleton3D, bone: int, right: Vector3) -> float:
	var up: Vector3 = rig.get_bone_global_pose(bone).basis.y
	return atan2(up.dot(right), up.y)


# ── Live: crossovers commit to a turn ────────────────────────────────────────

# Crossovers are how a skater carries a turn, not how they correct a line:
# steering taps alternating sides cancel (the crossover is eased with its side
# as the sign), and only a turn held to one side commits. Measured before the
# locomotion states: the taps fired crossovers on alternate legs and swung the
# skates ±0.3 m.
func test_steering_taps_ride_the_edges_and_a_held_turn_crosses_over() -> void:
	var c: SkaterController = _live_controller()
	# From the far end: the skate-up and the taps cover most of the half-rink.
	c.skater.global_position.z = 25.0
	var input := InputState.new()
	input.delta = DT
	_skate_up_the_ice(c, input)
	var tap_worst: float = 0.0
	for k: int in 8:
		var move := Vector2(0.7 if k % 2 == 0 else -0.7, -0.7)
		for _i: int in 30:
			_tick(c, input, move, Vector3(0.0, 0.0, -3.0))
			if k >= 2:
				tap_worst = maxf(tap_worst, c._skating.locomotion_mix().crossover)
	assert_lt(tap_worst, 0.3, "steering taps committed %.2f to crossovers" % tap_worst)

	# A held arc: the stick kept across the travel, so the turn never completes.
	for _i: int in 120:
		var v := Vector2(c.skater.velocity.x, c.skater.velocity.z).normalized()
		var across := Vector2(-v.y, v.x)
		var look: Vector2 = (v + across).normalized() * 3.0
		_tick(c, input, across, Vector3(look.x, 0.0, look.y))
	assert_gt(c._skating.locomotion_mix().crossover, 0.6,
			"a held turn must be skated with crossovers")

