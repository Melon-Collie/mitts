class_name SleevePaint
extends RefCounted

# A kit's sleeve: one base color down the whole arm, and stripes laid along it
# from the shoulder (pos 0) to the glove's cuff (pos 1) — a shoulder or forearm
# of another color is a wide stripe. The skater paints it as one piece
# (SleeveDecal); the goalie paints his two arm segments, so `segment` cuts the
# sleeve at the elbow for him, and `from_legacy` reads a kit written in the
# older two-segment form (arms.upper / arms.lower and a shoulder color).

# The sleeve from the shoulder joint to the cuff, and the elbow along it, at the
# default build (Skater.upper_arm_length; the cuff sits ~0.13 m up the 0.33 m
# forearm from the fist).
const LENGTH_M: float = 0.53
const ELBOW_M: float = 0.33
# A shoulder of its own color covers the sleeve's top this far: past the number.
const SHOULDER_BAND_M: float = 0.15
# Where the number sits on the sleeve, its centre down from the shoulder.
const NUMBER_CENTER_M: float = 0.08
# The two-segment form: each segment 0.33 m, its stripes shrunk about its
# centre by the sock's length (0.30 m) over the segment's, so an authored width
# paints the same band height on an arm as on a sock.
const _SEGMENT_M: float = 0.33
const _SEGMENT_STRIPE_SCALE: float = 0.30 / 0.33
# A legacy forearm's stripes were laid round mid-forearm; real sleeves carry
# them at the elbow, so the group is brought up to centre this far below it.
const _ELBOW_GROUP_CENTER_M: float = 0.03


static func pos_of(metres: float) -> float:
	return metres / LENGTH_M


# The sleeve a two-segment kit describes: the upper arm's base, a band for a
# shoulder or a forearm of another color, then both segments' stripes where
# they physically sat, the forearm's group brought up to the elbow.
static func from_legacy(arms: Dictionary, shoulder_color: Color) -> Dictionary:
	var upper: Dictionary = arms.get("upper", {})
	var lower: Dictionary = arms.get("lower", {})
	var base: Color = upper.get("base", Color.WHITE)
	var stripes: Array[Dictionary] = []
	if not shoulder_color.is_equal_approx(base):
		stripes.append(_band(0.0, SHOULDER_BAND_M, shoulder_color))
	var lower_base: Color = lower.get("base", base)
	if not lower_base.is_equal_approx(base):
		stripes.append(_band(ELBOW_M, LENGTH_M + 0.05, lower_base))
	for s: Dictionary in upper.get("stripes", []):
		stripes.append(_from_segment(s, 0.0))
	var lower_stripes: Array = lower.get("stripes", [])
	if not lower_stripes.is_empty():
		var top: float = INF
		var bottom: float = -INF
		for s: Dictionary in lower_stripes:
			var placed: Dictionary = _from_segment(s, ELBOW_M)
			top = minf(top, placed.pos - placed.width * 0.5)
			bottom = maxf(bottom, placed.pos + placed.width * 0.5)
		var shift: float = pos_of(ELBOW_M + _ELBOW_GROUP_CENTER_M) - (top + bottom) * 0.5
		for s: Dictionary in lower_stripes:
			var placed: Dictionary = _from_segment(s, ELBOW_M)
			placed.pos += shift
			stripes.append(placed)
	return {"base": base, "stripes": stripes}


# One legacy segment's stripe on the sleeve, that segment starting `start_m`
# down it.
static func _from_segment(s: Dictionary, start_m: float) -> Dictionary:
	var centre_m: float = start_m \
			+ (0.5 + (float(s.pos) - 0.5) * _SEGMENT_STRIPE_SCALE) * _SEGMENT_M
	return {"pos": pos_of(centre_m),
			"width": float(s.width) * _SEGMENT_STRIPE_SCALE * _SEGMENT_M / LENGTH_M,
			"color": s.color}


static func _band(from_m: float, to_m: float, color: Color) -> Dictionary:
	return {"pos": pos_of((from_m + to_m) * 0.5), "width": (to_m - from_m) / LENGTH_M,
			"color": color}


# The upper arm's or the forearm's part of the sleeve in the legacy segment
# form, for the bodies that paint the two apart: its base the sleeve's color at
# the segment's middle, its stripes those that reach into it, clipped to it.
static func segment(sleeve: Dictionary, upper: bool) -> Dictionary:
	var from_m: float = 0.0 if upper else ELBOW_M
	var to_m: float = ELBOW_M if upper else ELBOW_M + _SEGMENT_M
	var stripes: Array[Dictionary] = []
	for s: Dictionary in sleeve.stripes:
		var top_m: float = maxf((float(s.pos) - float(s.width) * 0.5) * LENGTH_M, from_m)
		var bottom_m: float = minf((float(s.pos) + float(s.width) * 0.5) * LENGTH_M, to_m)
		if bottom_m <= top_m:
			continue
		var centre: float = ((top_m + bottom_m) * 0.5 - from_m) / _SEGMENT_M
		stripes.append({
			"pos": 0.5 + (centre - 0.5) / _SEGMENT_STRIPE_SCALE,
			"width": (bottom_m - top_m) / _SEGMENT_M / _SEGMENT_STRIPE_SCALE,
			"color": s.color,
		})
	return {"base": sleeve.base, "stripes": stripes}


# The color showing at `pos` down the sleeve: the last stripe over it, else the
# base.
static func color_at(sleeve: Dictionary, pos: float) -> Color:
	var c: Color = sleeve.base
	for s: Dictionary in sleeve.stripes:
		if absf(pos - float(s.pos)) <= float(s.width) * 0.5:
			c = s.color
	return c
