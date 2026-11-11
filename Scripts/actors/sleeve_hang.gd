class_name SleeveHang
extends RefCounted

# Hangs a jersey's sleeve between its armhole and its elbow (the skater's,
# SkaterConnectedMesh, and the keeper's, KeeperJerseyMesh): a loose sleeve is
# cloth hung between the two, not a tube on the arm. Why is in
# Scripts/actors/CLAUDE.md, *The body's skin*.

# The upper arm's first ring's share on the shoulder's middle rather than the
# arm: over the top of the arm, and at its sides. All of it on the shoulder over
# the top puts the whole of the arm's turn between this ring and the next, a
# step where the arm leaves the shoulder.
const FIRST_RING_SHOULDER := Vector2(0.45, 1.0)


# How far round under the arm each of `ring`'s vertices is, 0 straight over it
# to 1 straight under, about the arm's `axis` in the bind pose. The sleeve's
# rings run vertex for vertex, so one ring's serve every ring's columns.
static func under_shares(b: ConnectedSkinBuilder, ring: PackedInt32Array,
		axis: Vector3) -> PackedFloat32Array:
	var centre: Vector3 = b.centroid(ring)
	var over_arm: Vector3 = (Vector3.UP - axis * axis.y).normalized()
	var under := PackedFloat32Array()
	for id: int in ring:
		under.append(0.5 - 0.5 * (b.position(id) - centre).normalized().dot(over_arm))
	return under


# Weights the upper arm's first ring between the shoulder's middle and the arm.
static func ride_shoulder(b: ConnectedSkinBuilder, ring: PackedInt32Array,
		under: PackedFloat32Array, shoulder: int, upper: int) -> void:
	for m: int in ring.size():
		var share: float = lerpf(FIRST_RING_SHOULDER.x, FIRST_RING_SHOULDER.y,
				smoothstep(0.0, 0.5, under[m]))
		b.reweight(ring[m], [shoulder, upper], [share, 1.0 - share])


# Hangs `columns`, the sleeve's rings from the seam to the elbow's own, each
# weighted as it rides over the arm. As far as a column is under the arm
# (`under`) its vertices between the two are laid toward the straight line
# from the seam to the elbow and weighted toward the hang: on `chest` at the
# seam, and by the way down to the elbow on the arm instead (`upper`, and
# `elbow` by the ring's share on it, `elbow_shares`).
static func hang(b: ConnectedSkinBuilder, columns: Array[PackedInt32Array],
		under: PackedFloat32Array, chest: int, upper: int, elbow: int,
		elbow_shares: PackedFloat32Array) -> void:
	var at_elbow: int = columns.size() - 1
	for m: int in under.size():
		var hung: float = smoothstep(0.0, 1.0, under[m])
		var from: Vector3 = b.position(columns[0][m])
		var to: Vector3 = b.position(columns[at_elbow][m])
		var along: PackedFloat32Array = _lengths_down(b, columns, m)
		for k: int in range(1, at_elbow):
			var id: int = columns[k][m]
			b.move(id, b.position(id).lerp(from.lerp(to, along[k] / along[at_elbow]), hung))
		along = _lengths_down(b, columns, m)
		for k: int in at_elbow:
			var down: float = along[k] / along[at_elbow]
			b.blend_toward(columns[k][m], [chest, upper, elbow], [1.0 - down,
					down * (1.0 - elbow_shares[k]), down * elbow_shares[k]], hung)


# How far down column `m` each of `columns`' rings is from the first, metres.
static func _lengths_down(b: ConnectedSkinBuilder, columns: Array[PackedInt32Array],
		m: int) -> PackedFloat32Array:
	var along := PackedFloat32Array([0.0])
	for k: int in range(1, columns.size()):
		along.append(along[k - 1] + b.position(columns[k - 1][m]).distance_to(
				b.position(columns[k][m])))
	return along
