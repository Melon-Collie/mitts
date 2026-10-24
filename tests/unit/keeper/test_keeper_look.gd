extends GutTest

# His eyes on the puck (KeeperLook): in any stance his face comes round to it
# wherever the neck lets it, no faster than a head turns, held at the neck's
# limit past it, and back where the stance holds it when the puck is there.

const DT: float = 1.0 / 120.0

var _skel := KeeperSkeleton.new()


# His face as the skeleton solves it from `p`, and where his eyes are.
func _face(p: KeeperPose) -> Vector3:
	_skel.pose(p)
	return (_skel.xf[KeeperSkeleton.Bone.HEAD].basis * Vector3.FORWARD).normalized()


func _eyes(p: KeeperPose) -> Vector3:
	_skel.pose(p)
	return _skel.xf[KeeperSkeleton.Bone.HEAD].origin


# `stance` with the look stepped `seconds` toward `at`.
func _looked(stance: Callable, at: Vector3, seconds: float, look: KeeperLook) -> KeeperPose:
	var p := KeeperPose.new()
	for i: int in int(seconds / DT):
		stance.call(p)
		look.step(DT, p, at)
	return p


func test_in_any_stance_his_face_comes_round_to_the_puck() -> void:
	var stances: Array[Callable] = [KeeperPoses.ready, KeeperPoses.butterfly, KeeperPoses.low_ready]
	var spots: Array[Vector3] = [Vector3(0.0, 0.05, -6.0), Vector3(1.5, 0.05, -4.0), Vector3(-1.0, 1.2, -3.0),
			Vector3(0.6, 0.05, -1.0)]
	for s: int in stances.size():
		for at: Vector3 in spots:
			var look := KeeperLook.new()
			var p: KeeperPose = _looked(stances[s], at, 0.6, look)
			var off: float = rad_to_deg(_face(p).angle_to(at - _eyes(p)))
			assert_lt(off, 4.0, "stance %d, %s: his face on it (%.1f° off)" % [s, at, off])


func test_no_faster_than_a_head_turns_and_no_further_than_a_neck() -> void:
	var look := KeeperLook.new()
	var p := KeeperPose.new()
	var was := Vector2.ZERO
	for i: int in 60:
		KeeperPoses.ready(p)
		look.step(DT, p, Vector3(-4.0, 1.0, 0.5))
		var now := Vector2(look.yaw, look.pitch)
		assert_lte(now.distance_to(was), KeeperLook.TURN_RAD_S * DT + 1e-5, "tick %d" % i)
		was = now
	# Behind him to his glove side: turned off his chest as far as his neck turns.
	KeeperPoses.ready(p)
	look.step(DT, p, Vector3(-4.0, 1.0, 0.5))
	var face: Vector3 = _face(p)
	var on_chest: Vector3 = _skel.xf[KeeperSkeleton.Bone.CHEST].basis.inverse() * face
	assert_almost_eq(absf(atan2(-on_chest.x, -on_chest.z)), KeeperLook.YAW_MAX_RAD, deg_to_rad(2.0),
			"as far as his neck turns")


func test_a_puck_straight_ahead_leaves_the_stance_as_it_is() -> void:
	var look := KeeperLook.new()
	var p := KeeperPose.new()
	KeeperPoses.ready(p)
	var eyes: Vector3 = _eyes(p)
	var ahead: Vector3 = eyes + _face(p) * 6.0
	p = _looked(KeeperPoses.ready, ahead, 0.3, look)
	# To within his eyes' place, which the look takes off his trunk.
	assert_almost_eq(look.yaw, 0.0, 0.01)
	assert_almost_eq(look.pitch, 0.0, 0.01)


# A puck behind him he looks back at over his shoulder: the neck as far as it
# turns and the trunk the rest, his face on it; dead behind, he keeps to the
# shoulder he turned over rather than snapping to the other.
func test_behind_him_he_looks_back_over_his_shoulder() -> void:
	var look := KeeperLook.new()
	var p: KeeperPose = _looked(KeeperPoses.ready, Vector3(-1.5, 0.05, 1.2), 0.8, look)
	var off: float = rad_to_deg(_face(p).angle_to(Vector3(-1.5, 0.05, 1.2) - _eyes(p)))
	assert_lt(off, 6.0, "his face on it behind him (%.1f° off)" % off)
	assert_gt(absf(look.trunk), 0.1, "his trunk turned into the look")
	assert_lte(absf(look.trunk), KeeperLook.TRUNK_MAX_RAD + 1e-5, "no further than a trunk turns")
	var side: float = signf(look.yaw + look.trunk)
	var flips: int = 0
	var behind := Vector3(0.0, 0.05, 3.0)
	for i: int in 60:
		var q := KeeperPose.new()
		KeeperPoses.ready(q)
		behind.x = 0.05 * sin(float(i))
		look.step(DT, q, behind)
		if signf(look.yaw + look.trunk) != side:
			flips += 1
	assert_eq(flips, 0, "dead behind: over the same shoulder")
