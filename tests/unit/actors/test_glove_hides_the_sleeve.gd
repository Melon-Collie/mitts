extends GutTest

# The sleeve stops at the glove. The forearm, the cuff and the fist are three
# meshes posed along one forearm axis, and nothing but their proportions keeps
# the sleeve inside the other two: a sleeve thicker than the fist runs out
# through its faces as stripes of jersey across the glove. This poses the live
# rig at the corners of the build range and holds every sleeve vertex the glove
# reaches over to being inside the cuff or the fist.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
# [forearm, cuff, fist] per arm.
const _ARMS: Array = [
	[UpperBone.TOP_FOREARM, UpperBone.TOP_CUFF, UpperBone.TOP_HAND],
	[UpperBone.BOTTOM_FOREARM, UpperBone.BOTTOM_CUFF, UpperBone.BOTTOM_HAND],
]


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null


func _rig(attrs: PlayerAttributes) -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_skater.apply_appearance(attrs)
	_controller.apply_attributes(attrs)
	var input := InputState.new()
	for t: int in 40:
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = _skater.global_position + Vector3(0.6, 0.0, -2.2)
		_controller._process_input(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)


# The (half width, half depth) of a swept section at `y` along its axis, or a
# negative size outside it. `stations` run (y, half_w, half_d) from +y down;
# `y_scale` turns a station's y into the mesh's.
static func _section(stations: Array[Vector3], y_scale: float, y: float) -> Vector2:
	for i: int in stations.size() - 1:
		var a: Vector3 = stations[i]
		var b: Vector3 = stations[i + 1]
		var ya: float = a.x * y_scale
		var yb: float = b.x * y_scale
		if y <= ya and y >= yb:
			var t: float = (ya - y) / (ya - yb)
			return Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))
	return Vector2(-1.0, -1.0)


static func _inside_section(p: Vector3, size: Vector2) -> bool:
	if size.x < 0.0:
		return false
	var loop: PackedVector3Array = SkaterMeshBuilder._octagon_loop(0.0, size.x, size.y,
			SkaterMeshBuilder._GLOVE_FACE_FRAC, SkaterMeshBuilder._GLOVE_SIDE_FRAC)
	var winding: float = 0.0
	for k: int in loop.size():
		var a: Vector3 = loop[k]
		var b: Vector3 = loop[(k + 1) % loop.size()]
		var side: float = (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x)
		if winding == 0.0:
			winding = signf(side)
		elif signf(side) != winding:
			return false
	return true


# Sleeve vertices up the arm as far as the cuff's open end that are in neither
# the cuff nor the fist, and how many the glove reached over.
func _bare_sleeve(arm: Array) -> Vector2i:
	var body: Skeleton3D = _skater._arms._skeleton
	# The sleeve's forearm is the one on this arm's side, skinned through its
	# bind (SkaterMeshBuilder._sleeve).
	var top_on_right: bool = _skater.shoulder.position.x > 0.0
	var marker: Marker3D = _skater.shoulder if arm[0] == UpperBone.TOP_FOREARM \
			else _skater.bottom_shoulder
	var side_i: int = 1 if marker.position.x > 0.0 else 0
	var bind: Transform3D = SkaterMeshBuilder.shared_upper_skin(top_on_right).get_bind_pose(
			SkaterMeshBuilder.sleeve_bind(side_i, SkaterMeshBuilder.SleevePart.FOREARM))
	var forearm: Transform3D = body.get_bone_pose(arm[0]) * bind
	var to_cuff: Transform3D = body.get_bone_pose(arm[1]).affine_inverse()
	var to_fist: Transform3D = body.get_bone_pose(arm[2]).affine_inverse()
	var verts: PackedVector3Array = SkaterMeshBuilder.shared_upper_skin_mesh() \
			.surface_get_arrays(SkaterMeshBuilder.UpperSurface.TOP_FOREARM if side_i == 0
			else SkaterMeshBuilder.UpperSurface.BOTTOM_FOREARM)[Mesh.ARRAY_VERTEX]
	var cuff_top: float = SkaterMeshBuilder.CUFF_HEIGHT_M * 0.5
	var covered: int = 0
	var bare: int = 0
	for v: Vector3 in verts:
		var p: Vector3 = forearm * v
		var in_cuff: Vector3 = to_cuff * p
		if in_cuff.y > cuff_top:
			continue
		covered += 1
		var in_fist: Vector3 = to_fist * p
		if _inside_section(in_cuff, _section(SkaterMeshBuilder._CUFF_STATIONS,
				SkaterMeshBuilder.CUFF_HEIGHT_M, in_cuff.y)):
			continue
		if _inside_section(in_fist, _section(SkaterMeshBuilder._GLOVE_FIST_STATIONS,
				1.0, in_fist.y)):
			continue
		bare += 1
	return Vector2i(bare, covered)


func test_no_sleeve_shows_through_the_glove() -> void:
	for height: int in [PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX]:
		for weight: int in [PlayerAttributes.weight_min(height),
				PlayerAttributes.weight_max(height)]:
			_rig(PlayerAttributes.new(height, weight))
			for i: int in _ARMS.size():
				var count: Vector2i = _bare_sleeve(_ARMS[i])
				var label: String = "%d in, %d lb, %s arm" % [height, weight,
						"top" if i == 0 else "bottom"]
				assert_gt(count.y, 0, "%s: the glove reaches over some of the sleeve" % label)
				assert_eq(count.x, 0, "%s: %d of the %d sleeve vertices under the glove show through it"
						% [label, count.x, count.y])
