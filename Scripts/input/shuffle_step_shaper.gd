class_name ShuffleStepShaper
extends RefCounted

# The shuffle is the brake held with a stick, slow (SkaterMovementRules
# .is_shuffle); the movement model and the gait skate it from the plain stick
# and brake. Two things about it shape the input, here, before anything records
# or sends it, so the host, the reconcile replay and every remote see an
# ordinary stick and brake and nothing about a step rides the wire. It steers
# off the local skater's own predicted state, which the host reproduces from
# these same inputs.
#
# - A shuffle let go of finishes its step. The stick is held on until braking
#   stops the body where its step-together closes — every `distance` of ground
#   since the shuffle began, the cycle the gait lays over the ground — and the
#   brake stays on until the body is still, so the skates plant together. A
#   quick press is one whole step.
# - A stick already driving along the travel when the brake goes on at speed is
#   held off for as long as both stay down: W held through a stop stops, rather
#   than slowing into a shuffle forward. A key across or against the travel
#   held through a stop flows into the shuffle, and so does any key pressed
#   once braking.
#
# Bots drive the same stick and brake through the same movement model and are
# never shaped.

enum Phase { NONE, SHUFFLING, FINISH, SETTLE }

# Stick deflection that reads as a press, and the lower one it must fall back
# under before it reads as let go (a pad stick wanders around a single threshold).
const PRESS: float = 0.5
const RELEASE: float = 0.3
# A step that has not closed in this long (the boards, a body) gives up.
const MAX_STEP_S: float = 1.0
# Below this speed (m/s) a settling step has come to rest.
const REST_SPEED: float = 0.01
# Ground past a closed step-together (m) that still counts as closed.
const CLOSED_M: float = 0.01

var _pressed: bool = false
var _braked: bool = false
var _held_off: bool = false
var _phase: Phase = Phase.NONE
var _dir := Vector2.ZERO
# Ground covered since the shuffle began, m.
var _travel: float = 0.0
var _age: float = 0.0


func reset() -> void:
	_pressed = false
	_braked = false
	_held_off = false
	_phase = Phase.NONE


# Rewrites `input.move_vector` and `input.brake` in place. `velocity` is the
# skater's at the start of this tick; `stop_decel` is the brake the movement
# model stops it with, and `distance` the ground a step-together covers.
func shape(input: InputState, velocity: Vector3, distance: float, stop_decel: float) -> void:
	var raw: Vector2 = input.move_vector
	var was_pressed: bool = _pressed
	_pressed = raw.length() > (RELEASE if was_pressed else PRESS)
	var vel := Vector2(velocity.x, velocity.z)
	var speed: float = vel.length()
	if input.brake and not _braked and _pressed \
			and speed > SkaterMovementRules.SHUFFLE_MAX_SPEED \
			and raw.normalized().dot(vel / speed) >= SkaterMovementRules.SHUFFLE_AHEAD_COS:
		_held_off = true
	_held_off = _held_off and input.brake and _pressed
	_braked = input.brake
	if _held_off:
		input.move_vector = Vector2.ZERO
		_phase = Phase.NONE
		return
	if _pressed:
		if not input.brake:
			_phase = Phase.NONE
			return
		if speed <= SkaterMovementRules.SHUFFLE_MAX_SPEED:
			if _phase != Phase.SHUFFLING:
				_travel = 0.0
			_phase = Phase.SHUFFLING
			_dir = raw.normalized()
			_travel += speed * input.delta
		return
	if _phase == Phase.NONE:
		return
	if _phase == Phase.SHUFFLING:
		_phase = Phase.FINISH
		_age = 0.0
	_age += input.delta
	input.brake = true
	input.move_vector = Vector2.ZERO
	if _phase == Phase.SETTLE:
		if speed < REST_SPEED or _age > MAX_STEP_S:
			_phase = Phase.NONE
		return
	var into: float = fmod(_travel, distance)
	var remaining: float = distance - into
	if _travel > distance * 0.5 and into < CLOSED_M:
		remaining = 0.0
	# Let go once braking from here lands nearer the close than one more pushed
	# tick would: the brake's stopping distance, plus half a tick of travel.
	var along: float = maxf(vel.dot(_dir), 0.0)
	var stopping: float = along * along / (2.0 * maxf(stop_decel, 0.001)) \
			+ 0.5 * along * input.delta
	if remaining <= stopping or _age > MAX_STEP_S:
		_phase = Phase.SETTLE
		return
	input.move_vector = _dir
	_travel += speed * input.delta
