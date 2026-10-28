class_name KeeperMeshKit
extends RefCounted

# Flat-shaded low-poly geometry for the keeper's gear, the same faceted style as
# the skaters. A piece is built as a set of surfaces, one per paint slot, so the
# kit colours it; vertex colour is a tint under the paint (white takes the slot's
# colour as is, grey darkens it for a crease or a panel line).
#
# Every triangle is wound outward from a centre the caller names, so convex-ish
# shells come out right whichever order their vertices were listed in.

enum Slot {
	PADS, JERSEY, PANTS, GLOVES, ACCENT,
	HELMET, CAGE, SKATE_BOOT, SKATE_STEEL, STICK, STICK_TAPE, STRAP, SKIN, SOCK,
}
const SLOT_COUNT: int = 14

var _tools: Array[SurfaceTool] = []
var _used: Array[bool] = []
var tint: Color = Color.WHITE


func _init() -> void:
	for i: int in SLOT_COUNT:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools.append(st)
		_used.append(false)


# One triangle in `slot`, wound to face away from `inside`, with its own flat
# normal.
func tri(slot: int, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	var mid: Vector3 = (a + b + c) / 3.0
	if n.dot(mid - inside) < 0.0:
		n = -n
		var t: Vector3 = b
		b = c
		c = t
	# Godot's front faces wind clockwise seen from outside: the opposite of the
	# right-hand cross that `n` was taken from.
	var st: SurfaceTool = _tools[slot]
	_used[slot] = true
	for v: Vector3 in [a, c, b]:
		st.set_color(tint)
		st.set_normal(n)
		st.add_vertex(v)


func quad(slot: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	tri(slot, a, b, c, inside)
	tri(slot, a, c, d, inside)


# A shell swept through `rings` (each a closed loop of the same count, in
# order), capped at both ends. `inside` is a point inside the whole shell.
func sweep(slot: int, rings: Array[PackedVector3Array], inside: Vector3,
		cap_start: bool = true, cap_end: bool = true) -> void:
	for r: int in rings.size() - 1:
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		var mid: Vector3 = (_centroid(a) + _centroid(b)) * 0.5
		var to_ring: Vector3 = mid if mid.distance_to(inside) > 0.0 else inside
		for i: int in a.size():
			var j: int = (i + 1) % a.size()
			quad(slot, a[i], a[j], b[j], b[i], to_ring)
	if cap_start:
		_cap(slot, rings[0], rings[1])
	if cap_end:
		_cap(slot, rings[rings.size() - 1], rings[rings.size() - 2])


func _cap(slot: int, ring: PackedVector3Array, neighbour: PackedVector3Array) -> void:
	var c: Vector3 = _centroid(ring)
	# The cap faces away from the ring next to it.
	var inside: Vector3 = c + (_centroid(neighbour) - c) * 0.5
	for i: int in ring.size():
		tri(slot, c, ring[i], ring[(i + 1) % ring.size()], inside)


static func _centroid(ring: PackedVector3Array) -> Vector3:
	var s := Vector3.ZERO
	for v: Vector3 in ring:
		s += v
	return s / float(maxi(ring.size(), 1))


func box(slot: int, center: Vector3, half: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var c: Array[Vector3] = []
	for k: int in 8:
		var s := Vector3(-1.0 if k & 1 == 0 else 1.0, -1.0 if k & 2 == 0 else 1.0,
				-1.0 if k & 4 == 0 else 1.0)
		c.append(center + basis * (half * s))
	var faces: Array = [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6],
			[0, 2, 6, 4], [1, 3, 7, 5]]
	for f: Array in faces:
		quad(slot, c[f[0]], c[f[1]], c[f[2]], c[f[3]], center)


# A prebuilt mesh's first surface into `slot`, placed by `xform`. Its own
# vertex colours stay its tints.
func append(slot: int, mesh: ArrayMesh, xform: Transform3D) -> void:
	_tools[slot].append_from(mesh, 0, xform)
	_used[slot] = true


# A square bar of half thickness `r` from `a` to `b`.
func rod(slot: int, a: Vector3, b: Vector3, r: float) -> void:
	var d: Vector3 = b - a
	var y: Vector3 = d.normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.UP)
	x = x.normalized()
	box(slot, (a + b) * 0.5, Vector3(r, d.length() * 0.5, r), Basis(x, y, x.cross(y)))


# A loop of `n` points round an ellipse in the plane square to `axis` (X, Y or
# Z: 0, 1, 2) at `at` along it, radii `ra` and `rb` on the other two axes in
# order, starting at angle `phase`.
static func ellipse(axis: int, at: Vector3, ra: float, rb: float, n: int,
		phase: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i: int in n:
		var t: float = phase + TAU * float(i) / float(n)
		var u: float = cos(t) * ra
		var w: float = sin(t) * rb
		match axis:
			0:
				out.append(at + Vector3(0.0, u, w))
			1:
				out.append(at + Vector3(u, 0.0, w))
			_:
				out.append(at + Vector3(u, w, 0.0))
	return out


# A loop round a rounded rectangle square to Y: half widths `hx`, `hz` with the
# corners cut back by `cut` — the faceted section the pads and the trunk use.
# `front` scales the −Z half on its own, so a face can stand proud of the back.
static func octagon(y: float, hx: float, hz: float, cut: float, front: float = 1.0,
		cx: float = 0.0, cz: float = 0.0) -> PackedVector3Array:
	var f: float = hz * front
	var out := PackedVector3Array()
	out.append(Vector3(cx - hx + cut, y, cz - f))
	out.append(Vector3(cx + hx - cut, y, cz - f))
	out.append(Vector3(cx + hx, y, cz - f + cut))
	out.append(Vector3(cx + hx, y, cz + hz - cut))
	out.append(Vector3(cx + hx - cut, y, cz + hz))
	out.append(Vector3(cx - hx + cut, y, cz + hz))
	out.append(Vector3(cx - hx, y, cz + hz - cut))
	out.append(Vector3(cx - hx, y, cz - f + cut))
	return out


# A loop of `n` points round a rounded box square to Y at height `y`: a
# superellipse of `order` (2 an ellipse, higher squarer), half width `hx`,
# reaching `front` toward −Z and `back` toward +Z.
static func rounded(y: float, hx: float, front: float, back: float, n: int,
		order: float) -> PackedVector3Array:
	var e: float = 2.0 / order
	var out := PackedVector3Array()
	for i: int in n:
		var t: float = TAU * (float(i) + 0.5) / float(n)
		var sx: float = signf(sin(t)) * pow(absf(sin(t)), e)
		var cz: float = signf(cos(t)) * pow(absf(cos(t)), e)
		out.append(Vector3(sx * hx, y, -cz * (front if cz > 0.0 else back)))
	return out


# A low-poly ellipsoid: `rings` bands from pole to pole, its meridians from
# `phase` (match a sleeve's, and the sleeve leaves it on a clean ring).
func ellipsoid(slot: int, center: Vector3, r: Vector3, rings: int = 6, segs: int = 10,
		phase: float = 0.0) -> void:
	var loops: Array[PackedVector3Array] = []
	for i: int in range(1, rings):
		var a: float = PI * float(i) / float(rings)
		loops.append(ellipse(1, center + Vector3(0.0, -cos(a) * r.y, 0.0),
				sin(a) * r.x, sin(a) * r.z, segs, phase))
	var bottom: Vector3 = center - Vector3(0.0, r.y, 0.0)
	var top: Vector3 = center + Vector3(0.0, r.y, 0.0)
	for i: int in segs:
		var j: int = (i + 1) % segs
		tri(slot, bottom, loops[0][i], loops[0][j], center)
		tri(slot, top, loops[loops.size() - 1][i], loops[loops.size() - 1][j], center)
	for k: int in loops.size() - 1:
		for i: int in segs:
			var j: int = (i + 1) % segs
			quad(slot, loops[k][i], loops[k][j], loops[k + 1][j], loops[k + 1][i], center)


# A flat outline in X-Y, extruded from z0 to z1 (a convex outline).
func slab(slot: int, outline: PackedVector2Array, z0: float, z1: float) -> void:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	for p: Vector2 in outline:
		a.append(Vector3(p.x, p.y, z0))
		b.append(Vector3(p.x, p.y, z1))
	var rings: Array[PackedVector3Array] = [a, b]
	sweep(slot, rings, (_centroid(a) + _centroid(b)) * 0.5)


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i: int in SLOT_COUNT:
		if not _used[i]:
			continue
		_tools[i].commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, Slot.keys()[i])
	return mesh


# Which slot each of a committed mesh's surfaces paints from.
static func surface_slots(mesh: ArrayMesh) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s: int in mesh.get_surface_count():
		out.append(Slot.keys().find(mesh.surface_get_name(s)))
	return out
