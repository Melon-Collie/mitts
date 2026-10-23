class_name CellyPoseRules
extends RefCounted

# Where each goal celebration (CellyRegistry) puts the hands, the stick and the
# body at a point in its window: `t` is the progress through it (0..1), `s` the
# seconds since it began, which clock the repeated motions (a pump, a shake).
#
# Hand offsets are authored in ARM LENGTHS from the shoulder the hand hangs
# from, x outward on that hand's side, y up, z back (forward is −Z), so every
# build and either hand strikes the same pose. A free hand's path never crosses
# the elbow's pole (Skater.arm_pole_local, down and ~29° out): where the
# shoulder-to-hand line lies along it the bend has no side, and the elbow
# flips, so a hand low at the side stays well inside that angle, and one that
# swings away from the body goes out in front of it. Nor does a hand pass close
# by its shoulder on the way to or from the shaft, where the folded arm's elbow
# has no stable bend: a hand held overhead is held a little forward. The stick
# is authored as a
# bearing from the top hand and laid one full stick length along it — a held
# pose poses the hand and derives the blade (Scripts/controllers/CLAUDE.md,
# "Pose the hand, not the blade") — and never below the ice.

# The archer's drawing hand at the cheek (arm lengths off the top shoulder, as
# authored below) and the arrow's bearing: forward, across toward the bow arm,
# and up into the stands.
const BOW_CHEEK := Vector3(-0.3, 0.2, 0.12)
const BOW_AIM := Vector3(-0.25, 0.3, -0.92)
# How far up the shaft from the drawn hand, metres, the archer's bow hand holds.
const BOW_GRIP_M: float = 0.6
# The draw's length, metres: how far ahead of the cheek the hand nocks.
const BOW_DRAW_M: float = 0.45
# The share of the shaft, from the top hand, the hot stick's free hand hovers
# over, and how high above it, metres.
const WARM_GRIP: float = 0.45
const WARM_HOVER_M: float = 0.16

# The beats each celly's arms and body share, as (start, end) of the window's
# progress: what the hand does across one, the legs and trunk do across the same.
const SWORD_SLASH := Vector2(0.34, 0.46)
const SWORD_SHEATH := Vector2(0.52, 0.72)
const HOT_YANK := Vector2(0.55, 0.7)
const BOW_DRAW := Vector2(0.3, 0.55)
const BOW_LOOSE := Vector2(0.68, 0.74)
const LOUDER := Vector2(0.5, 0.7)


# The skater's arm geometry, UpperBody-local metres. Filled by the caller.
class Rig:
	var top_shoulder := Vector3(0.22, 0.4, 0.0)
	var bottom_shoulder := Vector3(-0.22, 0.4, 0.0)
	var arm: float = 0.66
	var stick: float = 1.3
	var ice_y: float = -1.0


class Arms:
	var hand := Vector3.ZERO
	var blade := Vector3.ZERO
	# Where the free (bottom) hand goes, and how far off the shaft it is taken.
	var free := Vector3.ZERO
	var free_weight: float = 0.0


class Body:
	# Stance engagement the legs sit at, at least (× stance_hip_deg).
	var crouch: float = 0.0
	# Share of the one-knee kneel.
	var kneel: float = 0.0
	# Trunk texture, radians: pitch negative folds forward, and the roll leans
	# the trunk over toward the free hand's side.
	var pitch: float = 0.0
	var lean_to_free: float = 0.0


# Fills out.hand and out.blade. Consume before the next call.
static func arms(celly: int, t: float, s: float, rig: Rig, out: Arms) -> void:
	var o := Vector3.ZERO
	var d := Vector3.ZERO
	match celly:
		CellyRegistry.SWORD_SHEATH:
			var slash: float = _beat(t, SWORD_SLASH)
			var sheath: float = _beat(t, SWORD_SHEATH)
			o = Vector3(-0.15, -0.05, -0.55).lerp(Vector3(0.3, -0.25, -0.5), slash) \
					.lerp(Vector3(0.08, -0.68, -0.15), sheath)
			d = Vector3(-0.1, 0.75, -0.65).lerp(Vector3(0.75, -0.15, -0.65), slash) \
					.lerp(Vector3(0.2, -0.45, 0.87), sheath)
		CellyRegistry.KNEE_SLIDE:
			o = Vector3(0.3, -0.6, 0.0)
			d = Vector3(0.75, -0.5, 0.4)
		CellyRegistry.HOT_STICK:
			var hot: float = _beat(t, HOT_YANK)
			o = Vector3(-0.05, -0.8, -0.5).lerp(Vector3(0.05, -0.5, -0.35), hot)
			o.x += 0.05 * sin(TAU * 7.0 * s) * hot
			d = Vector3(-0.4, -0.6, -0.7)
		CellyRegistry.BOW_AND_ARROW:
			var drawn: float = _beat(t, BOW_DRAW)
			var loosed: float = _beat(t, BOW_LOOSE)
			d = _bearing(BOW_AIM, 1.0)
			# The draw slides the hand back along the arrow to the cheek; the loose
			# flicks it back and out off the line.
			var nocked: Vector3 = BOW_CHEEK + d * BOW_DRAW_M / rig.arm
			o = nocked.lerp(BOW_CHEEK, drawn).lerp(BOW_CHEEK + Vector3(0.25, 0.05, 0.3), loosed)
		CellyRegistry.CANT_HEAR_YOU:
			var louder: float = _beat(t, LOUDER)
			var pump: float = 0.5 - 0.5 * cos(TAU * 2.0 * s)
			o = Vector3(0.15, -0.65, -0.15).lerp(Vector3(0.2, 0.7 + 0.15 * pump, 0.0), louder)
			d = Vector3(0.45, -0.55, -0.7).lerp(Vector3(0.3, 0.9, 0.3), louder)
		_:
			o = Vector3(0.2, 0.75 + 0.04 * sin(TAU * 1.5 * s), -0.35)
			d = Vector3(0.25, 0.9, 0.35)
	var top_side: float = signf(rig.top_shoulder.x)
	out.hand = _at(rig.top_shoulder, top_side, o, rig.arm)
	out.blade = _lay_stick(out.hand, _bearing(d, top_side), rig)


# Where the free (bottom) hand goes for the stick as placed — posed by arms(),
# or a remote's off the wire, within the arm's reach. Fills out.free and
# out.free_weight.
static func free_hand(celly: int, t: float, s: float, rig: Rig, hand: Vector3,
		blade: Vector3, out: Arms) -> void:
	var side: float = signf(rig.bottom_shoulder.x)
	out.free_weight = 1.0
	match celly:
		CellyRegistry.SWORD_SHEATH:
			var sheath: float = _beat(t, SWORD_SHEATH)
			out.free = _at(rig.bottom_shoulder, side,
					Vector3(0.15, -0.82, -0.25).lerp(Vector3(0.12, -0.62, 0.02), sheath), rig.arm)
		CellyRegistry.KNEE_SLIDE:
			var yank: float = (0.5 - 0.5 * cos(TAU * 1.8 * s)) * smoothstep(0.12, 0.22, t)
			out.free = _at(rig.bottom_shoulder, side,
					Vector3(0.3, lerpf(0.7, 0.05, yank), -0.3), rig.arm)
		CellyRegistry.HOT_STICK:
			var hot: float = _beat(t, HOT_YANK)
			var warm: Vector3 = hand.lerp(blade, WARM_GRIP) + Vector3(
					0.05 * cos(TAU * 1.5 * s) * side, WARM_HOVER_M, 0.05 * sin(TAU * 1.5 * s))
			var burnt: Vector3 = _at(rig.bottom_shoulder, side,
					Vector3(0.55 + 0.06 * sin(TAU * 8.0 * s), 0.05, -0.55), rig.arm)
			out.free = warm.lerp(burnt, hot)
			out.free_weight = smoothstep(0.12, 0.22, t)
		CellyRegistry.BOW_AND_ARROW:
			# The bow hand holds where the drawn arrow's shaft passes, still while
			# the top hand draws through it.
			var top_side: float = signf(rig.top_shoulder.x)
			out.free = _at(rig.top_shoulder, top_side, BOW_CHEEK, rig.arm) \
					+ _bearing(BOW_AIM, top_side) * BOW_GRIP_M
			out.free_weight = smoothstep(0.05, 0.25, t)
		CellyRegistry.CANT_HEAR_YOU:
			out.free = _at(rig.bottom_shoulder, side, Vector3(-0.12, 0.35, 0.05), rig.arm)
		_:
			var punch: float = 0.5 + 0.5 * sin(TAU * 2.0 * s)
			out.free = _at(rig.bottom_shoulder, side,
					Vector3(0.35, lerpf(0.45, 0.78, punch), -0.15), rig.arm)
	var span: Vector3 = out.free - rig.bottom_shoulder
	if span.length() > rig.arm:
		out.free = rig.bottom_shoulder + span.normalized() * rig.arm


# What the celebration asks of the legs and the trunk. Fills `out`.
static func body(celly: int, t: float, s: float, out: Body) -> void:
	out.crouch = 0.0
	out.kneel = 0.0
	out.pitch = 0.0
	out.lean_to_free = 0.0
	match celly:
		CellyRegistry.SWORD_SHEATH:
			var slash: float = _beat(t, SWORD_SLASH)
			var sheath: float = _beat(t, SWORD_SHEATH)
			out.crouch = 1.2 * slash * (1.0 - sheath)
			out.pitch = lerpf(0.05, 0.14, sheath)
		CellyRegistry.KNEE_SLIDE:
			out.kneel = 1.0
			out.pitch = 0.18
		CellyRegistry.HOT_STICK:
			var hot: float = _beat(t, HOT_YANK)
			out.crouch = lerpf(2.8, 1.4, hot)
			out.pitch = lerpf(-0.35, -0.1, hot)
		CellyRegistry.BOW_AND_ARROW:
			out.crouch = 1.4
			out.lean_to_free = 0.08
		CellyRegistry.CANT_HEAR_YOU:
			var louder: float = _beat(t, LOUDER)
			out.lean_to_free = 0.22 * (1.0 - louder)
			out.pitch = lerpf(-0.06, 0.1, louder)
		_:
			out.crouch = 0.6 * (0.5 - 0.5 * cos(TAU * s))
			out.pitch = 0.12


static func _beat(t: float, beat: Vector2) -> float:
	return smoothstep(beat.x, beat.y, t)


static func _at(shoulder: Vector3, side: float, o: Vector3, arm: float) -> Vector3:
	return shoulder + Vector3(o.x * side, o.y, o.z) * arm


static func _bearing(d: Vector3, side: float) -> Vector3:
	return Vector3(d.x * side, d.y, d.z).normalized()


# The blade one stick length along `dir` from the hand, the bearing lifted just
# enough that the blade stays on the ice rather than under it.
static func _lay_stick(hand: Vector3, dir: Vector3, rig: Rig) -> Vector3:
	var floor_y: float = clampf((rig.ice_y - hand.y) / rig.stick, -1.0, 1.0)
	if dir.y < floor_y:
		var flat := Vector2(dir.x, dir.z)
		flat = flat.normalized() * sqrt(1.0 - floor_y * floor_y) \
				if flat.length_squared() > 0.000001 else Vector2(0.0, -sqrt(1.0 - floor_y * floor_y))
		dir = Vector3(flat.x, floor_y, flat.y)
	return hand + dir * rig.stick
