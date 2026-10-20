class_name TeamCrest
extends RefCounted

# Procedural fruit crests: the team's fruit, mostly cut open, in the team's own
# colors, rimmed by a thin keyline. Each fruit is drawn in a unit space — y
# down, the fruit inside the unit circle — through whatever transform the caller
# set, so the same drawing lands on a jersey texture (stretched to its texel
# aspect) or a flat preview.

enum Style { OUTLINED, OUTLINED_DARK, OUTLINED_DOUBLE }

const STYLE_NAMES: PackedStringArray = ["outlined", "outlined_dark", "outlined_double"]

# The keyline, in unit-space units (about 8 mm on a 28 cm crest).
const OUTLINE_WIDTH: float = 0.06
# OUTLINED_DOUBLE's two keylines, dark against the fruit and light outside it
# (about 6 mm each).
const DOUBLE_LINE_WIDTH: float = 0.045
# A part keeps a color an earlier part already took unless an untaken team color
# is within this much of as close (OKLab distance): two parts snapping to one
# color merge, which is better than a far-off color that no longer reads.
const REUSE_MARGIN: float = 0.1

# Each fruit's parts as their real colors, in the order they claim a team color
# (the part that most says "this fruit" first). The drawing reads them by index.
const _FRUIT_COLORS: Dictionary = {
	"blackberry": [Color("#2A1735"), Color("#7A4A8A"), Color("#3E7D3A")],
	"blueberry": [Color("#3B5BA8"), Color("#22355F")],
	"cherry": [Color("#C8102E"), Color("#3E7D3A")],
	"coconut": [Color("#6B4226"), Color("#F5F0E1"), Color("#5A3A22")],
	"dragonfruit": [Color("#E0306F"), Color("#FFFFFF"), Color("#1A1A1A"), Color("#D04A7A")],
	"lemon": [Color("#F7D52A"), Color("#FFF8D6"), Color("#F9E36A")],
	"lime": [Color("#3F7F1F"), Color("#EAF5C8"), Color("#A6D84A")],
	"peach": [Color("#E8734A"), Color("#F7B550"), Color("#8A3B2A"), Color("#3E7D3A")],
	"pineapple": [Color("#F7C531"), Color("#3E8E4A"), Color("#B5781E"), Color("#FBE9A0")],
	"plum": [Color("#5B2A6E"), Color("#F2C14E"), Color("#9C5A2E"), Color("#6B4A2A")],
	"pomegranate": [Color("#9E1B2C"), Color("#F3E3CF"), Color("#E0405A")],
	"watermelon": [Color("#2F7D3A"), Color("#EEF6DA"), Color("#E8485C"), Color("#1A1A1A")],
}

# While > 0, every shape is drawn grown by this much in `_grow_color` — the
# silhouette pass under the fruit that leaves the keyline showing.
static var _grow: float = 0.0
static var _grow_color: Color = Color.WHITE


# The crest for `fruit` in `style`, centred on `xform`'s origin with the unit
# circle mapped through it, colored from `preset` (a TeamColorRegistry preset).
static func draw(canvas: CanvasItem, fruit: String, style: int, xform: Transform2D,
		preset: Dictionary) -> void:
	var colors: Array = team_colors(fruit, preset)
	canvas.draw_set_transform_matrix(xform)
	# Keylines outermost first, each a silhouette pass the next one covers.
	match style:
		Style.OUTLINED:
			_silhouette(canvas, fruit, colors, OUTLINE_WIDTH, preset.light)
		Style.OUTLINED_DARK:
			_silhouette(canvas, fruit, colors, OUTLINE_WIDTH, dark_color(preset))
		Style.OUTLINED_DOUBLE:
			_silhouette(canvas, fruit, colors, DOUBLE_LINE_WIDTH * 2.0, preset.light)
			_silhouette(canvas, fruit, colors, DOUBLE_LINE_WIDTH, dark_color(preset))
	_draw_fruit(canvas, fruit, colors)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _silhouette(canvas: CanvasItem, fruit: String, colors: Array, grow: float,
		color: Color) -> void:
	_grow = grow
	_grow_color = color
	_draw_fruit(canvas, fruit, colors)
	_grow = 0.0


# The light is what the away sweater is based on: alone, it rims the fruit at
# home and vanishes on the road. The dark — the darker of primary and secondary —
# rims it on the road, and at home unless that is the home color.
static func dark_color(preset: Dictionary) -> Color:
	var primary: Color = preset.primary
	var secondary: Color = preset.secondary
	return primary if primary.get_luminance() < secondary.get_luminance() else secondary


# The fruit's parts, each snapped to the nearest color anywhere in the team's
# palette or kits.
static func team_colors(fruit: String, preset: Dictionary) -> Array:
	var pool: Array[Color] = []
	_collect_colors(preset, pool)
	var out: Array = []
	for want: Color in _FRUIT_COLORS.get(fruit, _FRUIT_COLORS.cherry):
		var nearest: Color = _nearest(want, pool, [])
		var pick: Color = nearest
		if out.has(nearest):
			var free: Color = _nearest(want, pool, out)
			if _distance(want, free) < _distance(want, nearest) + REUSE_MARGIN:
				pick = free
		out.append(pick)
	return out


static func _collect_colors(value: Variant, pool: Array[Color]) -> void:
	if value is Color:
		for have: Color in pool:
			if have.is_equal_approx(value):
				return
		pool.append(value)
	elif value is Dictionary:
		for v: Variant in (value as Dictionary).values():
			_collect_colors(v, pool)
	elif value is Array:
		for v: Variant in value:
			_collect_colors(v, pool)


# The pool color nearest `want`, skipping `taken` unless that leaves none.
static func _nearest(want: Color, pool: Array[Color], taken: Array) -> Color:
	var best: Color = pool[0]
	var best_d: float = INF
	for c: Color in pool:
		if taken.has(c):
			continue
		var d: float = _distance(want, c)
		if d < best_d:
			best = c
			best_d = d
	return best if best_d < INF else _nearest(want, pool, [])


# Perceptual distance: Euclidean in OKLab.
static func _distance(a: Color, b: Color) -> float:
	return _oklab(a).distance_to(_oklab(b))


static func _oklab(c: Color) -> Vector3:
	var lin: Color = c.srgb_to_linear()
	var l: float = pow(0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b, 1.0 / 3.0)
	var m: float = pow(0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b, 1.0 / 3.0)
	var s: float = pow(0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b, 1.0 / 3.0)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
			1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
			0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


static func _draw_fruit(c: CanvasItem, fruit: String, k: Array) -> void:
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
		_: _circle(c, Vector2.ZERO, 0.9, k[0])


# ── Fruits ───────────────────────────────────────────────────────────────────
# Cut open where the inside is what says the fruit; whole for the berries, whose
# insides say nothing.


static func _blackberry(c: CanvasItem, k: Array) -> void:
	var berry: Color = k[0]
	var rim: Color = k[1]
	var leaf: Color = k[2]
	_leaf(c, Vector2(0.0, -0.62), Vector2(-0.55, -0.98), 0.22, leaf)
	_leaf(c, Vector2(0.0, -0.62), Vector2(0.55, -0.98), 0.22, leaf)
	_poly(c, _ellipse(Vector2(0.0, 0.08), Vector2(0.5, 0.66)), berry)
	# Drupelet rows as (y, count).
	for row: Vector2 in [Vector2(-0.38, 3), Vector2(-0.08, 4), Vector2(0.22, 3),
			Vector2(0.5, 2)]:
		for i: int in int(row.y):
			var at := Vector2((float(i) - (row.y - 1.0) * 0.5) * 0.3, row.x)
			_circle(c, at, 0.19, rim)
			_circle(c, at, 0.15, berry)


static func _blueberry(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var calyx: Color = k[1]
	_circle(c, Vector2(0.0, 0.08), 0.88, skin)
	_poly(c, _star(Vector2(0.0, -0.36), 0.36, 0.15, 5), calyx)
	_circle(c, Vector2(0.0, -0.36), 0.08, skin)


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


static func _dragonfruit(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var flesh: Color = k[1]
	var seed: Color = k[2]
	var bract: Color = k[3]
	# Halved lengthwise: bract tips flaring past the skin, then the flesh.
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
		_poly(c, _ellipse(at, Vector2(0.04, 0.06), 10), seed)


static func _lemon(c: CanvasItem, k: Array) -> void:
	var peel: Color = k[0]
	var pith: Color = k[1]
	var flesh: Color = k[2]
	# Halved, cut face tipped toward the viewer: the uncut half runs off to the
	# right to its nub, the cut face is a wheel seen at an angle.
	var tilt := Transform2D(-0.3, Vector2(0.0, 0.05))
	var cut_x: float = -0.3
	var body := PackedVector2Array()
	for i: int in 25:
		var t: float = lerpf(-PI * 0.5, PI * 0.5, float(i) / 24.0)
		var nub: float = 0.2 * pow(cos(t), 14.0)
		body.append(tilt * Vector2(cut_x + cos(t) * (0.78 + nub), sin(t) * 0.6))
	_poly(c, body, peel)
	var face := Vector2(cut_x, 0.0)
	_poly(c, _transformed(tilt, _ellipse(face, Vector2(0.32, 0.6))), peel)
	_poly(c, _transformed(tilt, _ellipse(face, Vector2(0.27, 0.52))), pith)
	var squash := Transform2D(Vector2(0.24, 0.0), Vector2(0.0, 0.47), face)
	for wedge: PackedVector2Array in _wheel_wedges(8, 0.12):
		_poly(c, _transformed(tilt * squash, wedge), flesh)


static func _lime(c: CanvasItem, k: Array) -> void:
	var rind: Color = k[0]
	var pith: Color = k[1]
	var flesh: Color = k[2]
	_circle(c, Vector2.ZERO, 0.95, rind)
	_circle(c, Vector2.ZERO, 0.82, pith)
	for wedge: PackedVector2Array in _wheel_wedges(8, 0.12):
		_poly(c, _transformed(Transform2D(0.0, Vector2.ONE * 0.72, 0.0, Vector2.ZERO), wedge),
				flesh)


static func _peach(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var flesh: Color = k[1]
	var pit: Color = k[2]
	var leaf: Color = k[3]
	_line(c, Vector2(0.0, -0.55), Vector2(0.06, -0.88), leaf, 0.1)
	_leaf(c, Vector2(0.05, -0.82), Vector2(0.7, -0.98), 0.26, leaf)
	# Halved through the cleft, which stays as the notch at the top.
	for half: float in [-0.16, 0.16]:
		_circle(c, Vector2(half, 0.12), 0.74, skin)
	for half: float in [-0.16, 0.16]:
		_circle(c, Vector2(half, 0.12), 0.64, flesh)
	_poly(c, _ellipse(Vector2(0.0, 0.16), Vector2(0.27, 0.34)), pit)
	_curve(c, Vector2(0.0, -0.12), Vector2(-0.07, 0.16), Vector2(0.0, 0.44), 0.045, flesh)


static func _pineapple(c: CanvasItem, k: Array) -> void:
	var flesh: Color = k[0]
	var crown: Color = k[1]
	var rind: Color = k[2]
	var core: Color = k[3]
	for spike: Vector3 in [Vector3(0.0, -1.02, 0.17), Vector3(-0.32, -0.95, 0.15),
			Vector3(0.32, -0.95, 0.15), Vector3(-0.58, -0.7, 0.14), Vector3(0.58, -0.7, 0.14)]:
		_leaf(c, Vector2(0.0, -0.3), Vector2(spike.x, spike.y), spike.z, crown)
	# Halved lengthwise: the rind as a band, the flesh, the core down the middle.
	var center := Vector2(0.0, 0.3)
	_poly(c, _ellipse(center, Vector2(0.56, 0.68)), rind)
	_poly(c, _ellipse(center, Vector2(0.46, 0.58)), flesh)
	_poly(c, _ellipse(center + Vector2(0.0, -0.02), Vector2(0.11, 0.46)), core)


static func _plum(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var flesh: Color = k[1]
	var pit: Color = k[2]
	var stem: Color = k[3]
	var tilt := Transform2D(0.2, Vector2(0.0, 0.1))
	_line(c, tilt * Vector2(0.0, -0.7), tilt * Vector2(0.12, -1.02), stem, 0.1)
	_poly(c, _transformed(tilt, _ellipse(Vector2.ZERO, Vector2(0.64, 0.8))), skin)
	_poly(c, _transformed(tilt, _ellipse(Vector2.ZERO, Vector2(0.54, 0.7))), flesh)
	_leaf(c, tilt * Vector2(0.0, -0.36), tilt * Vector2(0.0, 0.38), 0.36, pit)


static func _pomegranate(c: CanvasItem, k: Array) -> void:
	var rind: Color = k[0]
	var pith: Color = k[1]
	var aril: Color = k[2]
	_poly(c, PackedVector2Array([
		Vector2(-0.3, -0.5), Vector2(-0.4, -0.98), Vector2(-0.18, -0.78),
		Vector2(0.0, -1.02), Vector2(0.18, -0.78), Vector2(0.4, -0.98), Vector2(0.3, -0.5)]), rind)
	# Halved across: rind, pith, and the seeds packed inside it.
	var center := Vector2(0.0, 0.16)
	_circle(c, center, 0.82, rind)
	_circle(c, center, 0.71, pith)
	for row: int in range(-2, 3):
		var y: float = float(row) * 0.235
		var shift: float = 0.135 if row % 2 != 0 else 0.0
		for col: int in range(-3, 4):
			var at := Vector2(float(col) * 0.27 + shift, y)
			if at.length() < 0.56:
				_circle(c, center + at, 0.12, aril)


static func _watermelon(c: CanvasItem, k: Array) -> void:
	var rind: Color = k[0]
	var pith: Color = k[1]
	var flesh: Color = k[2]
	var seed: Color = k[3]
	var top: float = -0.38
	_poly(c, _half_disc(Vector2(0.0, top), 1.0), rind)
	_poly(c, _half_disc(Vector2(0.0, top), 0.9), pith)
	_poly(c, _half_disc(Vector2(0.0, top), 0.8), flesh)
	for at: Vector2 in [Vector2(-0.45, 0.0), Vector2(0.0, 0.08), Vector2(0.45, 0.0),
			Vector2(-0.22, 0.3), Vector2(0.22, 0.3)]:
		_poly(c, _ellipse(Vector2(at.x, top + 0.18 + at.y), Vector2(0.06, 0.1)), seed)


# ── Primitives (grown in the silhouette pass) ────────────────────────────────


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


static func _star(center: Vector2, outer: float, inner: float, points: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in points * 2:
		var r: float = outer if i % 2 == 0 else inner
		pts.append(center + Vector2.from_angle(-PI * 0.5 + PI * float(i) / points) * r)
	return pts


# A citrus wheel's segments in the unit circle, `gap` radians apart.
static func _wheel_wedges(segments: int, gap: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for i: int in segments:
		var a0: float = TAU * float(i) / segments + gap * 0.5
		var a1: float = TAU * float(i + 1) / segments - gap * 0.5
		var wedge := PackedVector2Array([Vector2.from_angle((a0 + a1) * 0.5) * 0.14])
		for j: int in 7:
			wedge.append(Vector2.from_angle(lerpf(a0, a1, float(j) / 6.0)))
		out.append(wedge)
	return out


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
