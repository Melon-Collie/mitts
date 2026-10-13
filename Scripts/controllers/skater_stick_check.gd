class_name SkaterStickCheck
extends RefCounted

# The skater's stick-lift phase (StickCheckRules). Owns both fields outright: the
# controller steps it from inputs every tick and the local reconcile adopts the
# host's pair before replaying, the same rail as stagger_timer.

var phase: int = StickCheckRules.Phase.IDLE
var elapsed: float = 0.0


func advance(pressed: bool, held: bool, can_start: bool, interrupted: bool,
		delta: float) -> void:
	var next: Vector2 = StickCheckRules.step(
			phase, elapsed, pressed, held, can_start, interrupted, delta)
	phase = int(next.x)
	elapsed = next.y


func adopt(wire_phase: int, wire_elapsed: float) -> void:
	phase = wire_phase
	elapsed = wire_elapsed


func reset() -> void:
	phase = StickCheckRules.Phase.IDLE
	elapsed = 0.0
