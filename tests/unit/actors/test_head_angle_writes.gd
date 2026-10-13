extends GutTest

# Skater.set_head_angle re-poses the helmet only once the angle has moved
# SkaterArmRig.HEAD_ANGLE_EPS_RAD from the last one written. The head's lerp
# toward its aim never lands exactly, and every bone write dirties the whole
# skeleton, so without the threshold an idle skater re-skinned every frame.

const HELMET: int = SkaterMeshBuilder.UpperBone.HELMET
const EPS: float = SkaterArmRig.HEAD_ANGLE_EPS_RAD


func _skater() -> Skater:
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.set_process(false)
	sk.set_physics_process(false)
	return sk


func _helmet(sk: Skater) -> Transform3D:
	return (sk.mesh_root.get_node("BodyRig") as Skeleton3D).get_bone_pose(HELMET)


func test_a_sub_threshold_move_leaves_the_helmet_alone() -> void:
	var sk: Skater = _skater()
	sk.set_head_angle(0.3)
	var posed: Transform3D = _helmet(sk)
	sk.set_head_angle(0.3 + EPS * 0.5)
	assert_eq(_helmet(sk), posed, "a sub-threshold move does not re-pose")
	sk.set_head_angle(0.3 + EPS * 2.0)
	assert_ne(_helmet(sk), posed, "a real move does")


func test_slow_drift_is_written_once_it_adds_up() -> void:
	# The threshold is measured from the last WRITE, so a turn made of many
	# sub-threshold steps still lands, and the drawn head never trails by more.
	var sk: Skater = _skater()
	sk.set_head_angle(0.0)
	var angle: float = 0.0
	var writes: int = 0
	var last: Transform3D = _helmet(sk)
	for _i: int in 100:
		angle += EPS * 0.3
		sk.set_head_angle(angle)
		if _helmet(sk) != last:
			writes += 1
			last = _helmet(sk)
	assert_between(writes, 25, 40, "~one write per threshold crossed (%d)" % writes)
	var drawn: float = last.basis.get_euler().y
	assert_lt(absf(drawn - angle), EPS + 1e-6, "the drawn head trails by under the threshold")


func test_an_easing_head_settles_into_no_writes() -> void:
	# The pose coordinator's lerp back to centre: after it has eased in, the
	# helmet stops being re-posed even though the angle never reaches zero.
	var sk: Skater = _skater()
	var angle: float = 0.5
	for _i: int in 600:
		angle = lerpf(angle, 0.0, 0.1)
		sk.set_head_angle(angle)
	assert_ne(angle, 0.0, "the lerp alone never lands")
	var settled: Transform3D = _helmet(sk)
	for _i: int in 60:
		angle = lerpf(angle, 0.0, 0.1)
		sk.set_head_angle(angle)
	assert_eq(_helmet(sk), settled, "a settled head is not re-posed")
