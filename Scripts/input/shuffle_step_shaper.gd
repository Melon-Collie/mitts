class_name ShuffleStepShaper
extends RefCounted

# The brake's shuffle as single steps. While the brake is held the stick reaches
# the movement model only as steps: each press of a direction starts one, held
# just long enough that the brake, taking over when it lets go, stops the body
# `distance` from where it started. Holding the direction does nothing more, and
# a stick already held when the brake goes on is no press, so a hockey stop is a
# stop whatever the stick says.
#
# It runs on the input before anything records or sends it, so the host, the
# reconcile replay and every remote see an ordinary held stick; nothing about a
# step rides the wire. It steers off the local skater's own predicted state,
# which the host reproduces from these same inputs.

# Stick deflection that reads as a press, and the lower one it must fall back
# under before the next (a pad stick wanders around a single threshold).
const PRESS: float = 0.5
const RELEASE: float = 0.3
# A step that has not arrived in this long (the boards, a body) gives up.
const MAX_STEP_S: float = 1.0

var _pressed: bool = false
var _stepping: bool = false
var _dir := Vector2.ZERO
var _origin := Vector2.ZERO
var _age: float = 0.0


func reset() -> void:
	_pressed = false
	_stepping = false


# Rewrites `input.move_vector` in place. `position` and `velocity` are the
# skater's at the start of this tick; `stop_decel` is the brake the movement
# model stops it with (SkaterMovementRules.apply_movement) and `max_start_speed`
# the speed a step may start from (the shuffle's ceiling).
func shape(input: InputState, position: Vector3, velocity: Vector3, distance: float,
		stop_decel: float, max_start_speed: float) -> void:
	var raw: Vector2 = input.move_vector
	var was_pressed: bool = _pressed
	_pressed = raw.length() > (RELEASE if was_pressed else PRESS)
	if not input.brake:
		_stepping = false
		return
	var pos := Vector2(position.x, position.z)
	var vel := Vector2(velocity.x, velocity.z)
	if _pressed and not was_pressed and vel.length() <= max_start_speed:
		_stepping = true
		_dir = raw.normalized()
		_origin = pos
		_age = 0.0
	input.move_vector = Vector2.ZERO
	if not _stepping:
		return
	_age += input.delta
	var along: float = vel.dot(_dir)
	var remaining: float = distance - (pos - _origin).dot(_dir)
	# Let go once braking from here lands nearer the mark than one more pushed
	# tick would: the brake's stopping distance, plus half a tick of travel.
	var stopping: float = along * along / (2.0 * maxf(stop_decel, 0.001)) \
			+ 0.5 * along * input.delta
	if remaining <= stopping or _age > MAX_STEP_S:
		_stepping = false
		return
	input.move_vector = _dir
