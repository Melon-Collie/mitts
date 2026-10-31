extends GutTest

# Scenes/Skater.tscn is hand-edited in the Godot editor; the constants that
# restate it live in text files edited separately. Nothing reads both, so a
# proportion moved in the editor and a constant left behind cannot disagree
# loudly — they disagree in the render, or worse, in the reach math.
#
# The sibling of test_goalie_scene_mirrors.gd, and the same argument: the scene
# is the authored truth for where a shoulder or a knee sits, and the code around
# it is a copy that has to keep up.
#
# The rig is doubly scene-coupled: SkaterArmRig.build / SkaterLegRig.build read
# each node's authored transform out of the scene and then FREE the subtree, so
# a renamed or reparented node is not a missing-node error at runtime — it is a
# bone that silently keeps its identity transform.

const _SCENE: String = "res://Scenes/Skater.tscn"

var _origins: Dictionary = {}


func before_all() -> void:
	var st: SceneState = (load(_SCENE) as PackedScene).get_state()
	for i: int in st.get_node_count():
		var path: String = "%s/%s" % [st.get_node_path(i, true), st.get_node_name(i)]
		for p: int in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == "transform":
				_origins[path] = (st.get_node_property_value(i, p) as Transform3D).origin


func _origin(path: String) -> Vector3:
	assert_true(_origins.has(path), "no node at `%s` in %s" % [path, _SCENE])
	return _origins.get(path, Vector3.ZERO)


# shoulder_offset / shoulder_height feed SkaterController.apply_attributes'
# backhand reach solve (reach = sqrt(arm_eff² − drop²)) and root the drawn
# arm; the skin's sleeve is bound with its arm rooted there, and the display
# figures root theirs there too. A shoulder moved in one and not the others
# grows the sleeve from somewhere the arm is not.
func test_the_skin_and_the_figures_root_the_arm_at_the_shoulder_anchor() -> void:
	var skater: Skater = Skater.new()
	var anchor := Vector3(skater.shoulder_offset, skater.shoulder_height, 0.0)
	assert_almost_eq(SkaterConnectedMesh._BIND_SHOULDER, anchor, Vector3.ONE * 1e-6,
			"the skin's bind shoulder")
	assert_almost_eq(Vector3(LockerMannequin._SHOULDER_X, LockerMannequin._SHOULDER_Y, 0.0),
			anchor, Vector3.ONE * 1e-6, "the figures' shoulder")
	skater.free()


# The display figures hold the stick as a skater at his defaults does.
func test_the_figures_grip_the_stick_as_the_skater_does() -> void:
	var skater: Skater = Skater.new()
	assert_eq(LockerMannequin._GRIP_ANGLE_DEG[0], skater.top_grip_angle_deg, "top hand")
	assert_eq(LockerMannequin._GRIP_ANGLE_DEG[1], skater.bottom_grip_angle_deg, "bottom hand")
	assert_eq(LockerMannequin._WRIST_ULNAR_MAX_DEG, skater.wrist_ulnar_max_deg, "ulnar")
	assert_eq(LockerMannequin._WRIST_RADIAL_MAX_DEG, skater.wrist_radial_max_deg, "radial")
	assert_eq(LockerMannequin._WRIST_FLEX_MAX_DEG, skater.wrist_flex_max_deg, "flexion")
	assert_eq(LockerMannequin._FOREARM_TWIST_MAX_DEG, skater.forearm_twist_max_deg, "twist")
	skater.free()


func test_helmet_and_torso_stations_mirror_the_scene() -> void:
	assert_almost_eq(_origin("./MeshRoot/UpperBody/Helmet").y, 0.65, 1e-6,
			"the neck profile is built in helmet-local space from this origin — move " +
			"the helmet and the neck stops sinking into the traps")
	var torso_origin: float = _origin("./MeshRoot/UpperBody/UpperBodyMesh").y
	assert_almost_eq(torso_origin, 0.195, 1e-6,
			"the torso's stations are built around this origin")
	assert_almost_eq(torso_origin + 0.275, 0.47, 1e-6,
			"torso origin plus the trap-line station (_TORSO_PROFILE[0].x) is the " +
			"shoulder shelf the neck profile is sized against")


# The body's skin is bound where the scene authors the parts it rides, so a
# part moved in the editor and not in SkaterConnectedMesh skins the body off
# its bones: the pants' seat off the hips, the knee's bend off the knee.
func test_the_skin_is_bound_where_the_scene_puts_the_legs() -> void:
	var leg: Vector3 = _origin("./MeshRoot/LowerBody/LegL")
	assert_almost_eq(SkaterConnectedMesh.hip(-1.0), leg, Vector3.ONE * 1e-6, "the hip pivot")
	assert_almost_eq(SkaterConnectedMesh._TORSO_Y_M,
			_origin("./MeshRoot/UpperBody/UpperBodyMesh").y, 1e-6, "the torso")
	assert_almost_eq(SkaterConnectedMesh._THIGH_DROP_M,
			-_origin("./MeshRoot/LowerBody/LegL/ThighL").y, 1e-6, "the thigh")
	assert_almost_eq(SkaterConnectedMesh._KNEE_DROP_M,
			-_origin("./MeshRoot/LowerBody/LegL/ShinL").y, 1e-6, "the knee")
	assert_almost_eq(SkaterConnectedMesh._SOCK_DROP_M,
			-_origin("./MeshRoot/LowerBody/LegL/ShinL/SockL").y, 1e-6, "the sock")


# The display figures lay their body out in the scene's own numbers
# (LockerMannequin, MeshRoot-local), the leg chain relative to its LEG pivot.
func test_the_figures_rest_where_the_scene_puts_the_parts() -> void:
	var leg: Vector3 = _origin("./MeshRoot/LowerBody/LegL")
	var shin: float = _origin("./MeshRoot/LowerBody/LegL/ShinL").y
	assert_almost_eq(Vector2(-LockerMannequin._LEG_X, LockerMannequin._LEG_Y),
			Vector2(leg.x, leg.y), Vector2.ONE * 1e-6, "the hip pivot")
	assert_almost_eq(LockerMannequin._TORSO_Y,
			_origin("./MeshRoot/UpperBody/UpperBodyMesh").y, 1e-6, "the torso")
	assert_almost_eq(LockerMannequin._HELMET_Y, _origin("./MeshRoot/UpperBody/Helmet").y,
			1e-6, "the helmet")
	assert_almost_eq(LockerMannequin._THIGH_DY,
			_origin("./MeshRoot/LowerBody/LegL/ThighL").y, 1e-6, "the thigh")
	assert_almost_eq(LockerMannequin._KNEE_DY, shin, 1e-6, "the knee")
	assert_almost_eq(LockerMannequin._SOCK_DY,
			shin + _origin("./MeshRoot/LowerBody/LegL/ShinL/SockL").y, 1e-5, "the sock")
	assert_almost_eq(LockerMannequin._COLLAR_DY,
			shin + _origin("./MeshRoot/LowerBody/LegL/ShinL/SkateL").y, 1e-5, "the collar")
	var foot: Vector3 = _origin("./MeshRoot/LowerBody/LegL/ShinL/FootL")
	assert_almost_eq(Vector2(LockerMannequin._BOOT_DY, LockerMannequin._BOOT_DZ),
			Vector2(shin + foot.y, foot.z), Vector2.ONE * 1e-5, "the boot")


# The skate collar perches ON the boot with an overlap seal rather than dropping
# past the heel — which only holds while the scene seats SkateL at the heel-top
# line. The profile ends 1 cm below its own origin to make the seal.
func test_the_skate_collar_seats_at_the_boot_heel_line() -> void:
	assert_almost_eq(_origin("./MeshRoot/LowerBody/LegL/ShinL/SkateL").y, -0.41, 1e-5,
			"SkateL's origin is the heel-top line the collar profile is authored against")


# Every bone the rig reads out of the scene. These are the paths
# SkaterLegRig.build / SkaterArmRig.build resolve before freeing the subtree —
# a rename in the editor leaves the bone at identity, which is a silent
# mispose rather than an error.
func test_every_authored_bone_node_still_exists() -> void:
	for path: String in SkaterMeshBuilder.LEG_BONE_NODE:
		assert_true(_origins.has("./MeshRoot/LowerBody/%s" % path),
				"LEG_BONE_NODE names `%s`, which is not in %s — the bone would " % [path, _SCENE] +
				"silently keep its identity transform")
	for path: String in SkaterMeshBuilder.UPPER_BONE_NODE:
		if path.is_empty():
			continue  # the arm parts are placed by IK, not authored in the scene
		assert_true(_origins.has("./MeshRoot/UpperBody/%s" % path),
				"UPPER_BONE_NODE names `%s`, which is not in %s" % [path, _SCENE])


# Every assertion above reads _origins, so an empty or half-built scan would
# pass them all vacuously. The floor is the rig's own node count less a little
# slack.
func test_the_scene_scan_actually_saw_the_rig() -> void:
	assert_gt(_origins.size(), 16, "expected the whole rig — the parser may have broken")
	assert_true(_origins.has("./MeshRoot/UpperBody/Helmet"), "sanity: Helmet found")
