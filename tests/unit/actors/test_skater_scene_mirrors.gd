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


# The one mirror where a silent drift changes GAMEPLAY rather than the picture.
# shoulder_offset / shoulder_height feed SkaterController.apply_attributes'
# backhand reach solve (reach = sqrt(arm_eff² − drop²)), so a shoulder moved in
# the editor moves how far a skater can actually reach across their body.
func test_shoulder_anchors_mirror_the_scene() -> void:
	var left: Vector3 = _origin("./MeshRoot/UpperBody/ShoulderL")
	var right: Vector3 = _origin("./MeshRoot/UpperBody/ShoulderR")
	var skater: Skater = Skater.new()
	assert_almost_eq(skater.shoulder_offset, absf(left.x), 1e-6,
			"shoulder_offset must equal ShoulderL's lateral offset")
	assert_almost_eq(skater.shoulder_offset, absf(right.x), 1e-6,
			"and ShoulderR's — the rig assumes the pair is symmetric")
	assert_almost_eq(skater.shoulder_height, left.y, 1e-6,
			"shoulder_height must equal the shoulder ball's height, which is the " +
			"top of the backhand reach triangle")
	assert_almost_eq(left.y, right.y, 1e-6, "both shoulders sit at one height")
	skater.free()


func test_helmet_and_torso_stations_mirror_the_scene() -> void:
	assert_almost_eq(_origin("./MeshRoot/UpperBody/Helmet").y, 0.65, 1e-6,
			"the neck profile is built in helmet-local space from this origin — move " +
			"the helmet and the neck stops sinking into the traps")
	var torso_origin: float = _origin("./MeshRoot/UpperBody/UpperBodyMesh").y
	assert_almost_eq(torso_origin, 0.195, 1e-6,
			"the torso lathe is built around this origin")
	assert_almost_eq(torso_origin + 0.275, 0.47, 1e-6,
			"torso origin plus the trap-line station (_TORSO_PROFILE[0].x) is the " +
			"shoulder shelf the neck profile is sized against")


# The thigh's upper stations are the hip joint: a dome that seals it only while
# it is centred ON the pivot the leg turns about, because a sphere about the
# axis of rotation is the one surface that does not move when the leg does. That
# pivot is the LegL node, and the thigh mesh hangs its own origin below it — so
# the dome's centre, in the thigh part's frame, IS that offset. Author it a
# centimetre out and the hip opens as the leg swings, which shows up only at the
# extremes: the block's abducted leg, the faceoff splay.
func test_the_thigh_dome_is_centred_on_the_hip_pivot() -> void:
	var thigh_drop: float = -_origin("./MeshRoot/LowerBody/LegL/ThighL").y
	assert_almost_eq(SkaterMeshBuilder._HIP_PIVOT_IN_THIGH, thigh_drop, 1e-6,
			"the dome's centre in thigh-local Y is the pivot the scene authors")
	var radius: float = SkaterMeshBuilder._THIGH_DOME_RADIUS
	var stations: int = 0
	for station: Vector2 in SkaterMeshBuilder._THIGH_PROFILE:
		var dy: float = station.x - SkaterMeshBuilder._HIP_PIVOT_IN_THIGH
		if dy < 0.0:
			continue  # below the equator the thigh's own taper takes over
		assert_almost_eq(station.y, sqrt(maxf(radius * radius - dy * dy, 0.0)), 0.002,
				"station y %.3f must lie on the dome" % station.x)
		stations += 1
	assert_gt(stations, 2, "the dome must be more than an equator and a pole")


# The knee is one lathe whose lower rings are skinned to the sock and whose top
# ring to the knee bone, both authored in the knee's frame. They meet only while
# the knee bone sits on the shin's pivot and the sock hangs _KNEE_ABOVE_SOCK
# below it; a drift tears the leg open at the joint before it bends at all.
func test_the_knee_stitch_sits_on_the_scene_pivot() -> void:
	var knee: Vector3 = _origin("./MeshRoot/LowerBody/LegL/KneeL")
	var shin: Vector3 = _origin("./MeshRoot/LowerBody/LegL/ShinL")
	var sock: Vector3 = _origin("./MeshRoot/LowerBody/LegL/ShinL/SockL")
	assert_almost_eq(knee, shin, Vector3.ONE * 1e-6, "the knee bone is on the knee pivot")
	assert_almost_eq(sock, Vector3(0.0, -SkaterMeshBuilder._KNEE_ABOVE_SOCK, 0.0),
			Vector3.ONE * 1e-6, "the sock hangs _KNEE_ABOVE_SOCK straight below it")
	var bottom: Vector3 = SkaterMeshBuilder._KNEE_PROFILE[-1]
	var sock_top: Vector2 = SkaterMeshBuilder._SOCK_PROFILE[0]
	assert_almost_eq(bottom.x + SkaterMeshBuilder._KNEE_ABOVE_SOCK, sock_top.x, 1e-6,
			"the knee's bottom ring is the sock's top ring")
	assert_almost_eq(bottom.y, sock_top.y, 1e-6, "at the sock's radius")
	assert_eq(bottom.z, 0.0, "with no kneecap on it")
	# The top ring rides the thigh and must stay inside the pants' hem.
	var top: Vector3 = SkaterMeshBuilder._KNEE_PROFILE[0]
	var hem_y: float = _origin("./MeshRoot/LowerBody/LegL/ThighL").y \
			+ SkaterMeshBuilder._THIGH_PROFILE[-1].x - knee.y
	assert_gt(top.x, hem_y, "the thigh's ring is above the pants' hem")
	assert_lt(top.y, SkaterMeshBuilder._THIGH_PROFILE[-1].y, "and inside it")
	assert_gt(top.x, SkaterMeshBuilder._KNEE_STITCH_Y, "the top ring is the thigh's")
	assert_lt(SkaterMeshBuilder._KNEE_PROFILE[1].x, SkaterMeshBuilder._KNEE_STITCH_Y,
			"and only the top ring")


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
# slack — it dropped by two when the hip balls were folded into the thighs, and
# it should drop again the next time the scene loses a part.
func test_the_scene_scan_actually_saw_the_rig() -> void:
	assert_gt(_origins.size(), 18, "expected the whole rig — the parser may have broken")
	assert_true(_origins.has("./MeshRoot/UpperBody/ShoulderL"), "sanity: ShoulderL found")
