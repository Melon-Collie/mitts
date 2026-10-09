class_name LocomotionRules

# Which skating state the body is in, read off the same decision the physics
# makes (SkaterMovementRules.apply_movement) rather than re-guessed from how the
# velocity happened to change. Everything it reads — velocity, move intent,
# brake, facing — is replicated, so every machine poses the same skate.
#
# Two things decide a moving skater's state, both what the physics is doing
# rather than where the stick points. DRIVE is the thrust it is applying: the
# stick's component along travel, exactly the `par` the movement model pushes
# by (its negative is a skid). TURNING is how much of the edge's lateral grip
# the travel's curve is using (SkaterLocomotion measures it). The physics turns
# at the full edge rate for any stick off travel and thrusts by the cosine, so
# a stick across travel coasts round on the edges and a diagonal one drives
# through the arc:
#
#   driving, not turning   STRIDE      driving and turning   CROSSOVER
#   coasting, not turning  GLIDE       coasting and turning  CARVE
#
# In the loaded stance the turning part is skated with both blades dug in
# (TIGHT) rather than crossed over or carved; the brake is a stop whatever the
# stick says. Below grip speed, where the push is free in any direction, the
# split is against facing instead of travel.
#
# Frame: XZ-plane vectors as Vector2(x, z).

# The state mix, filled in place by classify() — one per caller, never shared.
# Weights sum to 1.
class Mix extends RefCounted:
	var glide: float = 0.0
	var stride: float = 0.0
	var crossover: float = 0.0
	# Turning without driving: both blades on edge, the inside one leading.
	var carve: float = 0.0
	var backward: float = 0.0
	var shuffle: float = 0.0
	var skid: float = 0.0
	var tight: float = 0.0
	var stop: float = 0.0
	# +1 toward the traveller's right (CarveRules' sign): the inside of the
	# crossover, the carve and the tight turn, and the shuffle's direction.
	var side: float = 1.0

	func clear() -> void:
		glide = 0.0
		stride = 0.0
		crossover = 0.0
		carve = 0.0
		backward = 0.0
		shuffle = 0.0
		skid = 0.0
		tight = 0.0
		stop = 0.0


const _INTENT_MIN_SQ: float = 0.0025
# The drive at which the legs are fully pushing. The weights say WHETHER the
# skater pushes; how hard is the stroke's amplitude, which follows the measured
# acceleration. A stick 60° off travel still asks half the thrust and is skated
# as a push; below this the legs ease into coasting on the edges.
const DRIVE_FULL: float = 0.5


# `turning` is the share of the edge's lateral grip the travel's curve is using,
# 0..1 (SkaterLocomotion.sense).
static func classify(velocity: Vector2, intent: Vector2, brake: bool, stance: bool,
		facing: Vector2, turning: float, out: Mix) -> void:
	out.clear()
	var speed: float = velocity.length()
	var has_input: bool = intent.length_squared() > _INTENT_MIN_SQ
	if speed <= SkaterMovementRules.GRIP_MIN_SPEED:
		if not has_input:
			out.glide = 1.0
			return
		# Free push from a standstill: a start, a side-step or a backward push,
		# by where the stick points against the body.
		var dir: Vector2 = intent.normalized()
		var ahead: float = facing.dot(dir)
		var across: float = facing.cross(dir)
		out.stride = maxf(ahead, 0.0) ** 2
		out.backward = maxf(-ahead, 0.0) ** 2
		out.shuffle = across * across
		out.side = signf(across) if across != 0.0 else 1.0
		return
	var travel: Vector2 = velocity / speed
	if brake:
		if has_input:
			var steer: float = travel.angle_to(intent)
			out.side = signf(steer) if steer != 0.0 else 1.0
		out.stop = 1.0
		return
	if not has_input:
		out.glide = 1.0
		return
	var turn: float = travel.angle_to(intent)
	var along: float = cos(turn)
	var across_t: float = sin(turn)
	out.side = signf(across_t) if across_t != 0.0 else 1.0
	# Travel behind the facing is backward skating; a backward turn stays in the
	# C-cuts, which is how it is skated.
	if travel.dot(facing) < 0.0:
		out.skid = maxf(-along, 0.0) ** 2
		out.backward = 1.0 - out.skid
		return
	var stick: float = minf(intent.length(), 1.0)
	out.skid = maxf(-along, 0.0) * stick
	var moving: float = 1.0 - out.skid
	var push: float = moving * smoothstep(0.0, 1.0, maxf(along, 0.0) * stick / DRIVE_FULL)
	var coast: float = moving - push
	var t: float = clampf(turning, 0.0, 1.0)
	out.stride = push * (1.0 - t)
	out.glide = coast * (1.0 - t)
	if stance:
		out.tight = moving * t
	else:
		out.crossover = push * t
		out.carve = coast * t
