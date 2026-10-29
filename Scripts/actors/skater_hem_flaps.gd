class_name SkaterHemFlaps
extends HemFlaps

# The skater's jersey tail below the belt as flaps (HemFlaps), one per torso
# facet column: each segment a root bone (SkaterBodySkeleton.column_bone) that
# its column's vertices ride rigidly (SkaterJerseyHem.append_torso).
#
# A column hangs from its point on the belt ring, which is where the torso
# surface's own weights put it — carried by the chest and the hips in the share
# the azimuth and the tuck give it — so the jersey is one surface across the
# belt. It drapes over the thighs and the pants (SkaterHemColliders), driven by
# gravity less the skater's acceleration, read off his balance lean.
#
# The rest drape is the lathe's own rings, tucked as the skater's tuck drapes
# them, torso-local: `rest[station][column]` for the four tail stations from the
# belt down (SkaterMeshBuilder.TORSO_BELT_STATION and on).

const FIRST_STATION: int = SkaterMeshBuilder.TORSO_BELT_STATION

var _skater: Skater = null
# Draping the connected-body prototype's tail (SkaterConnectedMesh), which has
# twice the rig's columns on bones of its own.
var _connected: bool = false


func _init() -> void:
	columns = SkaterMeshBuilder.TORSO_SIDES


func setup(skater: Skater, skeleton: Skeleton3D, tuck: int, connected: bool = false) -> void:
	_skater = skater
	_connected = connected
	if connected:
		columns = SkaterConnectedMesh.TAIL_COLUMNS
	bind(skeleton, SkaterMeshBuilder.UpperBone.TORSO, SkaterBodySkeleton.TAIL_BONE,
			SkaterBodySkeleton.connected_column_bone(0, 0) if connected
			else SkaterBodySkeleton.COLUMN_BONE_BASE,
			SkaterHemColliders.new(SkaterConnectedPants.collider_stations(),
					SkaterConnectedPants.COLLIDER_THIGH_RADIUS_M) if connected
			else SkaterHemColliders.new())
	set_tuck(tuck)


func set_tuck(tuck: int) -> void:
	rest.clear()
	for station: int in STATIONS:
		rest.append(SkaterConnectedMesh.tail_ring(FIRST_STATION + station, tuck) if _connected
				else SkaterMeshBuilder.torso_ring(FIRST_STATION + station, tuck))
	hips_share.resize(columns)
	tuck_share.resize(columns)
	var phase: float = TAU * SkaterMeshBuilder.TORSO_U_PHASE
	for k: int in columns:
		var azimuth: float = TAU * float(k) / float(columns) + phase
		# The connected tail is drawn in taut beside a tucked corner
		# (SkaterConnectedMesh.tail_ring), so it is held to that drape as far.
		tuck_share[k] = SkaterJerseyHem.tuck_share(tuck, azimuth) if _connected \
				else SkaterJerseyHem.tucked_in(tuck, azimuth)
		hips_share[k] = lerpf(SkaterJerseyHem.carry(azimuth), 1.0,
				SkaterJerseyHem.tuck_share(tuck, azimuth))
	restart()


# One frame: gravity less the skater's acceleration, then the step. Bones are
# written only when drawn; the swing keeps time off camera too.
func update(delta: float, on_camera: bool) -> void:
	var g: Vector3 = _skeleton.global_basis.orthonormalized().inverse() \
			* Vector3(0.0, -gravity_m_s2, 0.0) - _acceleration()
	step(delta, g, on_camera)


# Steps a still figure's drape is settled for: long past its swing's settling.
const SETTLE_STEPS: int = 90


# The torso as a figure that is not a skinned rig wears it (FigureKit — the
# player screen's mannequin, the lobby's bench): the tail settled hanging over the
# figure's own pants and legs, and baked into the torso's own frame. `torso`,
# `pelvis` and each leg's frame at its hip (as SkaterBodySkeleton's LEG bone
# carries it, scaled by the leg's bulk) are the figure's parts in one upright
# space.
static func baked_torso(tuck: int, torso: Transform3D, pelvis: Transform3D,
		legs: Array[Transform3D]) -> ArrayMesh:
	var skeleton: Skeleton3D = SkaterBodySkeleton.new_body_skeleton()
	var leg_bones: Array[int] = [SkaterMeshBuilder.LegBone.LEG_L, SkaterMeshBuilder.LegBone.LEG_R]
	skeleton.set_bone_pose(SkaterMeshBuilder.UpperBone.TORSO, torso)
	skeleton.set_bone_pose(SkaterBodySkeleton.TAIL_BONE, torso)
	skeleton.set_bone_pose(SkaterMeshBuilder.UpperBone.PELVIS, pelvis)
	for i: int in 2:
		skeleton.set_bone_pose(SkaterBodySkeleton.LEG_BONE_OFFSET + leg_bones[i], legs[i])
	var flaps := SkaterHemFlaps.new()
	flaps.setup(null, skeleton, tuck)
	for i: int in SETTLE_STEPS:
		flaps.step(1.0 / 60.0, Vector3(0.0, -flaps.gravity_m_s2, 0.0), i == SETTLE_STEPS - 1)
	var arrays: Array = SkaterMeshBuilder.shared_torso(tuck).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = SkaterMeshBuilder.shared_upper_skin_mesh(tuck) \
			.surface_get_arrays(SkaterMeshBuilder.UpperSurface.TORSO)[Mesh.ARRAY_BONES]
	var to_torso: Transform3D = torso.affine_inverse()
	for v: int in verts.size():
		var column_bind: int = bones[v * 4] - SkaterMeshBuilder.UPPER_COLUMN_BIND_BASE
		if column_bind < 0:
			continue
		var moved: Transform3D = to_torso * skeleton.get_bone_pose(
				SkaterBodySkeleton.COLUMN_BONE_BASE + column_bind)
		verts[v] = moved * verts[v]
		normals[v] = (moved.basis * normals[v]).normalized()
	skeleton.free()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# The skater's acceleration, skeleton space: what the balance lean leans toward
# (BalanceRules — atan(|a| / g)), so it is read back off the lean.
func _acceleration() -> Vector3:
	var tilt: Vector2 = _skater.balance_tilt()
	var angle: float = tilt.length()
	if angle < 1e-5:
		return Vector3.ZERO
	var world := Vector3(tilt.x, 0.0, tilt.y) / angle * gravity_m_s2 * tan(angle)
	return _skeleton.global_basis.orthonormalized().inverse() * world
