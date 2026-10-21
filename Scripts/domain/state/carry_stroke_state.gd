class_name CarryStrokeState
extends RefCounted

# Which side of the carried puck the blade is on, keyed off the puck's lateral
# motion in the carrier's frame (docs/stickhandling-push-model-plan.md §7e).
#
# A face can only push the puck away from itself, so a stroke is contact for as
# long as the puck is gaining speed off the blade. Once a hard stroke stops
# gaining speed the push is spent: the puck runs on by itself, and the blade goes
# over it to the far face to meet it — the RELEASE. That face catches the puck
# as it slows and throws it back, which is the next push. A stroke that never
# reaches `release_speed` is a slow push held on one face, and flips only once
# the puck comes back at the blade faster than `flip_speed` (the FLIP, the
# plain stroke rule).
#
# After a release the puck is coming toward the blade; it is a catch while that
# speed falls. Speed rising again by `repush_margin` is the puck being pushed
# the same way a second time, which the leading face cannot do, so the blade
# goes back to the trailing face (a FLIP).
#
# `side` is a face-normal sign: +1 = the blade on the +face_normal side of the
# puck. The caller owns it; step() reports a flip and the caller applies it.

enum Event { NONE, FLIP, RELEASE }

var catching: bool = false
# Fastest the puck has run off the blade in the current push, and how long ago.
var _push_peak: float = 0.0
var _push_peak_age: float = 0.0
# Slowest the puck has come at the blade since the release.
var _catch_min: float = 0.0


func reset() -> void:
	catching = false
	_push_peak = 0.0
	_push_peak_age = 0.0
	_catch_min = 0.0


# `v_perp` is the puck's velocity along +face_normal relative to the carrier,
# m/s. Any event other than NONE means the blade changes to −side.
func step(side: int, v_perp: float, delta: float, flip_speed: float,
		release_speed: float, release_hold_s: float, repush_margin: float) -> int:
	var toward_blade: float = v_perp * float(side)
	if catching:
		if toward_blade <= 0.0:
			catching = false  # the puck turned: the throw is a push like any other
			_start_push()
		else:
			_catch_min = minf(_catch_min, toward_blade)
			if toward_blade >= flip_speed and toward_blade > _catch_min + repush_margin:
				catching = false
				_start_push()
				return Event.FLIP
			return Event.NONE
	var away: float = -toward_blade
	if away <= 0.0:
		_start_push()
		if CarryContactRules.stroke_side(side, v_perp, flip_speed) != side:
			return Event.FLIP
		return Event.NONE
	if away > _push_peak:
		_push_peak = away
		_push_peak_age = 0.0
		return Event.NONE
	_push_peak_age += delta
	if _push_peak >= release_speed and _push_peak_age >= release_hold_s \
			and away >= flip_speed:
		catching = true
		_catch_min = away
		return Event.RELEASE
	return Event.NONE


func _start_push() -> void:
	_push_peak = 0.0
	_push_peak_age = 0.0
