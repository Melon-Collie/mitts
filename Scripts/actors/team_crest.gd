class_name TeamCrest
extends RefCounted

# A team's chest crest: its fruit (CrestFruits) in the team's own colors, rimmed
# by two keylines — the team's dark against the fruit, its light outside that.
# The dark edges it on the light away sweater, the light on the dark home one.

# Each keyline's width in the drawing's unit space (about 6 mm on a 28 cm crest).
const KEYLINE_WIDTH: float = 0.045
# A part keeps a color an earlier part already took unless an untaken team color
# is within this much of as close (OKLab distance): two parts snapping to one
# color merge, which is better than a far-off color that no longer reads.
const REUSE_MARGIN: float = 0.1


# The team's fruit — its name, when CrestFruits draws one — or "" for no crest.
static func fruit_for(preset: Dictionary) -> String:
	var fruit: String = String(preset.get("name", "")).to_lower()
	return fruit if CrestFruits.has(fruit) else ""


# The crest for `fruit`, centred on `xform`'s origin with the unit circle mapped
# through it, colored from `preset`.
static func draw(canvas: CanvasItem, fruit: String, xform: Transform2D,
		preset: Dictionary) -> void:
	var colors: Array = team_colors(fruit, preset)
	canvas.draw_set_transform_matrix(xform)
	CrestFruits.draw(canvas, fruit, colors, KEYLINE_WIDTH * 2.0, preset.light)
	CrestFruits.draw(canvas, fruit, colors, KEYLINE_WIDTH, dark_color(preset))
	CrestFruits.draw(canvas, fruit, colors)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


# The darker of the team's primary and secondary.
static func dark_color(preset: Dictionary) -> Color:
	var primary: Color = preset.primary
	var secondary: Color = preset.secondary
	return primary if primary.get_luminance() < secondary.get_luminance() else secondary


# `fruit`'s parts, each snapped to the nearest color anywhere in the team's
# palette or kits, but for a green CrestFruits keeps. A color the drawing asks
# for twice snaps once.
static func team_colors(fruit: String, preset: Dictionary) -> Array:
	var pool: Array[Color] = []
	_collect_colors(preset, pool)
	var wanted: Array = CrestFruits.wanted_colors(fruit)
	var out: Array = []
	for i: int in wanted.size():
		var want: Color = wanted[i]
		var earlier: int = wanted.find(want)
		if earlier < i:
			out.append(out[earlier])
			continue
		if CrestFruits.keeps(want):
			out.append(want)
			continue
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
