class_name CrestFruits
extends RefCounted

# The fruit drawings TeamCrest puts on a chest. Each is drawn in a unit space —
# y down, the fruit inside the unit circle — through the caller's transform. A
# drawing is keyed by id: a fruit's name, or "<fruit>:<variant>" where its
# design is still being chosen. Its colors are the real fruit's, listed in the
# order they claim a team color (TeamCrest snaps them), and read here by index.

const VARIANT_NAMES: PackedStringArray = ["whole", "current", "new"]

# Dragonfruit's bracts keep this green unsnapped: no team carries a green, and
# in the skin's pink they read as petals.
const DRAGONFRUIT_GREEN: Color = Color("#7BBF3A")

const _LEAF: Color = Color("#3E7D3A")

const _COLORS: Dictionary = {
	"coconut": [Color("#6B4226"), Color("#F5F0E1"), Color("#5A3A22")],
	"lime": [Color("#3F7F1F"), Color("#EAF5C8"), Color("#A6D84A")],
	"watermelon": [Color("#2F7D3A"), Color("#EEF6DA"), Color("#E8485C"), Color("#1A1A1A")],

	"blackberry:whole": [Color("#2A1735"), Color("#7A5A9A"), _LEAF],
	"blackberry:current": [Color("#2A1735"), Color("#7A4A8A"), _LEAF],
	"blackberry:new": [Color("#2A1735"), Color("#7A4A8A"), _LEAF],
	"blueberry:whole": [Color("#3B5BA8"), Color("#9DB4E8"), _LEAF, Color("#22355F")],
	"blueberry:current": [Color("#3B5BA8"), Color("#22355F")],
	"blueberry:new": [Color("#3B5BA8"), Color("#22355F"), _LEAF],
	"cherry:whole": [Color("#C8102E"), Color("#F27C8A"), _LEAF],
	"cherry:current": [Color("#C8102E"), _LEAF],
	"cherry:new": [Color("#C8102E"), _LEAF, Color("#F27C8A")],
	"dragonfruit:whole": [Color("#E0306F"), Color("#FFC2D6"), DRAGONFRUIT_GREEN],
	"dragonfruit:current": [Color("#E0306F"), Color("#FFFFFF"), Color("#1A1A1A"),
			DRAGONFRUIT_GREEN],
	"dragonfruit:new": [Color("#E0306F"), DRAGONFRUIT_GREEN],
	"lemon:whole": [Color("#F7D52A"), Color("#FFF3A6"), _LEAF],
	"lemon:current": [Color("#F7D52A"), Color("#FFF8D6"), Color("#F9E36A")],
	"lemon:new": [Color("#F7D52A"), Color("#FFF8D6"), Color("#F9E36A"), _LEAF],
	"peach:whole": [Color("#F4A06B"), Color("#D9643F"), _LEAF],
	"peach:current": [Color("#E8734A"), Color("#F7B550"), Color("#8A3B2A"), _LEAF],
	"peach:new": [Color("#E8734A"), Color("#F7B550"), Color("#8A3B2A"), _LEAF],
	"pineapple:whole": [Color("#F2B233"), Color("#9C6418"), Color("#3E8E4A")],
	"pineapple:current": [Color("#F7C531"), Color("#3E8E4A"), Color("#B5781E"), Color("#FBE9A0")],
	"pineapple:new": [Color("#F2B233"), Color("#3E8E4A"), Color("#9C6418")],
	"plum:whole": [Color("#5B2A6E"), Color("#A57BBE"), Color("#6B4A2A")],
	"plum:current": [Color("#5B2A6E"), Color("#F2C14E"), Color("#9C5A2E"), Color("#6B4A2A")],
	"plum:new": [Color("#5B2A6E"), Color("#A57BBE"), Color("#6B4A2A"), _LEAF],
	"pomegranate:whole": [Color("#B3202F"), Color("#F07C8C")],
	"pomegranate:current": [Color("#9E1B2C"), Color("#F3E3CF"), Color("#E0405A")],
	"pomegranate:new": [Color("#9E1B2C"), Color("#F3E3CF"), Color("#E0405A")],
}

# While > 0, every shape is drawn grown by this much in `_grow_color` — a
# silhouette pass, which TeamCrest stacks under the fruit as its keylines.
static var _grow: float = 0.0
static var _grow_color: Color = Color.WHITE


static func has(id: String) -> bool:
	return _COLORS.has(id)


# The drawing for `fruit` in `variant`, or its only drawing when it has one.
static func resolve(fruit: String, variant: String) -> String:
	var id: String = "%s:%s" % [fruit, variant]
	if has(id):
		return id
	return fruit if has(fruit) else "%s:current" % fruit


# The real colors of drawing `id`'s parts, in claiming order.
static func wanted_colors(id: String) -> Array:
	return _COLORS.get(id, _COLORS["cherry:current"])


# Draws `id` with `k` (its parts' colors, as wanted_colors orders them); with
# `grow` > 0, draws only its silhouette grown by that much, in `grow_color`.
static func draw(c: CanvasItem, id: String, k: Array, grow: float = 0.0,
		grow_color: Color = Color.WHITE) -> void:
	_grow = grow
	_grow_color = grow_color
	match id:
		"coconut": _coconut(c, k)
		"lime": _lime(c, k)
		"watermelon": _watermelon(c, k)
		"blackberry:whole": _blackberry_whole(c, k)
		"blackberry:current": _blackberry_current(c, k)
		"blackberry:new": _blackberry_new(c, k)
		"blueberry:whole": _blueberry_whole(c, k)
		"blueberry:current": _blueberry_current(c, k)
		"blueberry:new": _blueberry_new(c, k)
		"cherry:whole": _cherry_whole(c, k)
		"cherry:current": _cherry_current(c, k)
		"cherry:new": _cherry_new(c, k)
		"dragonfruit:whole": _dragonfruit_whole(c, k)
		"dragonfruit:current": _dragonfruit_current(c, k)
		"dragonfruit:new": _dragonfruit_new(c, k)
		"lemon:whole": _lemon_whole(c, k)
		"lemon:current": _lemon_current(c, k)
		"lemon:new": _lemon_new(c, k)
		"peach:whole": _peach_whole(c, k)
		"peach:current": _peach_current(c, k)
		"peach:new": _peach_new(c, k)
		"pineapple:whole": _pineapple_whole(c, k)
		"pineapple:current": _pineapple_current(c, k)
		"pineapple:new": _pineapple_new(c, k)
		"plum:whole": _plum_whole(c, k)
		"plum:current": _plum_current(c, k)
		"plum:new": _plum_new(c, k)
		"pomegranate:whole": _pomegranate_whole(c, k)
		"pomegranate:current": _pomegranate_current(c, k)
		"pomegranate:new": _pomegranate_new(c, k)
		_: _circle(c, Vector2.ZERO, 0.9, k[0])
	_grow = 0.0


# ── Settled ──────────────────────────────────────────────────────────────────


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


static func _lime(c: CanvasItem, k: Array) -> void:
	_circle(c, Vector2.ZERO, 0.95, k[0])
	_circle(c, Vector2.ZERO, 0.82, k[1])
	_wheel(c, Transform2D(0.0, Vector2.ONE * 0.72, 0.0, Vector2.ZERO), k[2])


static func _watermelon(c: CanvasItem, k: Array) -> void:
	var top: float = -0.38
	_poly(c, _half_disc(Vector2(0.0, top), 1.0), k[0])
	_poly(c, _half_disc(Vector2(0.0, top), 0.9), k[1])
	_poly(c, _half_disc(Vector2(0.0, top), 0.8), k[2])
	for at: Vector2 in [Vector2(-0.45, 0.0), Vector2(0.0, 0.08), Vector2(0.45, 0.0),
			Vector2(-0.22, 0.3), Vector2(0.22, 0.3)]:
		_poly(c, _ellipse(Vector2(at.x, top + 0.18 + at.y), Vector2(0.06, 0.1)), k[3])


# ── Whole: the first drawings ────────────────────────────────────────────────


static func _blackberry_whole(c: CanvasItem, k: Array) -> void:
	_leaf(c, Vector2(0.0, -0.62), Vector2(-0.55, -0.98), 0.2, k[2])
	_leaf(c, Vector2(0.0, -0.62), Vector2(0.55, -0.98), 0.2, k[2])
	_line(c, Vector2(0.0, -0.6), Vector2(0.05, -1.0), k[2], 0.09)
	_poly(c, _ellipse(Vector2(0.0, 0.08), Vector2(0.5, 0.68)), k[0])
	for row: Vector2 in [Vector2(-0.42, 3), Vector2(-0.17, 4), Vector2(0.08, 4),
			Vector2(0.33, 3), Vector2(0.56, 2)]:
		for i: int in int(row.y):
			var at := Vector2((float(i) - (row.y - 1.0) * 0.5) * 0.27, row.x)
			_circle(c, at, 0.17, k[1])
			_circle(c, at, 0.145, k[0])
			_circle(c, at - Vector2(0.045, 0.045), 0.04, k[1])


static func _blueberry_whole(c: CanvasItem, k: Array) -> void:
	_leaf(c, Vector2(0.25, -0.6), Vector2(0.9, -0.95), 0.22, k[2])
	_circle(c, Vector2(0.0, 0.1), 0.82, k[0])
	_poly(c, _star(Vector2(0.0, -0.36), 0.3, 0.12, 5), k[3])
	_circle(c, Vector2(0.0, -0.36), 0.07, k[0])
	_arc(c, Vector2(0.0, 0.1), 0.62, PI * 0.95, PI * 1.25, k[1], 0.08)


static func _cherry_whole(c: CanvasItem, k: Array) -> void:
	var apex := Vector2(0.15, -0.78)
	_curve(c, Vector2(-0.45, 0.1), Vector2(-0.3, -0.45), apex, 0.08, k[2])
	_curve(c, Vector2(0.45, 0.16), Vector2(0.35, -0.35), apex, 0.08, k[2])
	_leaf(c, apex, Vector2(0.8, -0.82), 0.22, k[2])
	for cherry: Vector3 in [Vector3(-0.45, 0.45, 0.42), Vector3(0.45, 0.5, 0.4)]:
		var at := Vector2(cherry.x, cherry.y)
		_circle(c, at, cherry.z, k[0])
		_circle(c, at + Vector2(-0.14, -0.14), 0.08, k[1])


static func _dragonfruit_whole(c: CanvasItem, k: Array) -> void:
	_poly(c, _ellipse(Vector2(0.0, 0.12), Vector2(0.6, 0.82)), k[0])
	# Bracts: flaps rooted on the skin, tips flaring up and out past it.
	for b: Array in [
			[Vector2(0.0, -0.55), Vector2(0.0, -1.0)],
			[Vector2(-0.12, -0.5), Vector2(-0.42, -0.95)],
			[Vector2(0.12, -0.5), Vector2(0.42, -0.95)],
			[Vector2(-0.35, -0.12), Vector2(-0.82, -0.42)],
			[Vector2(0.35, -0.12), Vector2(0.82, -0.42)],
			[Vector2(-0.4, 0.3), Vector2(-0.88, 0.08)],
			[Vector2(0.4, 0.3), Vector2(0.88, 0.08)],
			[Vector2(0.0, 0.2), Vector2(0.0, -0.25)]]:
		_leaf(c, b[0], b[1], 0.2, k[1])
		_leaf(c, b[0], b[1], 0.13, k[2])


static func _lemon_whole(c: CanvasItem, k: Array) -> void:
	var tilt := Transform2D(-0.35, Vector2(0.0, 0.08))
	_leaf(c, Vector2(0.5, -0.38), Vector2(0.95, -0.92), 0.2, k[2])
	_poly(c, _transformed(tilt, _lemon_outline()), k[0])
	_arc(c, tilt.origin, 0.42, PI * 1.1, PI * 1.45, k[1], 0.08)


static func _peach_whole(c: CanvasItem, k: Array) -> void:
	_line(c, Vector2(0.0, -0.62), Vector2(0.05, -0.9), k[2], 0.09)
	_leaf(c, Vector2(0.05, -0.85), Vector2(0.75, -0.95), 0.22, k[2])
	_leaf(c, Vector2(0.05, -0.85), Vector2(-0.55, -1.0), 0.16, k[2])
	_circle(c, Vector2(-0.17, 0.12), 0.76, k[0])
	_circle(c, Vector2(0.17, 0.12), 0.76, k[0])
	_curve(c, Vector2(0.0, -0.58), Vector2(-0.32, 0.05), Vector2(-0.1, 0.72), 0.07, k[1])


static func _pineapple_whole(c: CanvasItem, k: Array) -> void:
	for spike: Vector3 in [Vector3(0.0, -1.02, 0.15), Vector3(-0.3, -0.95, 0.13),
			Vector3(0.3, -0.95, 0.13), Vector3(-0.55, -0.72, 0.12), Vector3(0.55, -0.72, 0.12)]:
		_leaf(c, Vector2(0.0, -0.3), Vector2(spike.x, spike.y), spike.z, k[2])
	var center := Vector2(0.0, 0.32)
	var radii := Vector2(0.55, 0.66)
	_poly(c, _ellipse(center, radii), k[0])
	# Diamond lattice, each line clipped to the body.
	for slope: float in [1.0, -1.0]:
		for i: int in range(-5, 6):
			var p := center + Vector2(float(i) * 0.24, 0.0)
			var d := Vector2(slope, 1.0).normalized()
			var span: Vector2 = _clip_to_ellipse(p - center, d, radii * 0.94)
			if span.y > span.x:
				_line(c, p + d * span.x, p + d * span.y, k[1], 0.05)


static func _plum_whole(c: CanvasItem, k: Array) -> void:
	var tilt := Transform2D(0.25, Vector2(0.0, 0.12))
	_line(c, Vector2(0.15, -0.62), Vector2(0.3, -0.98), k[2], 0.1)
	_poly(c, _transformed(tilt, _ellipse(Vector2.ZERO, Vector2(0.66, 0.8))), k[0])
	_curve(c, tilt * Vector2(0.0, -0.72), tilt * Vector2(0.3, 0.0),
			tilt * Vector2(0.08, 0.7), 0.06, k[1])
	_poly(c, _ellipse(tilt * Vector2(-0.32, -0.28), Vector2(0.09, 0.2)), k[1])


static func _pomegranate_whole(c: CanvasItem, k: Array) -> void:
	var crown: PackedVector2Array = _pomegranate_crown()
	_poly(c, crown, k[0])
	_polyline(c, crown, k[1], 0.05)
	_circle(c, Vector2(0.0, 0.18), 0.8, k[0])
	_arc(c, Vector2(0.0, 0.18), 0.6, PI * 1.05, PI * 1.35, k[1], 0.08)


# ── Current: cut views and the bold berries ──────────────────────────────────


static func _blackberry_current(c: CanvasItem, k: Array) -> void:
	_leaf(c, Vector2(0.0, -0.62), Vector2(-0.55, -0.98), 0.22, k[2])
	_leaf(c, Vector2(0.0, -0.62), Vector2(0.55, -0.98), 0.22, k[2])
	_drupelets(c, Vector2.ZERO, 1.0, k[0], k[1])


static func _blueberry_current(c: CanvasItem, k: Array) -> void:
	_circle(c, Vector2(0.0, 0.08), 0.88, k[0])
	_poly(c, _star(Vector2(0.0, -0.36), 0.36, 0.15, 5), k[1])
	_circle(c, Vector2(0.0, -0.36), 0.08, k[0])


static func _cherry_current(c: CanvasItem, k: Array) -> void:
	var apex := Vector2(0.15, -0.8)
	_curve(c, Vector2(-0.45, 0.1), Vector2(-0.3, -0.45), apex, 0.1, k[1])
	_curve(c, Vector2(0.45, 0.16), Vector2(0.35, -0.35), apex, 0.1, k[1])
	_leaf(c, apex, Vector2(0.82, -0.85), 0.26, k[1])
	_circle(c, Vector2(-0.45, 0.45), 0.45, k[0])
	_circle(c, Vector2(0.45, 0.5), 0.43, k[0])


static func _dragonfruit_current(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var flesh: Color = k[1]
	var seed: Color = k[2]
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
		_poly(c, _ellipse(at, Vector2(0.04, 0.06), 10), seed)


static func _lemon_current(c: CanvasItem, k: Array) -> void:
	var peel: Color = k[0]
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
	_poly(c, _transformed(tilt, _ellipse(face, Vector2(0.27, 0.52))), k[1])
	_wheel(c, tilt * Transform2D(Vector2(0.24, 0.0), Vector2(0.0, 0.47), face), k[2])


static func _peach_current(c: CanvasItem, k: Array) -> void:
	_line(c, Vector2(0.0, -0.55), Vector2(0.06, -0.88), k[3], 0.1)
	_leaf(c, Vector2(0.05, -0.82), Vector2(0.7, -0.98), 0.26, k[3])
	_peach_half(c, Vector2(0.0, 0.12), 1.0, k)


static func _pineapple_current(c: CanvasItem, k: Array) -> void:
	for spike: Vector3 in [Vector3(0.0, -1.02, 0.17), Vector3(-0.32, -0.95, 0.15),
			Vector3(0.32, -0.95, 0.15), Vector3(-0.58, -0.7, 0.14), Vector3(0.58, -0.7, 0.14)]:
		_leaf(c, Vector2(0.0, -0.3), Vector2(spike.x, spike.y), spike.z, k[1])
	# Halved lengthwise: the rind as a band, the flesh, the core down the middle.
	var center := Vector2(0.0, 0.3)
	_poly(c, _ellipse(center, Vector2(0.56, 0.68)), k[2])
	_poly(c, _ellipse(center, Vector2(0.46, 0.58)), k[0])
	_poly(c, _ellipse(center + Vector2(0.0, -0.02), Vector2(0.11, 0.46)), k[3])


static func _plum_current(c: CanvasItem, k: Array) -> void:
	var tilt := Transform2D(0.2, Vector2(0.0, 0.1))
	_line(c, tilt * Vector2(0.0, -0.7), tilt * Vector2(0.12, -1.02), k[3], 0.1)
	_poly(c, _transformed(tilt, _ellipse(Vector2.ZERO, Vector2(0.64, 0.8))), k[0])
	_poly(c, _transformed(tilt, _ellipse(Vector2.ZERO, Vector2(0.54, 0.7))), k[1])
	_leaf(c, tilt * Vector2(0.0, -0.36), tilt * Vector2(0.0, 0.38), 0.36, k[2])


static func _pomegranate_current(c: CanvasItem, k: Array) -> void:
	_poly(c, _pomegranate_crown(), k[0])
	# Halved across: rind, pith, and the seeds packed inside it.
	var center := Vector2(0.0, 0.16)
	_circle(c, center, 0.82, k[0])
	_circle(c, center, 0.71, k[1])
	for row: int in range(-2, 3):
		var y: float = float(row) * 0.235
		var shift: float = 0.135 if row % 2 != 0 else 0.0
		for col: int in range(-3, 4):
			var at := Vector2(float(col) * 0.27 + shift, y)
			if at.length() < 0.56:
				_circle(c, center + at, 0.12, k[2])


# ── New ──────────────────────────────────────────────────────────────────────


# Two berries on a bramble leaf.
static func _blackberry_new(c: CanvasItem, k: Array) -> void:
	_leaf(c, Vector2(-0.1, 0.2), Vector2(0.75, -0.85), 0.75, k[2])
	_line(c, Vector2(-0.1, 0.2), Vector2(0.6, -0.68), k[0], 0.04)
	_drupelets(c, Vector2(-0.32, -0.12), 0.68, k[0], k[1])
	_drupelets(c, Vector2(0.3, 0.3), 0.62, k[0], k[1])


# A cluster of three, each rimmed in the calyx color so they read apart.
static func _blueberry_new(c: CanvasItem, k: Array) -> void:
	var skin: Color = k[0]
	var calyx: Color = k[1]
	_leaf(c, Vector2(0.15, -0.55), Vector2(0.92, -0.9), 0.32, k[2])
	for berry: Vector3 in [Vector3(0.05, -0.25, 0.48), Vector3(-0.4, 0.3, 0.5),
			Vector3(0.4, 0.34, 0.47)]:
		var at := Vector2(berry.x, berry.y)
		_circle(c, at, berry.z + 0.04, calyx)
		_circle(c, at, berry.z, skin)
		_poly(c, _star(at + Vector2(0.0, -0.05), 0.2, 0.08, 5), calyx)


# One big cherry on a long stem.
static func _cherry_new(c: CanvasItem, k: Array) -> void:
	_curve(c, Vector2(-0.05, -0.2), Vector2(0.0, -0.7), Vector2(0.3, -0.98), 0.1, k[1])
	_leaf(c, Vector2(0.18, -0.82), Vector2(0.85, -0.6), 0.34, k[1])
	_circle(c, Vector2(-0.05, 0.32), 0.64, k[0])
	_poly(c, _ellipse(Vector2(-0.3, 0.08), Vector2(0.1, 0.17)), k[2])


# Whole, with the bracts as flames: skin-colored, green at the tips.
static func _dragonfruit_new(c: CanvasItem, k: Array) -> void:
	for b: Array in [
			[Vector2(0.0, -0.4), Vector2(0.0, -1.0)],
			[Vector2(-0.22, -0.38), Vector2(-0.6, -0.95)],
			[Vector2(0.22, -0.38), Vector2(0.6, -0.95)],
			[Vector2(-0.45, -0.05), Vector2(-0.88, -0.62)],
			[Vector2(0.45, -0.05), Vector2(0.88, -0.62)]]:
		var base: Vector2 = b[0]
		var tip: Vector2 = b[1]
		_leaf(c, base, tip, 0.32, k[0])
		_leaf(c, base.lerp(tip, 0.5), tip, 0.17, k[1])
	_poly(c, _ellipse(Vector2(0.0, 0.2), Vector2(0.55, 0.72)), k[0])


# A whole lemon with a slice in front of it.
static func _lemon_new(c: CanvasItem, k: Array) -> void:
	var whole := Transform2D(-0.4, Vector2.ONE * 0.72, 0.0, Vector2(0.2, -0.22))
	_leaf(c, whole * Vector2(0.55, -0.55), whole * Vector2(1.0, -1.15), 0.2, k[3])
	_poly(c, _transformed(whole, _lemon_outline()), k[0])
	var slice := Vector2(-0.38, 0.38)
	_circle(c, slice, 0.56, k[1])
	_circle(c, slice, 0.52, k[0])
	_circle(c, slice, 0.45, k[1])
	_wheel(c, Transform2D(0.0, Vector2.ONE * 0.39, 0.0, slice), k[2])


# A whole peach behind a half.
static func _peach_new(c: CanvasItem, k: Array) -> void:
	var whole := Vector2(0.28, -0.22)
	_line(c, whole + Vector2(0.0, -0.4), whole + Vector2(0.05, -0.65), k[3], 0.08)
	_leaf(c, whole + Vector2(0.04, -0.6), whole + Vector2(0.55, -0.75), 0.22, k[3])
	_circle(c, whole + Vector2(-0.11, 0.0), 0.5, k[0])
	_circle(c, whole + Vector2(0.11, 0.0), 0.5, k[0])
	_curve(c, whole + Vector2(0.0, -0.38), whole + Vector2(-0.2, 0.0),
			whole + Vector2(-0.06, 0.45), 0.05, k[2])
	var half := Vector2(-0.25, 0.3)
	for side: float in [-0.11, 0.11]:
		_circle(c, half + Vector2(side, 0.0), 0.55, k[2])
	_peach_half(c, half, 0.68, k)


# Whole, chunkier: a three-leaf crown and the eyes as diamonds.
static func _pineapple_new(c: CanvasItem, k: Array) -> void:
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


# Two plums, the front one seamed off from the back in the stem's dark.
static func _plum_new(c: CanvasItem, k: Array) -> void:
	var back := Transform2D(0.3, Vector2(0.3, -0.12))
	_line(c, back * Vector2(0.0, -0.55), back * Vector2(0.1, -0.88), k[2], 0.09)
	_leaf(c, back * Vector2(0.06, -0.8), back * Vector2(0.62, -0.92), 0.24, k[3])
	_poly(c, _transformed(back, _ellipse(Vector2.ZERO, Vector2(0.48, 0.58))), k[0])
	_poly(c, _ellipse(back * Vector2(-0.22, -0.22), Vector2(0.06, 0.13)), k[1])
	var front := Transform2D(-0.15, Vector2(-0.22, 0.3))
	_poly(c, _transformed(front, _ellipse(Vector2.ZERO, Vector2(0.57, 0.67))), k[2])
	_poly(c, _transformed(front, _ellipse(Vector2.ZERO, Vector2(0.53, 0.63))), k[0])
	_curve(c, front * Vector2(0.0, -0.58), front * Vector2(0.24, 0.0),
			front * Vector2(0.06, 0.56), 0.05, k[1])
	_poly(c, _ellipse(front * Vector2(-0.26, -0.24), Vector2(0.07, 0.15)), k[1])


# Whole, split open on one side to show the seeds.
static func _pomegranate_new(c: CanvasItem, k: Array) -> void:
	_poly(c, _pomegranate_crown(), k[0])
	var center := Vector2(0.0, 0.16)
	_circle(c, center, 0.82, k[0])
	var a0: float = -1.75
	var a1: float = 0.35
	var split := PackedVector2Array([center])
	for i: int in 17:
		split.append(center + Vector2.from_angle(lerpf(a0, a1, float(i) / 16.0)) * 0.74)
	_poly(c, split, k[1])
	for ring: Vector2 in [Vector2(0.24, 2), Vector2(0.43, 4), Vector2(0.62, 6)]:
		for i: int in int(ring.y):
			var a: float = lerpf(a0 + 0.22, a1 - 0.22, (float(i) + 0.5) / ring.y)
			_circle(c, center + Vector2.from_angle(a) * ring.x, 0.09, k[2])


# ── Parts shared between drawings ────────────────────────────────────────────


# A blackberry `s` times full size at `at`: the berry, its drupelets rimmed.
static func _drupelets(c: CanvasItem, at: Vector2, s: float, berry: Color, rim: Color) -> void:
	_poly(c, _ellipse(at + Vector2(0.0, 0.08) * s, Vector2(0.5, 0.66) * s), berry)
	for row: Vector2 in [Vector2(-0.38, 3), Vector2(-0.08, 4), Vector2(0.22, 3),
			Vector2(0.5, 2)]:
		for i: int in int(row.y):
			var p: Vector2 = at + Vector2((float(i) - (row.y - 1.0) * 0.5) * 0.3, row.x) * s
			_circle(c, p, 0.19 * s, rim)
			_circle(c, p, 0.15 * s, berry)


# A halved peach `s` times full size centred at `at`: skin, flesh, pit, crease.
# `k` is [skin, flesh, pit, leaf].
static func _peach_half(c: CanvasItem, at: Vector2, s: float, k: Array) -> void:
	for side: float in [-0.16, 0.16]:
		_circle(c, at + Vector2(side, 0.0) * s, 0.74 * s, k[0])
	for side: float in [-0.16, 0.16]:
		_circle(c, at + Vector2(side, 0.0) * s, 0.64 * s, k[1])
	_poly(c, _ellipse(at + Vector2(0.0, 0.04) * s, Vector2(0.27, 0.34) * s), k[2])
	_curve(c, at + Vector2(0.0, -0.24) * s, at + Vector2(-0.07, 0.04) * s,
			at + Vector2(0.0, 0.32) * s, 0.045 * s, k[1])


static func _pomegranate_crown() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.3, -0.5), Vector2(-0.4, -0.98), Vector2(-0.18, -0.78),
		Vector2(0.0, -1.02), Vector2(0.18, -0.78), Vector2(0.4, -0.98), Vector2(0.3, -0.5)])


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
