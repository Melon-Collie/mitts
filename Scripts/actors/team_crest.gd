class_name TeamCrest
extends RefCounted

# Procedural fruit crests. Each fruit is drawn in a unit space — y down, the
# fruit inside the unit circle — through whatever transform the caller set, so
# the same drawing lands on a jersey texture (stretched to its texel aspect) or
# a flat preview. Colors come in four roles: BODY (the fruit), DETAIL (cut-outs:
# highlights, cleft, pith), ACCENT (leaves, stems, rind, the coconut's hollow)
# and MARK (seeds, calyx).

enum Style { FLAT, ROUNDEL, SHIELD, NATURAL, OUTLINED, OUTLINED_DARK }

const STYLE_NAMES: PackedStringArray = [
	"flat", "roundel", "shield", "natural", "outlined", "outlined_dark"]

const BODY: int = 0
const DETAIL: int = 1
const ACCENT: int = 2
const MARK: int = 3

# Inside a frame, the fruit is scaled to clear the ring.
const FRAMED_FRUIT_SCALE: float = 0.6
const RING_INNER: float = 0.84
# The OUTLINED keyline, in unit-space units (about 8 mm on a 28 cm crest).
const OUTLINE_WIDTH: float = 0.06

# While > 0, every shape is drawn grown by this much in `_grow_color` — the
# silhouette pass under an outlined fruit.
static var _grow: float = 0.0
static var _grow_color: Color = Color.WHITE

const _LEAF_GREEN: Color = Color("#3E7D3A")
# Natural colors, as [BODY, DETAIL, ACCENT, MARK].
const _NATURAL: Dictionary = {
	"blackberry": [Color("#2A1735"), Color("#7A5A9A"), _LEAF_GREEN, Color("#7A5A9A")],
	"blueberry": [Color("#3B5BA8"), Color("#9DB4E8"), _LEAF_GREEN, Color("#22355F")],
	"cherry": [Color("#C8102E"), Color("#F27C8A"), _LEAF_GREEN, Color("#F27C8A")],
	"coconut": [Color("#6B4226"), Color("#F5F0E1"), Color("#E3D6B8"), Color("#E3D6B8")],
	"dragonfruit": [Color("#E0306F"), Color("#FFC2D6"), Color("#7BBF3A"), Color("#FFC2D6")],
	"lemon": [Color("#F7D52A"), Color("#FFF3A6"), _LEAF_GREEN, Color("#FFF3A6")],
	"lime": [Color("#A6D84A"), Color("#EAF5C8"), Color("#3F7F1F"), Color("#EAF5C8")],
	"peach": [Color("#F4A06B"), Color("#D9643F"), _LEAF_GREEN, Color("#D9643F")],
	"pineapple": [Color("#F2B233"), Color("#9C6418"), Color("#3E8E4A"), Color("#9C6418")],
	"plum": [Color("#5B2A6E"), Color("#A57BBE"), Color("#6B4A2A"), Color("#A57BBE")],
	"pomegranate": [Color("#B3202F"), Color("#F07C8C"), Color("#B3202F"), Color("#F07C8C")],
	"watermelon": [Color("#E8485C"), Color("#EEF6DA"), Color("#2F7D3A"), Color("#1A1A1A")],
}


# The crest for `fruit` in `style`, centred on `xform`'s origin with the unit
# circle mapped through it. `kit` is the side's kit block, `preset` the team's.
static func draw(canvas: CanvasItem, fruit: String, style: int, xform: Transform2D,
		preset: Dictionary, kit: Dictionary) -> void:
	var colors: Array = _palette(fruit, style, preset, kit)
	canvas.draw_set_transform_matrix(xform)
	var fruit_xform: Transform2D = xform
	if style == Style.OUTLINED or style == Style.OUTLINED_DARK:
		_grow = OUTLINE_WIDTH
		_grow_color = colors[4]
		_draw_fruit(canvas, fruit, colors)
		_grow = 0.0
	elif style != Style.FLAT:
		var ring: Color = colors[4]
		var field: Color = colors[5]
		if style == Style.SHIELD:
			_shield(canvas, 1.0, ring)
			_shield(canvas, RING_INNER, field)
		else:
			canvas.draw_circle(Vector2.ZERO, 1.0, ring)
			canvas.draw_circle(Vector2.ZERO, RING_INNER, field)
		fruit_xform = xform * Transform2D(0.0, Vector2.ONE * FRAMED_FRUIT_SCALE, 0.0,
				Vector2(0.0, 0.04 if style == Style.SHIELD else 0.0))
		canvas.draw_set_transform_matrix(fruit_xform)
	_draw_fruit(canvas, fruit, colors)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


# [BODY, DETAIL, ACCENT, MARK, ring, field].
static func _palette(fruit: String, style: int, preset: Dictionary, kit: Dictionary) -> Array:
	var primary: Color = preset.primary
	var secondary: Color = preset.secondary
	var light: Color = preset.light
	match style:
		Style.FLAT:
			var ink: Color = kit.text.color
			var cut: Color = kit.jersey.base
			return [ink, cut, ink, cut, ink, cut]
		Style.ROUNDEL, Style.SHIELD:
			return [light, primary, secondary, primary, secondary, primary]
	var natural: Array = _NATURAL.get(fruit, _NATURAL.cherry)
	if style == Style.OUTLINED:
		# The keyline is the light, which the away jersey is based on: it rims
		# the fruit on the home sweater and vanishes into the away one.
		return [natural[BODY], natural[DETAIL], natural[ACCENT], natural[MARK], light, light]
	if style == Style.OUTLINED_DARK:
		# The team's darker color: it rims the fruit on the away sweater, and on
		# the home one too unless the home sweater is that color.
		var dark: Color = (primary if primary.get_luminance() < secondary.get_luminance()
				else secondary)
		return [natural[BODY], natural[DETAIL], natural[ACCENT], natural[MARK], dark, dark]
	# The ring is the secondary, which neither jersey is based on, so the badge
	# stands off both kits; the field is whichever base the fruit reads on.
	var body: Color = natural[BODY]
	var field: Color = primary if _contrast(primary, body) > _contrast(light, body) else light
	return [body, natural[DETAIL], natural[ACCENT], natural[MARK], secondary, field]


static func _contrast(a: Color, b: Color) -> float:
	return absf(a.get_luminance() - b.get_luminance())


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
		_: _circle(c,Vector2.ZERO, 0.9, k[BODY])


# ── Fruits ───────────────────────────────────────────────────────────────────


static func _blackberry(c: CanvasItem, k: Array) -> void:
	_leaf(c, Vector2(0.0, -0.62), Vector2(-0.55, -0.98), 0.2, k[ACCENT])
	_leaf(c, Vector2(0.0, -0.62), Vector2(0.55, -0.98), 0.2, k[ACCENT])
	_line(c,Vector2(0.0, -0.6), Vector2(0.05, -1.0), k[ACCENT], 0.09)
	# Drupelet rows down an egg, widest a little above the middle.
	# Packed tight enough to overlap, so it reads as one berry, not a bunch.
	_poly(c,_ellipse(Vector2(0.0, 0.08), Vector2(0.5, 0.68)), k[BODY])
	var rows: Array = [[-0.42, 3], [-0.17, 4], [0.08, 4], [0.33, 3], [0.56, 2]]
	for row: Array in rows:
		var y: float = row[0]
		var n: int = row[1]
		for i: int in n:
			var x: float = (float(i) - float(n - 1) * 0.5) * 0.27
			_circle(c,Vector2(x, y), 0.17, k[DETAIL])
			_circle(c,Vector2(x, y), 0.145, k[BODY])
			_circle(c,Vector2(x - 0.045, y - 0.045), 0.04, k[DETAIL])


static func _blueberry(c: CanvasItem, k: Array) -> void:
	_leaf(c, Vector2(0.25, -0.6), Vector2(0.9, -0.95), 0.22, k[ACCENT])
	_circle(c,Vector2(0.0, 0.1), 0.82, k[BODY])
	_poly(c,_star(Vector2(0.0, -0.36), 0.3, 0.12, 5), k[MARK])
	_circle(c,Vector2(0.0, -0.36), 0.07, k[BODY])
	_arc(c,Vector2(0.0, 0.1), 0.62, PI * 0.95, PI * 1.25, 12, k[DETAIL], 0.08)


static func _cherry(c: CanvasItem, k: Array) -> void:
	var apex := Vector2(0.15, -0.78)
	_curve(c, Vector2(-0.45, 0.1), Vector2(-0.3, -0.45), apex, 0.08, k[ACCENT])
	_curve(c, Vector2(0.45, 0.16), Vector2(0.35, -0.35), apex, 0.08, k[ACCENT])
	_leaf(c, apex, Vector2(0.8, -0.82), 0.22, k[ACCENT])
	for cherry: Vector3 in [Vector3(-0.45, 0.45, 0.42), Vector3(0.45, 0.5, 0.4)]:
		var at := Vector2(cherry.x, cherry.y)
		_circle(c,at, cherry.z, k[BODY])
		_circle(c,at + Vector2(-0.14, -0.14), 0.08, k[DETAIL])


static func _coconut(c: CanvasItem, k: Array) -> void:
	# A half shell, cut face tipped toward the viewer: the shell's lower half,
	# the flesh rim, and the hollow inside it.
	var tilt := Transform2D(-0.3, Vector2(0.0, 0.0))
	var bowl := PackedVector2Array()
	for i: int in 25:
		var t: float = PI * float(i) / 24.0
		bowl.append(tilt * Vector2(cos(t) * 0.9, sin(t) * 0.8))
	_poly(c,bowl, k[BODY])
	var rim := PackedVector2Array()
	var hollow := PackedVector2Array()
	for p: Vector2 in _ellipse(Vector2.ZERO, Vector2(0.9, 0.48)):
		rim.append(tilt * p)
	for p: Vector2 in _ellipse(Vector2(0.0, 0.02), Vector2(0.7, 0.33)):
		hollow.append(tilt * p)
	_poly(c,rim, k[DETAIL])
	_poly(c,hollow, k[ACCENT])


static func _dragonfruit(c: CanvasItem, k: Array) -> void:
	var body := _ellipse(Vector2(0.0, 0.12), Vector2(0.6, 0.82))
	_poly(c,body, k[BODY])
	# Bracts: flaps rooted on the skin, tips flaring up and out past it.
	var bracts: Array = [
		[Vector2(0.0, -0.55), Vector2(0.0, -1.0)],
		[Vector2(-0.12, -0.5), Vector2(-0.42, -0.95)],
		[Vector2(0.12, -0.5), Vector2(0.42, -0.95)],
		[Vector2(-0.35, -0.12), Vector2(-0.82, -0.42)],
		[Vector2(0.35, -0.12), Vector2(0.82, -0.42)],
		[Vector2(-0.4, 0.3), Vector2(-0.88, 0.08)],
		[Vector2(0.4, 0.3), Vector2(0.88, 0.08)],
		[Vector2(0.0, 0.2), Vector2(0.0, -0.25)],
	]
	for b: Array in bracts:
		_leaf(c, b[0], b[1], 0.2, k[DETAIL])
		_leaf(c, b[0], b[1], 0.13, k[ACCENT])


static func _lemon(c: CanvasItem, k: Array) -> void:
	var tilt := Transform2D(-0.35, Vector2(0.0, 0.08))
	_leaf(c, Vector2(0.5, -0.38), Vector2(0.95, -0.92), 0.2, k[ACCENT])
	var pts := PackedVector2Array()
	for i: int in 48:
		var t: float = TAU * float(i) / 48.0
		# A nub at each end of the long axis.
		var tip: float = 0.18 * pow(absf(cos(t)), 12.0)
		pts.append(tilt * Vector2(cos(t) * (0.82 + tip), sin(t) * 0.6))
	_poly(c,pts, k[BODY])
	_arc(c,tilt * Vector2(0.0, 0.0), 0.42, PI * 1.1, PI * 1.45, 10, k[DETAIL], 0.08)


static func _lime(c: CanvasItem, k: Array) -> void:
	_circle(c,Vector2.ZERO, 0.95, k[ACCENT])
	_circle(c,Vector2.ZERO, 0.82, k[DETAIL])
	var segments: int = 8
	for i: int in segments:
		var a0: float = TAU * float(i) / segments + 0.07
		var a1: float = TAU * float(i + 1) / segments - 0.07
		var mid: float = (a0 + a1) * 0.5
		var wedge := PackedVector2Array([Vector2.from_angle(mid) * 0.1])
		for j: int in 7:
			wedge.append(Vector2.from_angle(lerpf(a0, a1, float(j) / 6.0)) * 0.72)
		_poly(c,wedge, k[BODY])


static func _peach(c: CanvasItem, k: Array) -> void:
	_line(c,Vector2(0.0, -0.62), Vector2(0.05, -0.9), k[ACCENT], 0.09)
	_leaf(c, Vector2(0.05, -0.85), Vector2(0.75, -0.95), 0.22, k[ACCENT])
	_leaf(c, Vector2(0.05, -0.85), Vector2(-0.55, -1.0), 0.16, k[ACCENT])
	_circle(c,Vector2(-0.17, 0.12), 0.76, k[BODY])
	_circle(c,Vector2(0.17, 0.12), 0.76, k[BODY])
	_curve(c, Vector2(0.0, -0.58), Vector2(-0.32, 0.05), Vector2(-0.1, 0.72), 0.07, k[DETAIL])


static func _pineapple(c: CanvasItem, k: Array) -> void:
	for spike: Vector3 in [Vector3(0.0, -1.02, 0.15), Vector3(-0.3, -0.95, 0.13),
			Vector3(0.3, -0.95, 0.13), Vector3(-0.55, -0.72, 0.12), Vector3(0.55, -0.72, 0.12)]:
		_leaf(c, Vector2(0.0, -0.3), Vector2(spike.x, spike.y), spike.z, k[ACCENT])
	var center := Vector2(0.0, 0.32)
	var radii := Vector2(0.55, 0.66)
	_poly(c,_ellipse(center, radii), k[BODY])
	# Diamond lattice, each line clipped to the body.
	for slope: float in [1.0, -1.0]:
		for i: int in range(-5, 6):
			var p := center + Vector2(float(i) * 0.24, 0.0)
			var d := Vector2(slope, 1.0).normalized()
			var span: Vector2 = _clip_to_ellipse(p - center, d, radii * 0.94)
			if span.y > span.x:
				_line(c,p + d * span.x, p + d * span.y, k[DETAIL], 0.05)


static func _plum(c: CanvasItem, k: Array) -> void:
	var tilt := Transform2D(0.25, Vector2(0.0, 0.12))
	_line(c,Vector2(0.15, -0.62), Vector2(0.3, -0.98), k[ACCENT], 0.1)
	var body := PackedVector2Array()
	for p: Vector2 in _ellipse(Vector2.ZERO, Vector2(0.66, 0.8)):
		body.append(tilt * p)
	_poly(c,body, k[BODY])
	_curve(c, tilt * Vector2(0.0, -0.72), tilt * Vector2(0.3, 0.0),
			tilt * Vector2(0.08, 0.7), 0.06, k[DETAIL])
	_poly(c,_ellipse(tilt * Vector2(-0.32, -0.28), Vector2(0.09, 0.2)), k[DETAIL])


static func _pomegranate(c: CanvasItem, k: Array) -> void:
	var crown := PackedVector2Array([
		Vector2(-0.3, -0.5), Vector2(-0.38, -0.98), Vector2(-0.18, -0.78),
		Vector2(0.0, -1.02), Vector2(0.18, -0.78), Vector2(0.38, -0.98), Vector2(0.3, -0.5)])
	_poly(c,crown, k[ACCENT])
	_polyline(c,crown, k[DETAIL], 0.05)
	_circle(c,Vector2(0.0, 0.18), 0.8, k[BODY])
	_arc(c,Vector2(0.0, 0.18), 0.6, PI * 1.05, PI * 1.35, 12, k[DETAIL], 0.08)


static func _watermelon(c: CanvasItem, k: Array) -> void:
	var top: float = -0.38
	_poly(c,_half_disc(Vector2(0.0, top), 1.0), k[ACCENT])
	_poly(c,_half_disc(Vector2(0.0, top), 0.9), k[DETAIL])
	_poly(c,_half_disc(Vector2(0.0, top), 0.8), k[BODY])
	for seed: Vector2 in [Vector2(-0.45, 0.0), Vector2(0.0, 0.08), Vector2(0.45, 0.0),
			Vector2(-0.22, 0.3), Vector2(0.22, 0.3)]:
		_poly(c,_ellipse(Vector2(seed.x, top + 0.18 + seed.y),
				Vector2(0.06, 0.1)), k[MARK])


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


static func _arc(c: CanvasItem, center: Vector2, r: float, from: float, to: float, points: int,
		color: Color, width: float) -> void:
	c.draw_arc(center, r, from, to, points, _grow_color if _grow > 0.0 else color,
			width + 2.0 * _grow)


# ── Shapes ───────────────────────────────────────────────────────────────────


static func _ellipse(center: Vector2, radii: Vector2, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in n:
		var t: float = TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(t) * radii.x, sin(t) * radii.y))
	return pts


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
	_poly(c,pts, color)


# A quadratic stroke from `a` through control `ctrl` to `b`.
static func _curve(c: CanvasItem, a: Vector2, ctrl: Vector2, b: Vector2, width: float,
		color: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in 13:
		var t: float = float(i) / 12.0
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	_polyline(c,pts, color, width)


# A heater shield `scale` times the frame's size, pointed at the bottom.
static func _shield(c: CanvasItem, scale: float, color: Color) -> void:
	var pts := PackedVector2Array([Vector2(-0.85, -0.92), Vector2(0.85, -0.92)])
	for i: int in 13:
		var t: float = float(i) / 12.0
		pts.append(Vector2(0.85, 0.1).lerp(Vector2(0.85, 0.55), t).lerp(
				Vector2(0.85, 0.55).lerp(Vector2(0.0, 1.0), t), t))
	for i: int in range(11, -1, -1):
		var t: float = float(i) / 12.0
		pts.append(Vector2(-0.85, 0.1).lerp(Vector2(-0.85, 0.55), t).lerp(
				Vector2(-0.85, 0.55).lerp(Vector2(0.0, 1.0), t), t))
	for i: int in pts.size():
		pts[i] *= scale
	_poly(c,pts, color)


# The [enter, exit] distances along `dir` from `origin` (relative to the ellipse
# centre) inside an axis-aligned ellipse; enter > exit when the line misses.
static func _clip_to_ellipse(origin: Vector2, dir: Vector2, radii: Vector2) -> Vector2:
	var o := Vector2(origin.x / radii.x, origin.y / radii.y)
	var d := Vector2(dir.x / radii.x, dir.y / radii.y)
	var a: float = d.dot(d)
	var b: float = 2.0 * o.dot(d)
	var disc: float = b * b - 4.0 * a * (o.dot(o) - 1.0)
	if disc <= 0.0:
		return Vector2(1.0, 0.0)
	var root: float = sqrt(disc)
	return Vector2((-b - root) / (2.0 * a), (-b + root) / (2.0 * a))
