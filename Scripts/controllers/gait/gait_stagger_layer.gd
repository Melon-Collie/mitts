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


func stages() -> int:
	return Stage.TRUNK


func is_quiet() -> bool:
	return _controller.stagger_timer <= 0.0


func advance(_delta: float) -> bool:
	return _controller.stagger_timer > 0.0


func shape_trunk(p: GaitPose) -> void:
	var t: float = clampf(
			_controller.stagger_timer / maxf(_controller.stagger_max_seconds, 0.001), 0.0, 1.0)
	if t <= 0.0:
		return
	var amp: float = deg_to_rad(_controller.stagger_wobble_deg) * t
	var phase: float = _controller.stagger_timer * TAU * _controller.stagger_wobble_hz
	p.wobble_pitch = amp * sin(phase)
	p.wobble_roll = amp * 0.7 * sin(phase * 1.31)
