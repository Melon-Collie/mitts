class_name SkaterCrossCheck
extends RefCounted

# The skater's cross-check phase (CrossCheckRules). Owns both fields outright: the
# controller steps it from inputs every tick and the local reconcile adopts the
# host's pair before replaying, the same rail as SkaterStickCheck.

var phase: int = CrossCheckRules.Phase.IDLE
var elapsed: float = 0.0


func advance(pressed: bool, can_start: bool, interrupted: bool, delta: float) -> void:
	var next: Vector2 = CrossCheckRules.step(phase, elapsed, pressed, can_start,
			interrupted, delta)
	phase = int(next.x)
	elapsed = next.y


func adopt(wire_phase: int, wire_elapsed: float) -> void:
	phase = wire_phase
	elapsed = wire_elapsed


func reset() -> void:
	phase = CrossCheckRules.Phase.IDLE
	elapsed = 0.0
