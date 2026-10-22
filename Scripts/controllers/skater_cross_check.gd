class_name SkaterCrossCheck
extends RefCounted

# The skater's cross-check phase (CrossCheckRules) and the aim its throw was
# pressed with. Owns all three fields outright: the controller steps them from
# inputs every tick and the local reconcile adopts the host's phase pair before
# replaying, the same rail as SkaterStickCheck.

var phase: int = CrossCheckRules.Phase.IDLE
var elapsed: float = 0.0
# Unit XZ, latched on the press that throws (CrossCheckRules.aim_dir): the push
# goes where the shover aimed it, wherever the cursor goes after.
var aim: Vector2 = Vector2.ZERO


func advance(pressed: bool, can_start: bool, interrupted: bool, aim_now: Vector2,
		delta: float) -> void:
	var next: Vector2 = CrossCheckRules.step(phase, elapsed, pressed, can_start,
			interrupted, delta)
	if phase == CrossCheckRules.Phase.IDLE and int(next.x) == CrossCheckRules.Phase.THROW:
		aim = aim_now
	phase = int(next.x)
	elapsed = next.y


func adopt(wire_phase: int, wire_elapsed: float) -> void:
	phase = wire_phase
	elapsed = wire_elapsed


func reset() -> void:
	phase = CrossCheckRules.Phase.IDLE
	elapsed = 0.0
	aim = Vector2.ZERO
