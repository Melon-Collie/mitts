class_name GaitCelebrationLayer
extends GaitLayer

# The celebration bounce: the knees pump between straight and seated (the body
# drop follows, so it reads as a hop bob) — 3 pumps across the window, double
# the raised-stick pose's bob rate. Gated to plain skating like that pose
# (SkaterController's celebration block) so it never fights a follow-through
# kick, and ramped in over the same first 20%.
#
# This pass runs at render rate and is visibility-gated, so the layer only
# READS the progress: the callers age the timer at physics rate
# (SkaterController._process_input / RemoteController._physics_process), which
# keeps it deterministic and never frozen off-screen.

const State = SkaterStateMachine.State


func stages() -> int:
	return Stage.FLOOR


func is_quiet() -> bool:
	return _controller.celebration_progress() <= 0.0


func advance(_delta: float) -> bool:
	return _controller.celebration_progress() > 0.0


func stance_floor() -> float:
	var progress: float = _controller.celebration_progress()
	var state: int = _skater.current_shot_state
	if progress <= 0.0 or (state != State.SKATING_WITH_PUCK
			and state != State.SKATING_WITHOUT_PUCK):
		return 0.0
	var ramp: float = clampf(progress / 0.2, 0.0, 1.0)
	ramp = ramp * ramp * (3.0 - 2.0 * ramp)
	var pump: float = 0.5 - 0.5 * cos(progress * TAU * 3.0)
	return _controller.celebration_leg_stance * ramp * pump
