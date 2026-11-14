class_name AIFieldGrid

# A measured field's spot grid read between its spots: the (up to) four spots
# round a release, by bilinear weight, as the shot field blends its own. A
# release past the grid's edge reads the edge. A leaf: reads nothing.

# The corners filled by fill(): each spot's index (`fwd` row major, `x` minor)
# and its weight. Overwritten by the next fill: read them before calling again.
static var spot := PackedInt32Array([0, 0, 0, 0])
static var weight := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


# The four spots round `x` across and `out` metres out on the grid of `grid_x`
# by `grid_fwd`, into spot / weight.
static func fill(grid_x: Array[float], grid_fwd: Array[float], x: float, out: float) -> void:
	var xi: int = _lower(grid_x, x)
	var fi: int = _lower(grid_fwd, out)
	var tx: float = _frac(grid_x, xi, x)
	var tf: float = _frac(grid_fwd, fi, out)
	var nx: int = grid_x.size()
	var xj: int = mini(xi + 1, nx - 1)
	var fj: int = mini(fi + 1, grid_fwd.size() - 1)
	spot[0] = fi * nx + xi
	spot[1] = fi * nx + xj
	spot[2] = fj * nx + xi
	spot[3] = fj * nx + xj
	weight[0] = (1.0 - tx) * (1.0 - tf)
	weight[1] = tx * (1.0 - tf)
	weight[2] = (1.0 - tx) * tf
	weight[3] = tx * tf


# The last grid index at or below `v`, clamped to the grid.
static func _lower(grid: Array[float], v: float) -> int:
	var i: int = 0
	while i + 1 < grid.size() - 1 and grid[i + 1] <= v:
		i += 1
	return i


# How far `v` lies from grid[i] to grid[i + 1], clamped to [0, 1].
static func _frac(grid: Array[float], i: int, v: float) -> float:
	if i + 1 >= grid.size():
		return 0.0
	return clampf((v - grid[i]) / (grid[i + 1] - grid[i]), 0.0, 1.0)
