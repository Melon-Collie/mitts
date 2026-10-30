class_name CrestFruits
extends RefCounted

# The fruit drawings TeamCrest puts on a chest, one per team, keyed by the
# team's name in lower case. Each is drawn in a unit space — y down, the fruit
# inside the unit circle — through the caller's transform. Its colors are the
# real fruit's, listed in the order they claim a team color (TeamCrest snaps
# them), and read here by index.

# Greens a crest keeps as drawn rather than snapping to the team's (keeps):
# they read as the plant, not the team. Dragonfruit's bracts are petals in the
# skin's pink; the cherry's stems and the peach's leaves would go black or navy
# in a team without a green.
const DRAGONFRUIT_GREEN: Color = Color("#7BBF3A")
const PLANT_GREEN: Color = Color("#3E8E3A")

const _LEAF: Color = Color("#3E7D3A")

const _COLORS: Dictionary = {
	"blackberry": [Color("#4A2050"), Color("#1E1420"), _LEAF],
	"blueberry": [Color("#3B5BA8"), Color("#22355F"), _LEAF],
	"cherry": [Color("#C8102E"), PLANT_GREEN],
	"coconut": [Color("#6B4226"), Color("#F5F0E1"), Color("#5A3A22")],
	"dragonfruit": [Color("#E0306F"), Color("#FFFFFF"), Color("#1A1A1A"), DRAGONFRUIT_GREEN],
	"lemon": [Color("#F7D52A"), Color("#FFF3A6"), _LEAF],
	"lime": [Color("#3F7F1F"), Color("#EAF5C8"), Color("#A6D84A")],
	"peach": [Color("#F08A66"), Color("#D9643F"), PLANT_GREEN],
	"pineapple": [Color("#F2B233"), Color("#3E8E4A"), Color("#9C6418")],
	"plum": [Color("#5B2A6E"), Color("#F0A23A"), Color("#6B4A2A"), _LEAF],
	"pomegranate": [Color("#9E1B2C"), Color("#F3E3CF"), Color("#E0405A")],
	"watermelon": [Color("#2F7D3A"), Color("#EEF6DA"), Color("#E8485C"), Color("#1A1A1A")],
}

# While > 0, every shape is drawn grown by this much in `_grow_color` — a
# silhouette pass, which TeamCrest stacks under the fruit as its keylines.
static var _grow: float = 0.0
static var _grow_color: Color = Color.WHITE


static func keeps(color: Color) -> bool:
	return color == DRAGONFRUIT_GREEN or color == PLANT_GREEN


static func has(fruit: String) -> bool:
	return _COLORS.has(fruit)


# The real colors of `fruit`'s parts, in claiming order.
static func wanted_colors(fruit: String) -> Array:
	return _COLORS[fruit]


# Draws `fruit` with `k` (its parts' colors, as wanted_colors orders them); with
# `grow` > 0, draws only its silhouette grown by that much, in `grow_color`.
static func draw(c: CanvasItem, fruit: String, k: Array, grow: float = 0.0,
		grow_color: Color = Color.WHITE) -> void:
	_grow = grow
	_grow_color = grow_color
	match fruit:
		"blackberry": _blackberry(c, k)
		"blueberry": _blueberry(c, k)
		"cherry": _cherry(c, k)
		"coconut": _coconut(c, k)
		"dragonfruit": _dragonfruit(c, k)
		"lemon": _lemon(c, k)
		"lime": _lime(c, k)
		"peach": _peach(c, k)
		"pineapple": _pineapple(c, k)
		"plum": _plum(c, k)
		"pomegranate": _pomegranate(c, k)
		"watermelon": _watermelon(c, k)
	_grow = 0.0


# ── Fruits ───────────────────────────────────────────────────────────────────


static func _blackberry(c: CanvasItem, k: Array) -> void:
	var berry: Color = k[0]
	var rim: Color = k[1]
	var leaf: Color = k[2]
	_leaf(c, Vector2(0.0, -0.62), Vector2(-0.55, -0.98), 0.2, leaf)
	_leaf(c, Vector2(0.0, -0.62), Vector2(0.55, -0.98), 0.2, leaf)
	_line(c, Vector2(0.0, -0.6), Vector2(0.05, -1.0), leaf, 0.09)
	_poly(c, _ellipse(Vector2(0.0, 0.08), Vector2(0.5, 0.68)), berry)
	# Drupelet rows as (y, count), packed to overlap so they read as one berry.
	for row: Vector2 in [Vector2(-0.42, 3), Vector2(-0.17, 4), Vector2(0.08, 4),
			Vector2(0.33, 3), Vector2(0.56, 2)]:
		for i: int in int(row.y):
			var at := Vector2((float(i) - (row.y - 1.0) * 0.5) * 0.27, row.x)
			_circle(c, at, 0.17, rim)
			_circle(c, at, 0.145, berry)
			_circle(c, at - Vector2(0.045, 0.045), 0.04, rim)


# A cluster of three, each rimmed in the calyx color so they read apart.
static func _blueberry(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var calyx: Color = k[1]
	_leaf(c, Vector2(0.15, -0.55), Vector2(0.92, -0.9), 0.32, k[2])
	for berry: Vector3 in [Vector3(0.05, -0.25, 0.48), Vector3(-0.4, 0.3, 0.5),
			Vector3(0.4, 0.34, 0.47)]:
		var at := Vector2(berry.x, berry.y)
		_circle(c, at, berry.z + 0.04, calyx)
		_circle(c, at, berry.z, skin)
		_poly(c, _star(at + Vector2(0.0, -0.05), 0.2, 0.08, 5), calyx)


static func _cherry(c: CanvasItem, k: Array) -> void:
	var fruit: Color = k[0]
	var stem: Color = k[1]
	var apex := Vector2(0.15, -0.8)
	_curve(c, Vector2(-0.45, 0.1), Vector2(-0.3, -0.45), apex, 0.1, stem)
	_curve(c, Vector2(0.45, 0.16), Vector2(0.35, -0.35), apex, 0.1, stem)
	_leaf(c, apex, Vector2(0.82, -0.85), 0.26, stem)
	_circle(c, Vector2(-0.45, 0.45), 0.45, fruit)
	_circle(c, Vector2(0.45, 0.5), 0.43, fruit)


static func _coconut(c: CanvasItem, k: Array) -> void:
	var shell: Color = k[0]
	var flesh: Color = k[1]
	var hollow: Color = k[2]
	# A half shell, cut face tipped toward the viewer: the shell's lower half,
	# the flesh rim, and the hollow inside it.
	var tilt := Transform2D(-0.3, Vector2.ZERO)
	var bowl := PackedVector2Array()
	for i: int in 25:
		var t: float = PI * float(i) / 24.0
		bowl.append(tilt * Vector2(cos(t) * 0.9, sin(t) * 0.8))
	_poly(c, bowl, shell)
	_poly(c, _transformed(tilt, _ellipse(Vector2.ZERO, Vector2(0.9, 0.48))), flesh)
	_poly(c, _transformed(tilt, _ellipse(Vector2(0.0, 0.02), Vector2(0.7, 0.33))), hollow)


# Halved lengthwise: bract tips flaring past the skin, then the flesh and seeds.
static func _dragonfruit(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var flesh: Color = k[1]
	var seed_color: Color = k[2]
	var bract: Color = k[3]
	for b: Array in [
			[Vector2(0.0, -0.6), Vector2(0.0, -1.0)],
			[Vector2(-0.2, -0.55), Vector2(-0.48, -0.95)],
			[Vector2(0.2, -0.55), Vector2(0.48, -0.95)],
			[Vector2(-0.45, -0.15), Vector2(-0.86, -0.45)],
			[Vector2(0.45, -0.15), Vector2(0.86, -0.45)],
			[Vector2(-0.48, 0.32), Vector2(-0.9, 0.12)],
			[Vector2(0.48, 0.32), Vector2(0.9, 0.12)]]:
		_leaf(c, b[0], b[1], 0.24, bract)
	_poly(c, _ellipse(Vector2(0.0, 0.12), Vector2(0.62, 0.84)), skin)
	_poly(c, _ellipse(Vector2(0.0, 0.12), Vector2(0.5, 0.72)), flesh)
	# Seeds on a sunflower spiral: evenly spread with no grid to read.
	for i: int in 16:
		var r: float = sqrt((float(i) + 0.5) / 16.0) * 0.82
		var a: float = float(i) * 2.39996
		var at := Vector2(cos(a) * r * 0.5, 0.12 + sin(a) * r * 0.72)
		_poly(c, _ellipse(at, Vector2(0.04, 0.06), 10), seed_color)


static func _lemon(c: CanvasItem, k: Array) -> void:
	var tilt := Transform2D(-0.35, Vector2(0.0, 0.08))
	_leaf(c, Vector2(0.5, -0.38), Vector2(0.95, -0.92), 0.2, k[2])
	_poly(c, _transformed(tilt, _lemon_outline()), k[0])
	_arc(c, tilt.origin, 0.42, PI * 1.1, PI * 1.45, k[1], 0.08)


static func _lime(c: CanvasItem, k: Array) -> void:
	_circle(c, Vector2.ZERO, 0.95, k[0])
	_circle(c, Vector2.ZERO, 0.82, k[1])
	_wheel(c, Transform2D(0.0, Vector2.ONE * 0.72, 0.0, Vector2.ZERO), k[2])


static func _peach(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var cleft: Color = k[1]
	var leaf: Color = k[2]
	_line(c, Vector2(0.0, -0.62), Vector2(0.05, -0.9), leaf, 0.09)
	_leaf(c, Vector2(0.05, -0.85), Vector2(0.75, -0.95), 0.22, leaf)
	_leaf(c, Vector2(0.05, -0.85), Vector2(-0.55, -1.0), 0.16, leaf)
	_circle(c, Vector2(-0.17, 0.12), 0.76, skin)
	_circle(c, Vector2(0.17, 0.12), 0.76, skin)
	_curve(c, Vector2(0.0, -0.58), Vector2(-0.32, 0.05), Vector2(-0.1, 0.72), 0.07, cleft)


# A three-leaf crown over a body studded with diamond eyes.
static func _pineapple(c: CanvasItem, k: Array) -> void:
	for leaf: Vector3 in [Vector3(-0.72, -0.6, 0.24), Vector3(0.72, -0.6, 0.24),
			Vector3(-0.42, -0.98, 0.32), Vector3(0.42, -0.98, 0.32), Vector3(0.0, -1.05, 0.36)]:
		_leaf(c, Vector2(0.0, -0.25), Vector2(leaf.x, leaf.y), leaf.z, k[1])
	var center := Vector2(0.0, 0.32)
	var radii := Vector2(0.56, 0.66)
	_poly(c, _ellipse(center, radii), k[0])
	for row: int in range(-3, 4):
		var shift: float = 0.13 if row % 2 != 0 else 0.0
		for col: int in range(-3, 4):
			var at := Vector2(float(col) * 0.26 + shift, float(row) * 0.19)
			if (at.x / radii.x) ** 2 + (at.y / radii.y) ** 2 < 0.62:
				_poly(c, _star(center + at, 0.07, 0.07, 2), k[2])


# Halved through the stone: the skin's rim, the flesh, and the almond stone.
static func _plum(c: CanvasItem, k: Array) -> void:
	var leaf: Color = k[3]
	# Stem and leaf stay below the crest's top, where the sweater's collar hangs.
	_line(c, Vector2(0.0, -0.5), Vector2(0.05, -0.74), k[2], 0.09)
	_leaf(c, Vector2(0.04, -0.7), Vector2(0.6, -0.8), 0.22, leaf)
	var center := Vector2(0.0, 0.24)
	_poly(c, _ellipse(center, Vector2(0.72, 0.74)), k[0])
	_poly(c, _ellipse(center, Vector2(0.58, 0.6)), k[1])
	_leaf(c, center + Vector2(0.0, -0.37), center + Vector2(0.0, 0.37), 0.4, k[0])


# Halved across: the crown, rind, pith, and the seeds packed inside it.
static func _pomegranate(c: CanvasItem, k: Array) -> void:
	var rind: Color = k[0]
	_poly(c, PackedVector2Array([
		Vector2(-0.3, -0.5), Vector2(-0.4, -0.98), Vector2(-0.18, -0.78),
		Vector2(0.0, -1.02), Vector2(0.18, -0.78), Vector2(0.4, -0.98), Vector2(0.3, -0.5)]), rind)
	var center := Vector2(0.0, 0.16)
	_circle(c, center, 0.82, rind)
	_circle(c, center, 0.71, k[1])
	for row: int in range(-2, 3):
		var y: float = float(row) * 0.235
		var shift: float = 0.135 if row % 2 != 0 else 0.0
		for col: int in range(-3, 4):
			var at := Vector2(float(col) * 0.27 + shift, y)
			if at.length() < 0.56:
				_circle(c, center + at, 0.12, k[2])


static func _watermelon(c: CanvasItem, k: Array) -> void:
	var top: float = -0.38
	_poly(c, _half_disc(Vector2(0.0, top), 1.0), k[0])
	_poly(c, _half_disc(Vector2(0.0, top), 0.9), k[1])
	_poly(c, _half_disc(Vector2(0.0, top), 0.8), k[2])
	for at: Vector2 in [Vector2(-0.45, 0.0), Vector2(0.0, 0.08), Vector2(0.45, 0.0),
			Vector2(-0.22, 0.3), Vector2(0.22, 0.3)]:
		_poly(c, _ellipse(Vector2(at.x, top + 0.18 + at.y), Vector2(0.06, 0.1)), k[3])


# A lemon lying along x: an ellipse with a nub at each end.
static func _lemon_outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in 48:
		var t: float = TAU * float(i) / 48.0
		var nub: float = 0.18 * pow(absf(cos(t)), 12.0)
		pts.append(Vector2(cos(t) * (0.82 + nub), sin(t) * 0.6))
	return pts


# A citrus wheel's eight segments, the unit circle mapped through `xform`.
static func _wheel(c: CanvasItem, xform: Transform2D, color: Color) -> void:
	var gap: float = 0.12
	for i: int in 8:
		var a0: float = TAU * float(i) / 8.0 + gap * 0.5
		var a1: float = TAU * float(i + 1) / 8.0 - gap * 0.5
		var wedge := PackedVector2Array([Vector2.from_angle((a0 + a1) * 0.5) * 0.14])
		for j: int in 7:
			wedge.append(Vector2.from_angle(lerpf(a0, a1, float(j) / 6.0)))
		_poly(c, _transformed(xform, wedge), color)


# ── Primitives (grown in a silhouette pass) ──────────────────────────────────


static func _poly(c: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	if _grow <= 0.0:
		c.draw_colored_polygon(pts, color)
		return
	for grown: PackedVector2Array in Geometry2D.offset_polygon(pts, _grow,
			Geometry2D.JOIN_ROUND):
		c.draw_colored_polygon(grown, _grow_color)


static func _circle(c: CanvasItem, at: Vector2, r: float, color: Color) -> void:
	c.draw_circle(at, r + _grow, _grow_color if _grow > 0.0 else color)


static func _line(c: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	c.draw_line(a, b, _grow_color if _grow > 0.0 else color, width + 2.0 * _grow)


static func _polyline(c: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	c.draw_polyline(pts, _grow_color if _grow > 0.0 else color, width + 2.0 * _grow)


static func _arc(c: CanvasItem, center: Vector2, r: float, from: float, to: float,
		color: Color, width: float) -> void:
	c.draw_arc(center, r, from, to, 12, _grow_color if _grow > 0.0 else color,
			width + 2.0 * _grow)


# ── Shapes ───────────────────────────────────────────────────────────────────


static func _ellipse(center: Vector2, radii: Vector2, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in n:
		var t: float = TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(t) * radii.x, sin(t) * radii.y))
	return pts


static func _transformed(xform: Transform2D, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(xform * p)
	return out


static func _half_disc(top_center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in 33:
		pts.append(top_center + Vector2.from_angle(PI * float(i) / 32.0) * r)
	return pts


# `points` tips at `outer`, notches at `inner`; two tips with outer == inner is a
# diamond.
static func _star(center: Vector2, outer: float, inner: float, points: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in points * 2:
		var r: float = outer if i % 2 == 0 else inner
		pts.append(center + Vector2.from_angle(-PI * 0.5 + PI * float(i) / points) * r)
	return pts


# A pointed leaf from `base` to `tip`, `width` at its widest.
static func _leaf(c: CanvasItem, base: Vector2, tip: Vector2, width: float, color: Color) -> void:
	var along: Vector2 = tip - base
	var side: Vector2 = along.orthogonal().normalized() * width * 0.5
	var pts := PackedVector2Array()
	for i: int in 11:
		var t: float = float(i) / 10.0
		pts.append(base + along * t + side * sin(PI * t))
	for i: int in range(9, 0, -1):
		var t: float = float(i) / 10.0
		pts.append(base + along * t - side * sin(PI * t))
	_poly(c, pts, color)


# A quadratic stroke from `a` through control `ctrl` to `b`.
static func _curve(c: CanvasItem, a: Vector2, ctrl: Vector2, b: Vector2, width: float,
		color: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in 13:
		var t: float = float(i) / 12.0
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	_polyline(c, pts, color, width)
