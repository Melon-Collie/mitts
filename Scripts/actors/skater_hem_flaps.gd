class_name SkaterHemFlaps
extends HemFlaps

# The skater's jersey tail below the belt as flaps (HemFlaps), one per tail
# column (SkaterConnectedMesh.TAIL_COLUMNS): each segment a root bone
# (SkaterBodySkeleton.column_bone) that its column's vertices ride rigidly.
#
# A column hangs from its point on the belt ring, which is where the torso's own
# weights put it — carried by the chest and the hips in the share the azimuth
# and the tuck give it — so the jersey is one surface across the belt. It drapes
# over the thighs and the pants (SkaterHemColliders), driven by gravity less the
# skater's acceleration, read off his balance lean; a figure with no skater (the
# locker's, the bench's) hangs under gravity alone.
#
# The rest drape is the skin's own tail rings, tucked as the skater's tuck
# drapes them, torso-local: `rest[station][column]` for the four tail stations
# from the belt down (SkaterConnectedMesh.tail_ring). Beside a tucked corner the
# tail is drawn in taut, so each column is held to its drape as far as the tuck
# pulls it.

const FIRST_STATION: int = SkaterMeshBuilder.TORSO_BELT_STATION
# The skin's faces are drawn from its columns, so a hem that shingles round the
# ring turns them over.
const SHEAR_STIFFNESS: float = 0.5
# Steps a still figure's drape is settled for: long past its swing's settling.
const SETTLE_STEPS: int = 90

var _skater: Skater = null


func _init() -> void:
	columns = SkaterConnectedMesh.TAIL_COLUMNS
	shear_stiffness = SHEAR_STIFFNESS


# `skater` is null for a figure that is not one.
func setup(skater: Skater, skeleton: Skeleton3D, tuck: int) -> void:
	_skater = skater
	bind(skeleton, SkaterMeshBuilder.UpperBone.TORSO, SkaterBodySkeleton.TAIL_BONE,
			SkaterBodySkeleton.column_bone(0, 0), SkaterHemColliders.new())
	set_tuck(tuck)


func set_tuck(tuck: int) -> void:
	rest.clear()
	for station: int in STATIONS:
		rest.append(SkaterConnectedMesh.tail_ring(FIRST_STATION + station, tuck))
	hips_share.resize(columns)
	tuck_share.resize(columns)
	var phase: float = TAU * SkaterMeshBuilder.TORSO_U_PHASE
	for k: int in columns:
		var azimuth: float = TAU * float(k) / float(columns) + phase
		tuck_share[k] = SkaterJerseyHem.tuck_share(tuck, azimuth)
		hips_share[k] = lerpf(SkaterJerseyHem.carry(azimuth), 1.0, tuck_share[k])
	restart()


# One frame: gravity less the skater's acceleration, then the step. Bones are
# written only when drawn; the swing keeps time off camera too.
func update(delta: float, on_camera: bool) -> void:
	var g: Vector3 = _skeleton.global_basis.orthonormalized().inverse() \
			* Vector3(0.0, -gravity_m_s2, 0.0) - _acceleration()
	step(delta, g, on_camera)


# Hangs the drape still, for an upright figure posed and then left: from its
# rest, swung out under gravity and settled, its bones written.
func settle() -> void:
	restart()
	for i: int in SETTLE_STEPS:
		step(1.0 / 60.0, Vector3(0.0, -gravity_m_s2, 0.0), i == SETTLE_STEPS - 1)


# The skater's acceleration, skeleton space: what the balance lean leans toward
# (BalanceRules — atan(|a| / g)), so it is read back off the lean.
func _acceleration() -> Vector3:
	if _skater == null:
		return Vector3.ZERO
	var tilt: Vector2 = _skater.balance_tilt()
	var angle: float = tilt.length()
	if angle < 1e-5:
		return Vector3.ZERO
	var world := Vector3(tilt.x, 0.0, tilt.y) / angle * gravity_m_s2 * tan(angle)
	return _skeleton.global_basis.orthonormalized().inverse() * world
