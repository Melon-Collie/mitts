class_name SkaterReadyFold
extends RefCounted

# The ready fold's ease: the chest's fold over a tracked stick, stepped on the
# tick toward where the blade and the puck put it. It is tick state the blade
# pass reads, so a reconcile's replay plays back the fold each live tick left
# (LocalController, PredictedState) rather than stepping it again.

# The fold's spring (rad/s): a trunk settling over the stick in about half a
# second, as a body's weight comes forward.
const OMEGA: float = 8.0

# Where the fold settles (rad), read each step: SkaterIKCoordinator's.
var _target: Callable
var _fold: float = 0.0
var _rate: float = 0.0
var _seeded: bool = false


func _init(target: Callable) -> void:
	_target = target


# The eased fold (rad), landed on its target the first time it is read.
func value() -> float:
	if not _seeded:
		_land(_target.call())
	return _fold


# One live tick's step, on every peer, whatever drove the body
# (Skater.tick_pose_update).
func advance(delta: float) -> void:
	var target: float = _target.call()
	if not _seeded or delta <= 0.0:
		_land(target)
		return
	var x: float = _fold
	_fold = maxf(EaseRules.critical_x(x, _rate, target, OMEGA, delta), 0.0)
	_rate = EaseRules.critical_v(x, _rate, target, OMEGA, delta)


# The fold as the last tick left it, landed or not: what a replay plays back.
func state() -> float:
	return _fold


# Takes the fold a live tick left, for the replay of that tick.
func adopt(fold: float) -> void:
	_fold = fold
	_seeded = true


# The next read or step lands on the target: a blade re-seeded from scratch.
func unseed() -> void:
	_seeded = false


func _land(target: float) -> void:
	_seeded = true
	_fold = target
	_rate = 0.0
