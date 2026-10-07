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
	for shell: int in [SkaterMeshBuilder.UpperBone.TORSO, SkaterMeshBuilder.UpperBone.HELMET,
			SkaterMeshBuilder.UpperBone.SHOULDER_L, SkaterMeshBuilder.UpperBone.SHOULDER_R]:
		assert_eq(rig.get_bone_parent(shell), SkaterBodySkeleton.SPINE_BONE)


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
func test_sweeping_the_cursor_at_speed_keeps_the_head_over_the_pelvis() -> void:
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

	var input := InputState.new()
	input.delta = DT
	var worst: float = 0.0
	# Turn to face up the ice, build speed, then sweep the cursor side to side.
	var segments: Array = [[40, Vector2.ZERO, Vector3(3.0, 0.0, 0.0)],
			[40, Vector2.ZERO, Vector3(0.0, 0.0, -3.0)],
			[240, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -3.0)],
			[40, Vector2(0.0, -1.0), Vector3(2.5, 0.0, -1.5)],
			[40, Vector2(0.0, -1.0), Vector3(-2.5, 0.0, -1.5)],
			[40, Vector2(0.0, -1.0), Vector3(2.5, 0.0, -1.5)],
			[40, Vector2(0.0, -1.0), Vector3(-2.5, 0.0, -1.5)]]
	for k: int in segments.size():
		var seg: Array = segments[k]
		for _i: int in int(seg[0]):
			input.host_timestamp += DT
			input.move_vector = seg[1]
			input.mouse_world_pos = skater.global_position + (seg[2] as Vector3)
			c._process_input(input, DT)
			skater._physics_process(DT)
			skater._process(DT)
			if k >= 3:
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
