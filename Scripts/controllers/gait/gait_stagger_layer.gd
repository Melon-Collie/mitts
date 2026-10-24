class_name GaitStaggerLayer
extends GaitLayer

# A checked player visibly fighting for balance. The wobble phase is derived
# FROM stagger_timer (a uniform countdown), so every machine — and reconcile
# replay, which snaps the timer from the host — renders the identical stumble
# with zero new network state. Amplitude tracks the time left, so the wobble
# eases out with the recovery window; the two axes run at incommensurate
# frequencies so it reads as a stumble, not a metronome. It is written to the
# pose's wobble, which the coordinator adds after the trunk inertia filter — a
# stumble is supposed to shake, and the filter would blunt exactly the
# frequencies that sell it.
#
# Rocked, he also catches himself: the skates splay and he sits into them for as
# long as he is rocked. That part rides a spring (EaseRules) so the legs step
# out over a few frames instead of in one, and back in as he comes out of it.

var _catch: float = 0.0
var _catch_rate: float = 0.0


func stages() -> int:
	return Stage.FLOOR | Stage.TRUNK


func reset() -> void:
	_catch = 0.0
	_catch_rate = 0.0


func is_quiet() -> bool:
	return _controller.stagger_timer <= 0.0


func advance(delta: float) -> bool:
	var target: float = 1.0 if _controller.rocked_share() > 0.0 else 0.0
	var omega: float = _controller.rocked_catch_rate * EaseRules.OMEGA_PER_RATE
	var x: float = _catch
	_catch = maxf(EaseRules.critical_x(x, _catch_rate, target, omega, delta), 0.0)
	_catch_rate = EaseRules.critical_v(x, _catch_rate, target, omega, delta)
	return _controller.stagger_timer > 0.0 or _catch > 0.001


func stance_floor() -> float:
	return _controller.rocked_crouch * _catch


func stance_width() -> float:
	return _controller.rocked_splay_m * _catch


func shape_trunk(p: GaitPose) -> void:
	var t: float = clampf(
			_controller.stagger_timer / maxf(_controller.stagger_max_seconds, 0.001), 0.0, 1.0)
	if t <= 0.0:
		return
	var amp: float = deg_to_rad(_controller.stagger_wobble_deg) * t
	var phase: float = _controller.stagger_timer * TAU * _controller.stagger_wobble_hz
	p.wobble_pitch = amp * sin(phase)
	p.wobble_roll = amp * 0.7 * sin(phase * 1.31)
