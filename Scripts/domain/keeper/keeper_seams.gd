class_name KeeperSeams
extends RefCounted

# The gaps a puck fits through in the shape he shows a shot straight on, inside
# his outline. The mouth is laid out in square cells (x across from its centre,
# y up from the ice, inside the iron) and each is one of:
#   OPEN   the puck, flat as it slides or flies, fits clear of him here
#   BODY   his gear's silhouette, from the save boxes
#   SHUT   no gear, but a puck centred here would touch some
#   SEAM   OPEN, closed in by him: his body to its left, its right and above,
#          and no way out to the open net round him that a puck fits through.
#          A notch between two pieces that opens onto the net (under the
#          glove, beside the hip) is the net, not a hole in him
# A flat puck is 7.6 cm across and only 2.5 cm tall, so a slit under a pad's toe
# is a seam as much as one between the pads.

enum Cell { OPEN, BODY, SHUT, SEAM }

const STEP_M: float = 0.01


# The mouth's cells, row by row from the ice up, `columns(step)` to a row.
static func classify(skel: KeeperSkeleton, step: float = STEP_M) -> PackedByteArray:
	var nx: int = columns(step)
	var ny: int = rows(step)
	var cells := PackedByteArray()
	cells.resize(nx * ny)
	cells.fill(Cell.OPEN)
	for part: int in KeeperGear.PART_COUNT:
		_rasterize(cells, nx, ny, step, _silhouette(KeeperGear.box(skel, part),
				KeeperGear.half_extents(part)))
	_shut_round_the_body(cells, nx, ny, step)
	_mark_seams(cells, nx, ny)
	_open_to_the_net(cells, nx, ny)
	return cells


# Each seam's bounds in the mouth plane, metres: x across from the mouth's
# centre, y up from the ice.
static func find(skel: KeeperSkeleton, step: float = STEP_M) -> Array[Rect2]:
	var cells: PackedByteArray = classify(skel, step)
	var nx: int = columns(step)
	var ny: int = rows(step)
	var out: Array[Rect2] = []
	var seen := PackedByteArray()
	seen.resize(nx * ny)
	var stack := PackedInt32Array()
	for start: int in cells.size():
		if cells[start] != Cell.SEAM or seen[start] != 0:
			continue
		var lo := Vector2i(nx, ny)
		var hi := Vector2i(-1, -1)
		stack.push_back(start)
		seen[start] = 1
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var at := Vector2i(c % nx, c / nx)
			lo = lo.min(at)
			hi = hi.max(at)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = at + d
				if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= ny:
					continue
				var ni: int = n.y * nx + n.x
				if cells[ni] == Cell.SEAM and seen[ni] == 0:
					seen[ni] = 1
					stack.push_back(ni)
		out.append(Rect2(cell_center(lo, step) - Vector2.ONE * step * 0.5,
				Vector2(hi - lo + Vector2i.ONE) * step))
	return out


# Columns sit on whole steps from the mouth's centre, so where he is sampled
# does not move with the mouth's width.
static func columns(step: float) -> int:
	return 2 * _half_columns(step) + 1


static func _half_columns(step: float) -> int:
	return floori(_inner_half_width() / step - 0.5 + 1e-6)


static func rows(step: float) -> int:
	return ceili(_inner_height() / step)


# A cell's centre in the mouth plane.
static func cell_center(cell: Vector2i, step: float) -> Vector2:
	return Vector2(float(cell.x - _half_columns(step)) * step, (float(cell.y) + 0.5) * step)


static func _inner_half_width() -> float:
	return GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS


static func _inner_height() -> float:
	return GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS


# A box's outline seen straight on: the convex hull of its corners in x and y.
static func _silhouette(xf: Transform3D, h: Vector3) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k: int in 8:
		var c: Vector3 = xf * Vector3(h.x * (1.0 if k & 1 else -1.0), h.y * (1.0 if k & 2 else -1.0),
				h.z * (1.0 if k & 4 else -1.0))
		pts.append(Vector2(c.x, c.y))
	return _hull(pts)


# The convex hull, counter-clockwise (Andrew's monotone chain).
static func _hull(pts: PackedVector2Array) -> PackedVector2Array:
	var sorted: Array[Vector2] = []
	for p: Vector2 in pts:
		sorted.append(p)
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var out := PackedVector2Array()
	for pass_i: int in 2:
		var start: int = out.size()
		for k: int in sorted.size():
			var p: Vector2 = sorted[k] if pass_i == 0 else sorted[sorted.size() - 1 - k]
			while out.size() >= start + 2 and (out[out.size() - 1] - out[out.size() - 2]).cross(
					p - out[out.size() - 2]) <= 0.0:
				out.remove_at(out.size() - 1)
			out.append(p)
		out.remove_at(out.size() - 1)
	return out


static func _inside(p: Vector2, hull: PackedVector2Array) -> bool:
	for k: int in hull.size():
		var a: Vector2 = hull[k]
		var b: Vector2 = hull[(k + 1) % hull.size()]
		if (b - a).cross(p - a) < 0.0:
			return false
	return true


static func _rasterize(cells: PackedByteArray, nx: int, ny: int, step: float,
		hull: PackedVector2Array) -> void:
	if hull.size() < 3:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in hull:
		lo = lo.min(p)
		hi = hi.max(p)
	var x0: float = -(float(_half_columns(step)) + 0.5) * step
	var i0: int = maxi(floori((lo.x - x0) / step), 0)
	var i1: int = mini(ceili((hi.x - x0) / step), nx - 1)
	var j0: int = maxi(floori(lo.y / step), 0)
	var j1: int = mini(ceili(hi.y / step), ny - 1)
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			if _inside(cell_center(Vector2i(i, j), step), hull):
				cells[j * nx + i] = Cell.BODY


# Where a flat puck's centre cannot be without touching him: within its radius
# of his body across, within its half height of it up and down, and below its
# half height off the ice.
static func _shut_round_the_body(cells: PackedByteArray, nx: int, ny: int, step: float) -> void:
	var rx: int = roundi(GameRules.PUCK_COLLISION_RADIUS / step)
	var ry: int = roundi(GameRules.PUCK_COLLISION_HALF_HEIGHT / step)
	# Across first: how far each cell is from the nearest body in its row.
	var near_row := PackedByteArray()
	near_row.resize(nx * ny)
	for j: int in ny:
		var last: int = -1000
		for i: int in nx:
			if cells[j * nx + i] == Cell.BODY:
				last = i
			if i - last <= rx:
				near_row[j * nx + i] = 1
		last = 1000000
		for i: int in range(nx - 1, -1, -1):
			if cells[j * nx + i] == Cell.BODY:
				last = i
			if last - i <= rx:
				near_row[j * nx + i] = 1
	for j: int in ny:
		var below_ice: bool = (float(j) + 0.5) * step < GameRules.PUCK_COLLISION_HALF_HEIGHT
		for i: int in nx:
			var c: int = j * nx + i
			if cells[c] != Cell.OPEN:
				continue
			var shut: bool = below_ice
			for dj: int in range(-ry, ry + 1):
				var jj: int = j + dj
				if not shut and jj >= 0 and jj < ny and near_row[jj * nx + i] == 1:
					shut = true
			if shut:
				cells[c] = Cell.SHUT


# An open cell with his body to its left and right in its row and above it in
# its column may be a hole in him.
static func _mark_seams(cells: PackedByteArray, nx: int, ny: int) -> void:
	var first := PackedInt32Array()
	var last := PackedInt32Array()
	first.resize(ny)
	last.resize(ny)
	for j: int in ny:
		first[j] = nx
		last[j] = -1
		for i: int in nx:
			if cells[j * nx + i] == Cell.BODY:
				first[j] = mini(first[j], i)
				last[j] = i
	var top := PackedInt32Array()
	top.resize(nx)
	for i: int in nx:
		top[i] = -1
		for j: int in ny:
			if cells[j * nx + i] == Cell.BODY:
				top[i] = j
	for j: int in ny:
		for i: int in nx:
			var c: int = j * nx + i
			if cells[c] == Cell.OPEN and first[j] < i and i < last[j] and top[i] > j:
				cells[c] = Cell.SEAM


# A candidate hole a puck can slide out of into the open net is the net: flood
# the open cells through the candidates.
static func _open_to_the_net(cells: PackedByteArray, nx: int, ny: int) -> void:
	var stack := PackedInt32Array()
	for c: int in cells.size():
		if cells[c] == Cell.OPEN:
			stack.push_back(c)
	while not stack.is_empty():
		var c: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var i: int = c % nx
		var j: int = c / nx
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = i + d.x
			var nj: int = j + d.y
			if ni < 0 or nj < 0 or ni >= nx or nj >= ny:
				continue
			var n: int = nj * nx + ni
			if cells[n] == Cell.SEAM:
				cells[n] = Cell.OPEN
				stack.push_back(n)
