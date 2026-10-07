class_name GaitLayer
extends RefCounted

# One overlay on the locomotion pose. A layer keeps its own clock and blend,
# advanced from replicated state only, and contributes to the gait pass through
# the stages it declares. SkaterSkatingCoordinator runs its layers lowest
# priority first: an additive stage lays offsets on whatever is beneath, and an
# override lerps the channels it owns toward its own pose — taking everything
# beneath with them.

enum Stage { HOLD = 1, FLOOR = 2, LEGS = 4, TRUNK = 8, OVERRIDE = 16 }

var _skater: Skater = null
var _controller: SkaterController = null


func setup(skater: Skater, controller: SkaterController) -> void:
	_skater = skater
	_controller = controller


# The Stage bitmask the coordinator builds its per-stage lists from, once.
func stages() -> int:
	return 0


func reset() -> void:
	pass


# Whether the replicated trigger is idle. The coordinator's settled early-out
# holds only while every layer says so — not while a blend decays, which the
# settle window outlasts.
func is_quiet() -> bool:
	return true


# Advances the layer's clock and blend, and reports whether it contributes to
# this pass. An idle layer's stages are skipped, so it may answer false only
# when every stage it declares would leave the pose as it found it (to within
# the 0.001 blend floor the layers share).
func advance(_delta: float) -> bool:
	return false


# How much this layer holds the stride, 0..1 (the feet set).
func stride_hold() -> float:
	return 0.0


# The crouch engagement this layer sits the stance at, at least.
func stance_floor() -> float:
	return 0.0


# After the stance solve, before the knee solve: offsets on the leg joints.
func shape_legs(_p: GaitPose) -> void:
	pass


# After the knee solve: the trunk texture, and sinks riding on the solved legs.
func shape_trunk(_p: GaitPose) -> void:
	pass


func override(_p: GaitPose) -> void:
	pass
