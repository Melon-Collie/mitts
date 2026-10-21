class_name CarryStrokeState
extends RefCounted

# Which side of the carried puck the blade is on, keyed off the puck's lateral
# motion in the carrier's frame (docs/stickhandling-push-model-plan.md §7e).
#
# A face can only push the puck away from itself, so a stroke is contact for as
# long as the puck is gaining speed off the blade. Once a hard stroke has lost
# `release_drop` of its peak speed the push is spent, and once the puck is
# slowing fast enough to stop within `release_stop_s` it is turning: the puck
# runs on by itself, and the blade goes over it to the far face to meet it —
# the RELEASE. A sweep that only slows, one way, keeps its face: the puck is not
# coming back, so the blade waits behind it for the next push.
# That face catches the puck as it slows and throws it back, which is the next
# push. A stroke that never reaches `release_speed` is a slow push held on one
# face, and flips only once the puck comes back at the blade faster than
# `flip_speed` (the FLIP, the plain stroke rule).
#
# After a release the puck is coming toward the blade; it is a catch while that
# speed falls. Speed rising again by `repush_margin` is the puck being pushed
# the same way a second time, which the leading face cannot do, so the blade
# goes back to the trailing face (a FLIP).
#
# A hand on a mouse is never still, and the blade's inertia turns a cursor that
# updates on alternate ticks into a speed that dips on them, so the speed is
# read through a first-order filter of `smoothing_s`, and a face only changes
# once the puck has gone `flip_distance` the new way: a wobble moves it a
# centimetre or two, a stroke a hand's width.
#
# At a release, `release_peak` is how hard the stroke was and `stop_in_s` how
# long the puck has left before it stops: when the far face has to be there. A
# sweep slows gently off its peak and then harder, so the slowing is taken to
# grow steadily (constant jerk), which puts a side-to-side dangle's stop ~10%
# early; the speed over the slowing so far would put it twice as late.
#
# `side` is a face-normal sign: +1 = the blade on the +face_normal side of the
# puck. The caller owns it; step() reports a flip and the caller applies it. A
# peer told the side instead (a client drawing someone else's carry, off the
# wire) reads the same stroke through observe() and asks wire_flip() what a
# flip it was told of was.

enum Event { NONE, FLIP, RELEASE }
# Why the last face change happened, for StickDebugOverlay: a slow stroke's
# puck coming back at the blade, a second push the way a release sent it, a
# release, or a side told from outside.
enum Cause { NONE, RETURN, REPUSH, RELEASE, TOLD }

var catching: bool = false
# The last face change: its cause, the puck's speed then (m/s, toward the blade
# for a flip, off it for a release) and how far it had come for a flip (m).
var last_cause: Cause = Cause.NONE
var last_speed: float = 0.0
var last_travel_m: float = 0.0
var release_peak: float = 0.0
var stop_in_s: float = 0.0
# The filtered lateral speed and its rate of change, and whether they have a
# first sample.
var _v: float = 0.0
var _dv: float = 0.0
var _v_valid: bool = false
# Fastest the puck has run off the blade in the current push, and how long ago.
var _push_peak: float = 0.0
var _push_peak_age: float = 0.0
# Slowest the puck has come at the blade since the release, and how far it has
# come since.
var _catch_min: float = 0.0
var _since_min_m: float = 0.0
# How far the puck has come at the blade outside a catch.
var _toward_m: float = 0.0


func reset() -> void:
	catching = false
	release_peak = 0.0
	stop_in_s = 0.0
	_v = 0.0
	_dv = 0.0
	_v_valid = false
	_push_peak = 0.0
	_push_peak_age = 0.0
	_catch_min = 0.0
	_since_min_m = 0.0
	_toward_m = 0.0


# `v_perp` is the puck's velocity along +face_normal relative to the carrier,
# m/s. Any event other than NONE means the blade changes to −side.
func step(side: int, v_perp: float, delta: float, smoothing_s: float, flip_speed: float,
		flip_distance: float, release_speed: float, release_drop: float, release_stop_s: float,
		repush_margin: float) -> int:
	_filter(v_perp, delta, smoothing_s)
	var toward_blade: float = _v * float(side)
	if catching:
		if toward_blade <= 0.0:
			catching = false  # the puck turned: the throw is a push like any other
			_push_peak = 0.0
		else:
			if toward_blade < _catch_min:
				_catch_min = toward_blade
				_since_min_m = 0.0
			else:
				_since_min_m += toward_blade * delta
			if toward_blade >= flip_speed and toward_blade > _catch_min + repush_margin \
					and _since_min_m >= flip_distance:
				return _flip(Cause.REPUSH, toward_blade, _since_min_m)
			return Event.NONE
	var away: float = -toward_blade
	if away <= 0.0:
		_push_peak = 0.0
		_toward_m += toward_blade * delta
		if toward_blade >= flip_speed and _toward_m >= flip_distance:
			return _flip(Cause.RETURN, toward_blade, _toward_m)
		return Event.NONE
	_toward_m = 0.0
	if away > _push_peak:
		_push_peak = away
		_push_peak_age = 0.0
		return Event.NONE
	_push_peak_age += delta
	# How fast the push is dying: the puck slows by this, m/s².
	var slowing: float = _dv * float(side)
	if _push_peak >= release_speed and away <= _push_peak * (1.0 - release_drop) \
			and away >= flip_speed and away <= slowing * release_stop_s:
		_release(away, smoothing_s)
		_note(Cause.RELEASE, away, 0.0)
		return Event.RELEASE
	return Event.NONE


# The stroke read of step() without its decisions, for a peer told the side.
func observe(side: int, v_perp: float, delta: float, smoothing_s: float) -> void:
	_filter(v_perp, delta, smoothing_s)
	var away: float = -_v * float(side)
	if away > _push_peak:
		_push_peak = away
		_push_peak_age = 0.0
	else:
		_push_peak_age += delta


# The blade was flipped off `side` from outside: a RELEASE if it left a stroke
# that peaked at `release_speed` and is spending it, which sets release_peak and
# stop_in_s as step() does, else a FLIP.
func wire_flip(side: int, smoothing_s: float, flip_speed: float, release_speed: float) -> int:
	var away: float = -_v * float(side)
	if _push_peak >= release_speed and away < _push_peak and away >= flip_speed:
		_release(away, smoothing_s)
		_push_peak = 0.0
		_note(Cause.TOLD, away, 0.0)
		return Event.RELEASE
	return _flip(Cause.TOLD, -away, 0.0)


# The filtered lateral speed toward the blade at `side` (m/s; negative = off it).
func toward(side: int) -> float:
	return _v * float(side)


func _filter(v_perp: float, delta: float, smoothing_s: float) -> void:
	if not _v_valid or smoothing_s <= 0.0 or delta <= 0.0:
		_dv = (v_perp - _v) / delta if _v_valid and delta > 0.0 else 0.0
		_v = v_perp
		_v_valid = true
		return
	var k: float = 1.0 - exp(-delta / smoothing_s)
	var was: float = _v
	_v += (v_perp - _v) * k
	_dv += ((_v - was) / delta - _dv) * k


func _release(away: float, smoothing_s: float) -> void:
	catching = true
	release_peak = _push_peak
	# Less the filter's own lag: it reads the puck about smoothing_s late.
	stop_in_s = maxf(_push_peak_age * (sqrt(_push_peak / (_push_peak - away)) - 1.0)
			- maxf(smoothing_s, 0.0), 0.0)
	_catch_min = away
	_since_min_m = 0.0


func _flip(cause: Cause, speed: float, travel_m: float) -> int:
	_note(cause, speed, travel_m)
	catching = false
	_push_peak = 0.0
	_toward_m = 0.0
	return Event.FLIP


func _note(cause: Cause, speed: float, travel_m: float) -> void:
	last_cause = cause
	last_speed = speed
	last_travel_m = travel_m
