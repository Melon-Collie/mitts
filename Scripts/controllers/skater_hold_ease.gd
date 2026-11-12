class_name SkaterHoldEase
extends RefCounted

# The hold's eased state: the chest's fold over a tracked stick, and how much
# of the hold is the two-handed one a puck asks for (the grip, 0 the top hand
# alone to 1), each stepped on the tick toward where the blade and the puck
# put it. It is tick state the blade pass reads, so a reconcile's replay plays
# back what each live tick left (LocalController, PredictedState) rather than
# stepping it again.

# The fold's spring (rad/s): a trunk settling over the stick in about half a
# second, as a body's weight comes forward.
const FOLD_OMEGA: float = 8.0
# The grip's: the hand sliding to its pocket as the other comes onto the shaft,
# in about a quarter second.
const GRIP_OMEGA: float = 16.0

# Where the two settle, as (fold in rad, grip), read each step:
# SkaterIKCoordinator's.
var _targets: Callable
var _fold: float = 0.0
var _fold_rate: float = 0.0
var _grip: float = 0.0
var _grip_rate: float = 0.0
var _seeded: bool = false


func _init(targets: Callable) -> void:
	_targets = targets


# The eased fold (rad), landed on its target the first time either is read.
func fold() -> float:
	if not _seeded:
		_land(_targets.call())
	return _fold


func grip() -> float:
	if not _seeded:
		_land(_targets.call())
	return _grip


# One live tick's step, on every peer, whatever drove the body
# (Skater.tick_pose_update).
func advance(delta: float) -> void:
	var target: Vector2 = _targets.call()
	if not _seeded or delta <= 0.0:
		_land(target)
		return
	var fold_was: float = _fold
	_fold = maxf(EaseRules.critical_x(fold_was, _fold_rate, target.x, FOLD_OMEGA, delta), 0.0)
	_fold_rate = EaseRules.critical_v(fold_was, _fold_rate, target.x, FOLD_OMEGA, delta)
	var grip_was: float = _grip
	_grip = clampf(EaseRules.critical_x(grip_was, _grip_rate, target.y, GRIP_OMEGA, delta),
			0.0, 1.0)
	_grip_rate = EaseRules.critical_v(grip_was, _grip_rate, target.y, GRIP_OMEGA, delta)


# The two as the last tick left them, landed or not, as (fold, grip): what a
# replay plays back.
func state() -> Vector2:
	return Vector2(_fold, _grip)


# Takes what a live tick left, for the replay of that tick.
func adopt(from: Vector2) -> void:
	_fold = from.x
	_grip = from.y
	_seeded = true


# The next read or step lands on the targets: a blade re-seeded from scratch.
func unseed() -> void:
	_seeded = false


func _land(target: Vector2) -> void:
	_seeded = true
	_fold = target.x
	_fold_rate = 0.0
	_grip = target.y
	_grip_rate = 0.0
