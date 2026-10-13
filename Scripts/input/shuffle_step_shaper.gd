class_name ShuffleStepShaper
extends RefCounted

# The shuffle as a tap. From a near-standstill, a press to the side or back is a
# step: the brake goes on with the stick (the movement model's shuffle,
# SkaterMovementRules.shuffle_velocity), held just long enough that the brake,
# taking over when the stick lets go, stops the body `distance` from where it
# started, and on until it is still. A press still held when the tap window
# closes was never a tap: the step lets go of both and the skater skates on from
# there. A press ahead (within 45° of facing) is a start, never a step — a
# skater pushes off forward, and the shuffle's slower pace would cost the start.
#
# The player's own brake is the stop and nothing else: under it the stick never
# reaches the movement model, so a hockey stop is a stop whatever the stick says.
#
# It runs on the input before anything records or sends it, so the host, the
# reconcile replay and every remote see an ordinary stick and brake; nothing
# about a step rides the wire. It steers off the local skater's own predicted
# state, which the host reproduces from these same inputs.

enum Phase { NONE, PUSH, SETTLE }

# Stick deflection that reads as a press, and the lower one it must fall back
# under before the next (a pad stick wanders around a single threshold).
const PRESS: float = 0.5
const RELEASE: float = 0.3
# How long a press may be held and still be a tap, seconds: under a start's
# first ~12 cm, which a hold skates on from rather than losing.
const TAP_WINDOW_S: float = 0.15
# cos 45°: a press at least this far ahead of facing is a start (W+D skates).
const AHEAD_COS: float = 0.707
# A step that has not arrived in this long (the boards, a body) gives up.
const MAX_STEP_S: float = 1.0
# Below this speed (m/s) a settling step has come to rest.
const REST_SPEED: float = 0.01

var _pressed: bool = false
var _phase: Phase = Phase.NONE
# The press that started the step is still down.
var _held: bool = false
var _dir := Vector2.ZERO
var _origin := Vector2.ZERO
var _age: float = 0.0


func reset() -> void:
	_pressed = false
	_phase = Phase.NONE


# Rewrites `input.move_vector` and `input.brake` in place. `position` and
# `velocity` are the skater's at the start of this tick and `facing` its XZ
# facing; `stop_decel` is the brake the movement model stops it with.
func shape(input: InputState, position: Vector3, velocity: Vector3, facing: Vector2,
		distance: float, stop_decel: float) -> void:
	var raw: Vector2 = input.move_vector
	var was_pressed: bool = _pressed
	_pressed = raw.length() > (RELEASE if was_pressed else PRESS)
	if input.brake:
		_phase = Phase.NONE
		input.move_vector = Vector2.ZERO
		return
	var pos := Vector2(position.x, position.z)
	var vel := Vector2(velocity.x, velocity.z)
	if _pressed and not was_pressed:
		var dir: Vector2 = raw.normalized()
		if vel.length() <= SkaterMovementRules.GRIP_MIN_SPEED and dir.dot(facing) < AHEAD_COS:
			_phase = Phase.PUSH
			_held = true
			_dir = dir
			_origin = pos
			_age = 0.0
		else:
			_phase = Phase.NONE
	if _phase == Phase.NONE:
		return
	_held = _held and _pressed
	_age += input.delta
	if _phase == Phase.PUSH and _held and _age >= TAP_WINDOW_S:
		_phase = Phase.NONE
		return
	input.brake = true
	input.move_vector = Vector2.ZERO
	if _phase == Phase.SETTLE:
		if vel.length() < REST_SPEED or _age > MAX_STEP_S:
			_phase = Phase.NONE
		return
	var along: float = vel.dot(_dir)
	var remaining: float = distance - (pos - _origin).dot(_dir)
	# Let go once braking from here lands nearer the mark than one more pushed
	# tick would: the brake's stopping distance, plus half a tick of travel.
	var stopping: float = along * along / (2.0 * maxf(stop_decel, 0.001)) \
			+ 0.5 * along * input.delta
	if remaining <= stopping or _age > MAX_STEP_S:
		_phase = Phase.SETTLE
		return
	input.move_vector = _dir
