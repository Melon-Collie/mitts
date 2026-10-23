class_name SkaterSettleGate
extends RefCounted

# The settle lock a hard catch leaves (docs/stick-settling-plan.md): until the
# deadline the grant carried, a carrier's inputs fire no on-puck action; the
# latest press is queued and fires on the first unlocked input.
#
# The deadline is in input-stamp time, and the host gates a remote's inputs at
# their own stamps, so host and client lock exactly the same inputs whatever the
# latency. It is compared on the 0.1 ms wire grid every stamp rides
# (Constants.TIME_WIRE_SCALE): a client's predicted stamp and the host's decoded
# copy of it round to the same integer, where the floats may not compare alike.

enum Press { NONE, PASS, WRISTER, SLAP, NUDGE }

const _WIRE_PER_MS: int = int(Constants.TIME_WIRE_SCALE / 1000.0)

var _until_wire: int = 0
# Presses stamped before this are not queued: the host's copy of a remote
# carrier's lock opens before that carrier's client can know it holds the puck,
# and a press it made then was a puckless one on its own screen.
var _notice_from_wire: int = 0
var _notice_from_pending: float = 0.0
# The press waiting for the unlock. Replay re-derives it from the same inputs,
# so LocalController saves and restores it around a reconcile.
var queued: Press = Press.NONE
# This input's read (read → the controller's dispatch): still locked, or the
# queued press the unlock just released.
var settling: bool = false
var unqueued: Press = Press.NONE
# Stamp of the latest input read: the clock a deadline is set against, in the
# controller's own input-stamp domain.
var last_stamp: float = 0.0


# Per input. `carrying`: a plain carry, the only state the lock holds.
func read(input: InputState, carrying: bool) -> void:
	last_stamp = input.host_timestamp
	unqueued = Press.NONE
	settling = carrying and is_settling(input.host_timestamp)
	if settling:
		note(input)
	elif queued != Press.NONE:
		unqueued = take()


# Host: the deadline (ms of input-stamp time) a catch settling for `settle_s`
# locks the carrier until, 0 for a clean catch — from the stamp of the input the
# grant lands on, plus `grace`, how far behind the carrier's client learns of it
# (SkaterController.one_timer_window_lag_grace). The grace allows for the grant
# arriving on a snapshot a broadcast late; by the reliable RPC the client knows a
# broadcast sooner, and its presses from then on are ones it can queue.
func deadline_ms(settle_s: float, grace: float) -> int:
	if settle_s <= 0.0:
		return 0
	_notice_from_pending = last_stamp + maxf(0.0, grace - 1.0 / float(Constants.STATE_RATE))
	return roundi((last_stamp + grace + settle_s) * 1000.0)


func arm(until_ms: int) -> void:
	_until_wire = maxi(until_ms, 0) * _WIRE_PER_MS
	_notice_from_wire = _to_wire(_notice_from_pending)
	_notice_from_pending = 0.0
	queued = Press.NONE


# A lock the carrier's own input sets — a slapshot called off — rather than one
# a grant carries: every machine reads the same input at the same stamp, so it
# arms the same deadline with no notice window. `until_stamp`: input-stamp
# seconds.
func arm_local(until_stamp: float) -> void:
	_until_wire = _to_wire(until_stamp)
	_notice_from_wire = 0
	queued = Press.NONE


func clear() -> void:
	_until_wire = 0
	_notice_from_wire = 0
	queued = Press.NONE


func is_settling(stamp: float) -> bool:
	return _until_wire > 0 and _to_wire(stamp) < _until_wire


func time_left(stamp: float) -> float:
	if _until_wire <= 0:
		return 0.0
	return maxf(0.0, float(_until_wire - _to_wire(stamp)) / Constants.TIME_WIRE_SCALE)


# Queue this input's press, if it has one. A later press replaces an earlier one.
func note(input: InputState) -> void:
	if _to_wire(input.host_timestamp) < _notice_from_wire:
		return
	if input.quick_pass_pressed:
		queued = Press.PASS
	elif input.shoot_pressed:
		queued = Press.WRISTER
	elif input.slap_pressed:
		queued = Press.SLAP
	elif input.stick_lift_pressed:
		queued = Press.NUDGE


func take() -> Press:
	var press: Press = queued
	queued = Press.NONE
	return press


# Sets a queued shot or pass press's edge on `input` to `value` and returns what
# it was, so a caller dispatching the press as this input's own can put the
# input back: input history and reconcile replay hold the same object. (A
# queued nudge has no dispatch to ride; the controller fires it directly.)
static func set_edge(input: InputState, press: Press, value: bool) -> bool:
	var was: bool = false
	match press:
		Press.PASS:
			was = input.quick_pass_pressed
			input.quick_pass_pressed = value
		Press.WRISTER:
			was = input.shoot_pressed
			input.shoot_pressed = value
		Press.SLAP:
			was = input.slap_pressed
			input.slap_pressed = value
	return was


static func _to_wire(stamp: float) -> int:
	return roundi(maxf(stamp, 0.0) * Constants.TIME_WIRE_SCALE)
