extends GutTest

# The seat: three agreements between parts, none of them visible in the file
# that would break one.
#
# The trunk texture rotates the torso bone about the fold pivot at the hips, so
# at the faceoff centre's fold the jersey hem swings up and away and leaves the
# body open from behind — a flat bottom cap tipped into view over the V-notch
# between two hip balls. A real pelvis does not fold with the spine, so the
# rig's does not fold with the torso: it is a part of the UPPER mesh that the
# trunk texture is not applied to. That only works while it stays hidden under
# the jersey at rest, meets the hips it sits between, and keeps its hands off
# the fold.

const _SCENE: String = "res://Scenes/Skater.tscn"

# The hip pivots, from Scenes/Skater.tscn — where the thigh domes are centred.
var _hip_centre_y: float = 0.0
var _hip_centre_x: float = 0.0
var _torso_origin_y: float = 0.0


func before_all() -> void:
	var st: SceneState = (load(_SCENE) as PackedScene).get_state()
	var origins: Dictionary = {}
	for i: int in st.get_node_count():
		var path: String = "%s/%s" % [st.get_node_path(i, true), st.get_node_name(i)]
		for p: int in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == "transform":
				origins[path] = (st.get_node_property_value(i, p) as Transform3D).origin
	var leg: Vector3 = origins["./MeshRoot/LowerBody/LegL"]
	_hip_centre_y = leg.y
	_hip_centre_x = absf(leg.x)
	_torso_origin_y = origins["./MeshRoot/UpperBody/UpperBodyMesh"].y


# Radius of a lathe profile at height `y`, linearly between its stations, plus
# that station's rear sway — the profile's own back edge. Outside the profile's
# span it has no material, which the callers handle.
func _profile_back(profile: Array[Vector2], sway: Array[float], y: float) -> float:
	for i: int in profile.size() - 1:
		var hi: Vector2 = profile[i]
		var lo: Vector2 = profile[i + 1]
		if y <= hi.x and y >= lo.x:
			var t: float = (hi.x - y) / maxf(hi.x - lo.x, 1e-6)
			return lerpf(hi.y, lo.y, t) + lerpf(sway[i], sway[i + 1], t)
	return -1.0


# ── It must not show, at rest or twisted ─────────────────────────────────────

# The pelvis exists to be seen only where there was nothing. Anywhere the torso
# still has material — every height the two share — it has to sit inside the
# torso's own rings, or it reads as a bulge through the jersey in every pose in
# the game rather than as the seat under one.
#
# Not just square-on: the trunk twists on the pelvis by whatever share of the
# spine's range the waist does not take (SkaterSpineRig), and both lathes are
# wider than they are deep, so the check walks each pelvis ring's corners
# through that yaw and asks the torso's ELLIPSE, sway included, whether they are
# inside.
func test_the_pelvis_hides_under_the_jersey_at_any_twist() -> void:
	var max_twist: float = SkaterSpineRig.TWIST_LIMIT * (1.0 - SkaterSpineRig.WAIST_TWIST_SHARE)
	var xs: float = SkaterMeshBuilder._TORSO_X_SCALE
	var zs: float = SkaterMeshBuilder._TORSO_Z_SCALE
	var sides: int = SkaterMeshBuilder._TORSO_SIDES
	var checked: int = 0
	for i: int in SkaterMeshBuilder._PELVIS_PROFILE.size():
		var station: Vector2 = SkaterMeshBuilder._PELVIS_PROFILE[i]
		var torso: Vector2 = _profile_ring(SkaterMeshBuilder._TORSO_PROFILE,
				SkaterMeshBuilder._TORSO_REAR_SWAY, station.x - _torso_origin_y)
		if torso.x < 0.0:
			continue  # below the hem — the pelvis is on its own down there
		var sway: float = SkaterMeshBuilder._PELVIS_REAR_SWAY[i]
		for twist: float in [0.0, max_twist * 0.5, max_twist, -max_twist * 0.5, -max_twist]:
			for k: int in sides:
				var a: float = TAU * float(k) / float(sides)
				var corner := Vector2(station.y * xs * cos(a), station.y * zs * sin(a) + sway)
				var turned: Vector2 = corner.rotated(twist)
				var reach: float = pow(turned.x / (torso.x * xs), 2.0) \
						+ pow((turned.y - torso.y) / (torso.x * zs), 2.0)
				assert_lt(reach, 1.0,
						"at y %.3f, twisted %.0f°, a pelvis corner pokes through the jersey"
						% [station.x, rad_to_deg(twist)])
		checked += 1
	assert_gt(checked, 1, "the two parts must overlap in height at all")


# A lathe profile's (radius, rear sway) at height `y`, linearly between its
# stations; x < 0 outside its span.
func _profile_ring(profile: Array[Vector2], sway: Array[float], y: float) -> Vector2:
	for i: int in profile.size() - 1:
		var hi: Vector2 = profile[i]
		var lo: Vector2 = profile[i + 1]
		if y <= hi.x and y >= lo.x:
			var t: float = (hi.x - y) / maxf(hi.x - lo.x, 1e-6)
			return Vector2(lerpf(hi.y, lo.y, t), lerpf(sway[i], sway[i + 1], t))
	return Vector2(-1.0, 0.0)


# ── It must meet what it sits between ────────────────────────────────────────

# The seat and the two legs are separate solids that have to read as one body.
# Each thigh caps off in a dome centred on its hip pivot, and the pelvis has to
# reach it at every height that dome spans — otherwise the body gains a seam of
# daylight at the hip, which is what the old hip balls were covering up.
# Measured on the dome's own radius, before the thigh lathe's x scale widens it:
# the stricter of the two numbers.
func test_the_pelvis_meets_both_thigh_domes() -> void:
	var dome_r: float = SkaterMeshBuilder._THIGH_DOME_RADIUS
	var y: float = _hip_centre_y + dome_r
	var checked: int = 0
	while y > _hip_centre_y - dome_r:
		var dy: float = y - _hip_centre_y
		var dome: float = sqrt(maxf(dome_r * dome_r - dy * dy, 0.0))
		var pelvis: float = _profile_back(
				SkaterMeshBuilder._PELVIS_PROFILE, SkaterMeshBuilder._PELVIS_REAR_SWAY, y)
		if pelvis < 0.0:
			y -= 0.02
			continue  # past the seat's own bottom — down here the leg is the body
		assert_gt(pelvis * SkaterMeshBuilder._TORSO_X_SCALE + dome, _hip_centre_x,
				"at y %.3f the seat (%.3f) and the thigh dome (%.3f) must still overlap"
				% [y, pelvis, dome])
		checked += 1
		y -= 0.02
	assert_gt(checked, 4, "the seat and the dome must share a real span of height")


# ── It must not fold ─────────────────────────────────────────────────────────

# The whole point, and a one-line mistake to undo: adding PELVIS to the list of
# bones SkaterArmRig.repose_bone rotates by the trunk texture would give the
# body a second hem that swings away with the first.
func test_the_pelvis_does_not_fold_with_the_chest() -> void:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var rig: Skeleton3D = skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var pelvis_rest: Transform3D = rig.get_bone_pose(SkaterMeshBuilder.UpperBone.PELVIS)

	skater.set_trunk_texture(-deg_to_rad(48.0), 0.0)

	assert_gt(rig.get_bone_pose(SkaterMeshBuilder.UpperBone.TORSO).basis.get_euler().x, -1.0,
			"the torso must take the fold")
	assert_lt(rig.get_bone_pose(SkaterMeshBuilder.UpperBone.TORSO).basis.get_euler().x, -0.5,
			"the torso must take the whole fold")
	assert_eq(rig.get_bone_pose(SkaterMeshBuilder.UpperBone.PELVIS), pelvis_rest,
			"and the pelvis must not move at all")

	# The other half, and the one a written-once guard misses: the fold is applied
	# in repose_bone, which every OTHER writer goes through too. The sizing seam
	# reposes this bone on each appearance apply, so a pelvis that is merely
	# absent from set_trunk_texture's call list still folds the moment a build's
	# scale lands on it while a fold is live.
	skater.set_upper_bone_scale(SkaterMeshBuilder.UpperBone.PELVIS, Vector3.ONE * 1.1)
	var reposed: Basis = rig.get_bone_pose(SkaterMeshBuilder.UpperBone.PELVIS).basis
	assert_almost_eq(reposed.get_euler().x, 0.0, 0.001,
			"and it must still be unrotated after anything else reposes it")
