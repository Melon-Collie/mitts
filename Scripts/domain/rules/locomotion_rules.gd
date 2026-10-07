class_name LocomotionRules

# Which skating state the body is in, read off the same decision the physics
# makes (SkaterMovementRules.apply_movement) rather than re-guessed from how the
# velocity happened to change. Everything it reads — velocity, move intent,
# brake, facing — is replicated, so every machine poses the same skate.
#
# The physics resolves the stick against travel: the part along it is a stride,
# the part against it is a skid, the part across it turns the travel on the
# edges. The squares of those cosine and sine terms sum to 1, so the same split
# is directly a crossfade between the three states. Braking divides the same way
# by the physics' own tight-turn weight; below grip speed, where the push is free
# in any direction, the split is against facing instead of travel.
#
# Frame: XZ-plane vectors as Vector2(x, z).
#
# Mirrored in C++ by NativeSkaterGait (native/src/native_skater_gait.cpp);
# test_native_gait_parity.gd fails if the two drift. Change both or neither.

# The state mix, filled in place by classify() — one per caller, never shared.
# Weights sum to 1.
class Mix extends RefCounted:
	var glide: float = 0.0
	var stride: float = 0.0
	var crossover: float = 0.0
	var backward: float = 0.0
	var shuffle: float = 0.0
	var skid: float = 0.0
	var tight: float = 0.0
	var stop: float = 0.0
	# +1 toward the traveller's right (CarveRules' sign): the crossover's and
	# the tight turn's inside, and the shuffle's direction.
	var side: float = 1.0

	func clear() -> void:
		glide = 0.0
		stride = 0.0
		crossover = 0.0
		backward = 0.0
		shuffle = 0.0
		skid = 0.0
		tight = 0.0
		stop = 0.0


const _INTENT_MIN_SQ: float = 0.0025


static func classify(velocity: Vector2, intent: Vector2, brake: bool, facing: Vector2,
		tight_align_angle: float, out: Mix) -> void:
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
			out.tight = SkaterMovementRules.tight_turn_weight(absf(steer), tight_align_angle)
			out.side = signf(steer) if steer != 0.0 else 1.0
		out.stop = 1.0 - out.tight
		return
	if not has_input:
		out.glide = 1.0
		return
	var turn: float = travel.angle_to(intent)
	var along: float = cos(turn)
	var across_t: float = sin(turn)
	out.side = signf(across_t) if across_t != 0.0 else 1.0
	out.skid = maxf(-along, 0.0) ** 2
	# Travel behind the facing is backward skating; a backward turn stays in the
	# C-cuts, which is how it is skated.
	if travel.dot(facing) < 0.0:
		out.backward = maxf(along, 0.0) ** 2 + across_t * across_t
	else:
		out.stride = maxf(along, 0.0) ** 2
		out.crossover = across_t * across_t
