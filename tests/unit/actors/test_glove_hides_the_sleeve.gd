extends GutTest

# The sleeve stops at the glove. The sleeve (the body's skin,
# SkaterConnectedMesh), the cuff and the fist are posed along one forearm, and
# nothing but their proportions keeps the sleeve inside the other two: a sleeve
# thicker than the fist runs out through its faces as stripes of jersey across
# the glove. This poses the live rig at the corners of the build range, skins
# the sleeves as drawn, and holds every sleeve vertex the glove reaches over to
# being inside the cuff or the fist.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
# [upper arm, cuff, fist] per arm.
const _ARMS: Array = [
	[UpperBone.TOP_UPPER_ARM, UpperBone.TOP_CUFF, UpperBone.TOP_HAND],
	[UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_CUFF, UpperBone.BOTTOM_HAND],
]


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


# Cuff radii off the forearm past which a sleeve vertex is beside the glove,
# not under it: the sleeve is narrower than the cuff.
const _BESIDE_CUFF: float = 2.0

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


# The sleeve on the arm whose upper arm is `upper`, skinned as drawn, skeleton
# space.
func _skinned_sleeve(body: Skeleton3D, upper: int) -> PackedVector3Array:
	var shoulder: Vector3 = body.get_bone_pose(upper) * Vector3(0.0, 0.0, 0.5)
	var zone: int = SkaterConnectedMesh.zone(SkaterConnectedMesh.sleeve_surface(
			signf(shoulder.x)))
	var skin: Skin = SkaterConnectedMesh.shared_skin()
	var xforms: Array[Transform3D] = []
	for i: int in skin.get_bind_count():
		xforms.append(body.get_bone_global_pose(skin.get_bind_bone(i)) * skin.get_bind_pose(i))
	var arrays: Array = SkaterConnectedMesh.shared_mesh(_skater.gear_style.jersey_tuck) \
			.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var out := PackedVector3Array()
	for v: int in verts.size():
		if roundi(zones[v].x) != zone:
			continue
		var p := Vector3.ZERO
		for k: int in 4:
			if weights[v * 4 + k] > 0.0:
				p += (xforms[bones[v * 4 + k]] * verts[v]) * weights[v * 4 + k]
		out.append(p)
	return out


# Sleeve vertices up the arm as far as the cuff's open end that are in neither
# the cuff nor the fist, and how many the glove reached over.
func _bare_sleeve(arm: Array) -> Vector2i:
	var body: Skeleton3D = _skater._arms._skeleton
	var to_cuff: Transform3D = body.get_bone_pose(arm[1]).affine_inverse()
	var to_fist: Transform3D = body.get_bone_pose(arm[2]).affine_inverse()
	var cuff_top: float = SkaterMeshBuilder.CUFF_HEIGHT_M * 0.5
	var covered: int = 0
	var bare: int = 0
	for p: Vector3 in _skinned_sleeve(body, arm[0]):
		var in_cuff: Vector3 = to_cuff * p
		# Past the cuff's open end, or off beside the forearm altogether: a
		# folded arm's upper sleeve lies level with the cuff, well out of it.
		if in_cuff.y > cuff_top or Vector2(in_cuff.x, in_cuff.z).length() > _BESIDE_CUFF:
			continue
		covered += 1
		var in_fist: Vector3 = to_fist * p
		if _inside_section(in_cuff, _section(SkaterMeshBuilder._CUFF_STATIONS,
				SkaterMeshBuilder.CUFF_HEIGHT_M, in_cuff.y)):
			continue
		if _inside_hand(in_fist):
			continue
		bare += 1
	return Vector2i(bare, covered)


# Whether `p` (the glove's frame) is inside the glove's hand, either hand's: the
# left glove is the right one mirrored in Z, so its sections sit at −z.
static func _inside_hand(p: Vector3) -> bool:
	var stations: Array[Vector4] = SkaterMeshBuilder._GLOVE_HAND_STATIONS
	for i: int in stations.size() - 1:
		var a: Vector4 = stations[i]
		var b: Vector4 = stations[i + 1]
		if p.y <= a.x and p.y >= b.x:
			var t: float = (a.x - p.y) / (a.x - b.x)
			var size := Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))
			var centre: float = lerpf(a.w, b.w, t)
			return _inside_section(Vector3(p.x, 0.0, p.z - centre), size) \
					or _inside_section(Vector3(p.x, 0.0, p.z + centre), size)
	return false


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
