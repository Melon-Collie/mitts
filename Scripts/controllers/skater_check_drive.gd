class_name SkaterCheckDrive
extends RefCounted

# The skater's timed-check phase (CheckDriveRules). Owns both fields outright:
# the controller steps it from inputs every tick and the local reconcile adopts
# the host's pair before replaying, the same rail as the stick lift's.

var phase: int = CheckDriveRules.Phase.IDLE
var elapsed: float = 0.0


func advance(held: bool, eligible: bool, delta: float) -> void:
	var next: Vector2 = CheckDriveRules.step(phase, elapsed, held, eligible, delta)
	phase = int(next.x)
	elapsed = next.y


func adopt(wire_phase: int, wire_elapsed: float) -> void:
	phase = wire_phase
	elapsed = wire_elapsed


func reset() -> void:
	phase = CheckDriveRules.Phase.IDLE
	elapsed = 0.0
