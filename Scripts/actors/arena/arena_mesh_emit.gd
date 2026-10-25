class_name ArenaMeshEmit

# SurfaceTool primitives the bowl's geometry is poured from. Pure emitters:
# every one appends triangles for the arguments it is given and reads nothing
# else, which is what lets the terraces, the seats and the spectator figures
# share them without any of the three depending on the others.
#
# Winding is CCW-is-front, matching Godot. Where a caller's material culls back
# faces (the terraces and the shell do) the winding is load-bearing and the
# caller's own comment says which way; where it culls nothing (the vomitory
# tunnels) either winding is fine.


# Horizontal quad strip between an inner and an outer perimeter ring, at `y`.
static func tread(st: SurfaceTool, inner: PackedVector2Array,
		outer: PackedVector2Array, y: float) -> void:
	var n: int = inner.size()
	for i: int in n:
		var j: int = (i + 1) % n
		var ia: Vector3 = Vector3(inner[i].x, y, inner[i].y)
		var oa: Vector3 = Vector3(outer[i].x, y, outer[i].y)
		var ib: Vector3 = Vector3(inner[j].x, y, inner[j].y)
		var ob: Vector3 = Vector3(outer[j].x, y, outer[j].y)
		# CCW from above so normals point +Y.
		st.add_vertex(ia)
		st.add_vertex(ib)
		st.add_vertex(ob)
		st.add_vertex(ia)
		st.add_vertex(ob)
		st.add_vertex(oa)


# Vertical wall along a perimeter ring, front face toward the rink interior.
static func riser(st: SurfaceTool, inner: PackedVector2Array,
		y_bot: float, y_top: float) -> void:
	var n: int = inner.size()
	for i: int in n:
		_riser_segment(st, inner[i], inner[(i + 1) % n], y_bot, y_top)


# `riser`, minus the segments flagged as doorways. `cut[i] == 1` drops the wall
# between point i and i+1.
static func riser_gapped(st: SurfaceTool, inner: PackedVector2Array,
		cut: PackedByteArray, y_bot: float, y_top: float) -> void:
	var n: int = inner.size()
	for i: int in n:
		if cut[i] == 1:
			continue
		_riser_segment(st, inner[i], inner[(i + 1) % n], y_bot, y_top)


# One wall panel. The winding is what fronts the whole bowl inward: on a path
# wound CCW from above, this order puts the front face toward the rink. The
# mirror winding fronts outward and is culled from every in-bowl camera, taking
# the risers, the fascia and the shell wall with it.
static func _riser_segment(st: SurfaceTool, a: Vector2, b: Vector2,
		y_bot: float, y_top: float) -> void:
	var ba := Vector3(a.x, y_bot, a.y)
	var ta := Vector3(a.x, y_top, a.y)
	var bb := Vector3(b.x, y_bot, b.y)
	var tb := Vector3(b.x, y_top, b.y)
	st.add_vertex(ba)
	st.add_vertex(bb)
	st.add_vertex(tb)
	st.add_vertex(ba)
	st.add_vertex(tb)
	st.add_vertex(ta)


# End wall of a rinkside well, at one ring sample: spans the row's tread
# inward-to-outward and the step the well cuts. `toward` points into the well,
# and the face is wound to look that way because the terrace material culls back
# faces.
static func well_side(st: SurfaceTool, p_in: Vector2, p_out: Vector2,
		y_lo: float, y_hi: float, toward: Vector2) -> void:
	var a := Vector3(p_in.x, y_lo, p_in.y)
	var b := Vector3(p_out.x, y_lo, p_out.y)
	var c := Vector3(p_out.x, y_hi, p_out.y)
	var d := Vector3(p_in.x, y_hi, p_in.y)
	if (b - a).cross(c - a).dot(Vector3(toward.x, 0.0, toward.y)) > 0.0:
		quad(st, a, b, c, d)
	else:
		quad(st, a, d, c, b)


# A horizontal quad through four ground points at height `y`.
static func deck_quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2,
		d: Vector2, y: float) -> void:
	st.add_vertex(Vector3(a.x, y, a.y))
	st.add_vertex(Vector3(b.x, y, b.y))
	st.add_vertex(Vector3(c.x, y, c.y))
	st.add_vertex(Vector3(a.x, y, a.y))
	st.add_vertex(Vector3(c.x, y, c.y))
	st.add_vertex(Vector3(d.x, y, d.y))


# A vertical quad between two ground points. Wound either way is fine for the
# only caller (the tunnels), whose surfaces are all double-sided.
static func vertical_quad(st: SurfaceTool, a: Vector2, b: Vector2,
		y_bot: float, y_top: float) -> void:
	st.add_vertex(Vector3(a.x, y_bot, a.y))
	st.add_vertex(Vector3(b.x, y_bot, b.y))
	st.add_vertex(Vector3(b.x, y_top, b.y))
	st.add_vertex(Vector3(a.x, y_bot, a.y))
	st.add_vertex(Vector3(b.x, y_top, b.y))
	st.add_vertex(Vector3(a.x, y_top, a.y))


static func box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h: Vector3 = size * 0.5
	# 8 corners
	var p: Array[Vector3] = [
		center + Vector3(-h.x, -h.y, -h.z),  # 0
		center + Vector3( h.x, -h.y, -h.z),  # 1
		center + Vector3( h.x, -h.y,  h.z),  # 2
		center + Vector3(-h.x, -h.y,  h.z),  # 3
		center + Vector3(-h.x,  h.y, -h.z),  # 4
		center + Vector3( h.x,  h.y, -h.z),  # 5
		center + Vector3( h.x,  h.y,  h.z),  # 6
		center + Vector3(-h.x,  h.y,  h.z),  # 7
	]
	# Six faces, each two CCW-wound triangles (Godot front = CCW).
	# +Y (top)
	quad(st, p[4], p[7], p[6], p[5])
	# -Y (bottom)
	quad(st, p[0], p[1], p[2], p[3])
	# +Z (front)
	quad(st, p[3], p[2], p[6], p[7])
	# -Z (back)
	quad(st, p[1], p[0], p[4], p[5])
	# +X (right)
	quad(st, p[2], p[1], p[5], p[6])
	# -X (left)
	quad(st, p[0], p[3], p[7], p[4])


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


# ── Faceted solids ───────────────────────────────────────────────────────────
# Unlike the primitives above, these carry their own flat normal and a `part`
# code in UV.x on every vertex, so a mesh poured from them must use nothing
# else (a SurfaceTool's format is fixed by its first vertex).

# One triangle wound and lit to face away from `inside`. Godot's front faces
# wind clockwise seen from outside, the opposite of the right-hand cross the
# normal is taken from, hence a-c-b.
static func facet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		inside: Vector3, part: float) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
		var t: Vector3 = b
		b = c
		c = t
	var uv := Vector2(part, 0.0)
	for v: Vector3 in [a, c, b]:
		st.set_normal(n)
		st.set_uv(uv)
		st.add_vertex(v)


# A shell through `rings` (closed loops of one count, in order), each band lit
# away from its own axis. A cap goes on an end only where it can be seen.
static func loft(st: SurfaceTool, rings: Array[PackedVector3Array], part: float,
		cap_start: bool, cap_end: bool) -> void:
	for r: int in rings.size() - 1:
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		var axis: Vector3 = (_centroid(a) + _centroid(b)) * 0.5
		for i: int in a.size():
			var j: int = (i + 1) % a.size()
			facet(st, a[i], a[j], b[j], axis, part)
			facet(st, a[i], b[j], b[i], axis, part)
	if cap_start:
		_loft_cap(st, rings[0], rings[1], part)
	if cap_end:
		_loft_cap(st, rings[rings.size() - 1], rings[rings.size() - 2], part)


# A square-sectioned limb from `from` to `to`, `width` across `side` and
# `depth` across the third axis.
static func beam(st: SurfaceTool, from: Vector3, to: Vector3, width: float,
		depth: float, side: Vector3, part: float, cap_from: bool, cap_to: bool) -> void:
	var along: Vector3 = (to - from).normalized()
	var across: Vector3 = (side - along * side.dot(along)).normalized() * width * 0.5
	var through: Vector3 = along.cross(across).normalized() * depth * 0.5
	var rings: Array[PackedVector3Array] = []
	for end: Vector3 in [from, to]:
		rings.append(PackedVector3Array([end - across - through, end + across - through,
				end + across + through, end - across + through]))
	loft(st, rings, part, cap_from, cap_to)


static func _loft_cap(st: SurfaceTool, ring: PackedVector3Array,
		neighbour: PackedVector3Array, part: float) -> void:
	var c: Vector3 = _centroid(ring)
	var inside: Vector3 = c + (_centroid(neighbour) - c) * 0.5
	# A fan from one corner: the rings are convex, and it costs two fewer
	# triangles than a fan from the centre.
	for i: int in range(1, ring.size() - 1):
		facet(st, ring[0], ring[i], ring[i + 1], inside, part)


static func _centroid(ring: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p: Vector3 in ring:
		sum += p
	return sum / float(ring.size())
