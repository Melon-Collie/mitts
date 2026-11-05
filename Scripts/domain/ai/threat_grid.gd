class_name AIThreatGrid
extends RefCounted

# The threat grid's cells, the other side's view of one, and the solve that
# values them (docs/xt-plan.md §3). Pure: the transitions are measured elsewhere
# (the threat-grid generator) and handed to `solve`.
#
# A cell is read in the attacking side's frame, as AIShotOdds reads a release:
# `out` metres in front of the goal line it attacks (negative behind it), `x`
# across, turned with the net so either side reads the same grid. Rows are cut
# on the goal lines and blue lines, so no cell straddles a gate; in their zone
# and behind their net they are finer and run the full width, since the keeper
# and the shot field are not symmetric across x.
#
# A state is a cell and a context (Context, `context_of`): the grid values the
# attacking side's possession there. The other side's possession of a spot is the same
# grid read from its own frame (`other_side`), negated.

enum Context { SET, RUSH }
const CONTEXTS: int = 2

const _GOAL_LINE_OUT: float = 0.0
const _THEIR_BLUE_OUT: float = GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z
const _OUR_BLUE_OUT: float = GameRules.GOAL_LINE_Z + GameRules.BLUE_LINE_Z
const _OUR_GOAL_OUT: float = 2.0 * GameRules.GOAL_LINE_Z
const _BEHIND_M: float = GameRules.INNER_HALF_LENGTH - GameRules.GOAL_LINE_Z
const _HALF_W: float = GameRules.INNER_HALF_WIDTH
# Row depths and column widths, by stretch of ice: their zone and behind their
# net fine, the neutral zone and our end coarse.
const FINE_ROW_M: float = 1.5
const COARSE_ROW_M: float = 3.0
const FINE_COLUMNS: int = 17
const COARSE_COLUMNS: int = 9
# A rush counts the attackers in on the play: no further from the net than the
# puck by more than this, a stride's reach.
const RUSH_BAND_M: float = 3.0

# Row edges in `out`, ascending; each row's column count and its first cell.
static var _row_edges := PackedFloat32Array()
static var _row_columns := PackedInt32Array()
static var _row_first := PackedInt32Array()
# Each row's stretch of ice (rows between the same two lines share one), so the
# value is read smoothly within a stretch and never across a line.
static var _row_stretch := PackedInt32Array()
static var _stretches: int = 0
static var _cells: int = 0


static func _build() -> void:
	if _cells > 0:
		return
	_row_edges.clear()
	_row_columns.clear()
	_row_stretch.clear()
	_stretches = 0
	_add_stretch(-_BEHIND_M, _GOAL_LINE_OUT, _BEHIND_M, FINE_COLUMNS)
	_add_stretch(_GOAL_LINE_OUT, _THEIR_BLUE_OUT, FINE_ROW_M, FINE_COLUMNS)
	_add_stretch(_THEIR_BLUE_OUT, _OUR_BLUE_OUT, COARSE_ROW_M, COARSE_COLUMNS)
	_add_stretch(_OUR_BLUE_OUT, _OUR_GOAL_OUT, COARSE_ROW_M, COARSE_COLUMNS)
	_add_stretch(_OUR_GOAL_OUT, _OUR_GOAL_OUT + _BEHIND_M, _BEHIND_M, COARSE_COLUMNS)
	_row_edges.append(_OUR_GOAL_OUT + _BEHIND_M)
	_row_first.resize(_row_columns.size())
	var n: int = 0
	for r: int in _row_columns.size():
		_row_first[r] = n
		n += _row_columns[r]
	_cells = n


# Rows from `from` to `to`, as near `row_m` deep as divides the stretch evenly.
static func _add_stretch(from: float, to: float, row_m: float, columns: int) -> void:
	var rows: int = maxi(roundi((to - from) / row_m), 1)
	for i: int in rows:
		_row_edges.append(lerpf(from, to, float(i) / float(rows)))
		_row_columns.append(columns)
		_row_stretch.append(_stretches)
	_stretches += 1


static func cell_count() -> int:
	_build()
	return _cells


static func state_count() -> int:
	return cell_count() * CONTEXTS


static func state(cell: int, context: int) -> int:
	return cell * CONTEXTS + context


# The cell holding `local_pos` (x across, out from the goal line attacked), clamped
# onto the ice.
static func cell_of(local_pos: Vector2) -> int:
	_build()
	var r: int = _row_of(local_pos.y)
	var cols: int = _row_columns[r]
	var c: int = clampi(int(floor((local_pos.x + _HALF_W) / (2.0 * _HALF_W) * cols)), 0, cols - 1)
	return _row_first[r] + c


# The row holding `out`, clamped onto the ice.
static func _row_of(out: float) -> int:
	var rows: int = _row_columns.size()
	for i: int in rows:
		if out < _row_edges[i + 1]:
			return i
	return rows - 1


# The attacking side's possession at `local_pos` in `context`, from the
# generated grid: linear between cell centres along a row and between rows,
# never across a goal line or blue line (a stretch's edge), so the value is
# smooth inside each stretch of ice and steps only where the rules do.
static func value(local_pos: Vector2, context: int) -> float:
	_build()
	var r: int = _row_of(local_pos.y)
	var mid: float = 0.5 * (_row_edges[r] + _row_edges[r + 1])
	var r2: int = r + (1 if local_pos.y > mid else -1)
	if r2 < 0 or r2 >= _row_columns.size() or _row_stretch[r2] != _row_stretch[r]:
		return _row_value(r, local_pos.x, context)
	var mid2: float = 0.5 * (_row_edges[r2] + _row_edges[r2 + 1])
	var w: float = clampf((local_pos.y - mid) / (mid2 - mid), 0.0, 1.0)
	return lerpf(_row_value(r, local_pos.x, context), _row_value(r2, local_pos.x, context), w)


static func _row_value(r: int, x: float, context: int) -> float:
	var cols: int = _row_columns[r]
	var u: float = clampf((x + _HALF_W) / (2.0 * _HALF_W) * cols - 0.5, 0.0, cols - 1.0)
	var c: int = mini(int(floor(u)), cols - 2)
	var a: float = AIThreatGridData.VALUES[state(_row_first[r] + c, context)]
	var b: float = AIThreatGridData.VALUES[state(_row_first[r] + c + 1, context)]
	return lerpf(a, b, u - c)


# The centre of `cell`, in the attacking frame.
static func centre(cell: int) -> Vector2:
	_build()
	var r: int = _row_first.bsearch(cell, false) - 1
	var cols: int = _row_columns[r]
	var c: int = cell - _row_first[r]
	return Vector2(-_HALF_W + (float(c) + 0.5) * 2.0 * _HALF_W / cols,
			0.5 * (_row_edges[r] + _row_edges[r + 1]))


# `world` in the frame of the side attacking the net at `goal`: x across, out
# in front of its goal line.
static func local(world: Vector3, goal: Vector3) -> Vector2:
	var mirror: float = -signf(goal.z)
	return Vector2((world.x - goal.x) * mirror, (world.z - goal.z) * mirror)


# A spot in one side's attacking frame, in the other side's: the rink turned
# end for end.
static func other_side(local_pos: Vector2) -> Vector2:
	return Vector2(-local_pos.x, _OUR_GOAL_OUT - local_pos.y)


# RUSH while the attack has more men in on the play than the defence has
# between the puck and the net: attackers (the carrier among them) no further
# from the net at `goal` than the puck by more than RUSH_BAND_M, against
# defenders nearer the net than the puck. SET otherwise.
static func context_of(puck: Vector3, attackers: Array[Vector3], defenders: Array[Vector3],
		goal: Vector3) -> int:
	var d: float = _flat_distance(puck, goal)
	var in_on_it: int = 0
	for a: Vector3 in attackers:
		if _flat_distance(a, goal) <= d + RUSH_BAND_M:
			in_on_it += 1
	var back: int = 0
	for b: Vector3 in defenders:
		if _flat_distance(b, goal) < d:
			back += 1
	return Context.RUSH if in_on_it > back else Context.SET


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# One measured outcome of a state's next macro event: its weight (its share of
# the state's samples × the decay over its duration) and where it goes. `to` is
# a state index, or −1 for a terminal worth `terminal`; `theirs` marks a state in
# the other side's frame (a turnover), worth the negative of its value.
class Outcome:
	var weight: float = 0.0
	var to: int = -1
	var theirs: bool = false
	var terminal: float = 0.0


# Solves V(s) = Σ weight · (terminal, or ±V(to)) over `outcomes` (one Array of
# Outcome per state), by Gauss–Seidel from 0 until no value moves more than
# `tolerance`. Converges while every state's weights sum below one, which the
# decay ensures. Returns the values, one per state.
static func solve(outcomes: Array, tolerance: float = 1e-6, max_sweeps: int = 10000) -> PackedFloat32Array:
	var n: int = outcomes.size()
	var v := PackedFloat32Array()
	v.resize(n)
	v.fill(0.0)
	for _sweep: int in max_sweeps:
		var moved: float = 0.0
		for s: int in n:
			var total: float = 0.0
			for o: Outcome in outcomes[s]:
				if o.to < 0:
					total += o.weight * o.terminal
				else:
					total += o.weight * (-v[o.to] if o.theirs else v[o.to])
			moved = maxf(moved, absf(total - v[s]))
			v[s] = total
		if moved < tolerance:
			break
	return v
