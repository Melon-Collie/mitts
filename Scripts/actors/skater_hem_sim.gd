class_name SkaterHemSim
extends RefCounted

# What the three draping hem sims share (HemSimMode): the tail below the belt
# is one column per torso facet, hung from that facet's point on the belt ring.
# The belt point is where the swung tail's weights put it (SkaterJerseyHem):
# carried by the chest and the hips in the share the azimuth and the tuck give
# it, so above the belt the jersey is exactly the swung one with its swing held
# still, and only the drape below it is the sim's.
#
# The rest drape is the lathe's own rings, tucked as the skater's tuck drapes
# them, torso-local: `rest[station][column]` for the four tail stations from the
# belt down (SkaterMeshBuilder.TORSO_BELT_STATION and on).

const FIRST_STATION: int = SkaterMeshBuilder.TORSO_BELT_STATION
const STATIONS: int = SkaterMeshBuilder.TORSO_HEM_STATION - SkaterMeshBuilder.TORSO_BELT_STATION + 1
const BEND: int = SkaterMeshBuilder.TORSO_BEND_STATION - SkaterMeshBuilder.TORSO_BELT_STATION
const HEM: int = STATIONS - 1

var columns: int = SkaterMeshBuilder.TORSO_SIDES
var rest: Array[PackedVector3Array] = []
# Per column: how much of the belt point the hips carry, and how tucked it is.
var hips_share := PackedFloat32Array()
var tuck_share := PackedFloat32Array()

var _skater: Skater = null
var _skeleton: Skeleton3D = null
var _colliders := SkaterHemColliders.new()


func setup(skater: Skater, skeleton: Skeleton3D, tuck: int) -> void:
	_skater = skater
	_skeleton = skeleton
	set_tuck(tuck)


func set_tuck(tuck: int) -> void:
	rest.clear()
	for station: int in STATIONS:
		rest.append(SkaterMeshBuilder.torso_ring(FIRST_STATION + station, tuck))
	hips_share.resize(columns)
	tuck_share.resize(columns)
	var phase: float = TAU * SkaterMeshBuilder.TORSO_U_PHASE
	for k: int in columns:
		var azimuth: float = TAU * float(k) / float(columns) + phase
		tuck_share[k] = SkaterJerseyHem.tuck_share(tuck, azimuth)
		hips_share[k] = lerpf(SkaterJerseyHem.carry(azimuth), 1.0, tuck_share[k])
	_rested()


# Called once the rest drape has changed.
func _rested() -> void:
	pass


func update(_delta: float, _on_camera: bool) -> void:
	pass


# Where the tail is drawn, in skeleton space: a sample of points on it for the
# comparison's clipping measure.
func hem_points() -> PackedVector3Array:
	return PackedVector3Array()


func colliders() -> SkaterHemColliders:
	return _colliders


# Each column's belt point this frame, in skeleton space.
func anchors(torso: Transform3D, tail: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(columns)
	var belt: PackedVector3Array = rest[0]
	for k: int in columns:
		out[k] = (torso * belt[k]).lerp(tail * belt[k], hips_share[k])
	return out


func _torso() -> Transform3D:
	return _skeleton.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TORSO)


func _tail() -> Transform3D:
	return _skeleton.get_bone_global_pose(SkaterBodySkeleton.TAIL_BONE)


# The skater's acceleration, skeleton space: what the balance lean leans toward
# (BalanceRules — atan(|a| / g)), so it is read back off the lean.
func _acceleration() -> Vector3:
	var tilt: Vector2 = _skater.balance_tilt()
	var angle: float = tilt.length()
	if angle < 1e-5:
		return Vector3.ZERO
	var world := Vector3(tilt.x, 0.0, tilt.y) / angle * 9.8 * tan(angle)
	return _skeleton.global_basis.orthonormalized().inverse() * world
