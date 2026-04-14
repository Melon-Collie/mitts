class_name PhaseRules

# Pure rules about game phases — which phases suppress movement, which are
# "dead puck" (cosmetic freeze / position reset). Extracted from GameManager
# so controllers and tests can ask these questions without reaching into
# the orchestrator.

# Phases during which player movement and input are suppressed.
static func is_dead_puck_phase(phase: GamePhase.Phase) -> bool:
	return phase == GamePhase.Phase.GOAL_SCORED or phase == GamePhase.Phase.FACEOFF_PREP

# Convenience: same as is_dead_puck_phase for the given phase.
static func movement_locked(phase: GamePhase.Phase) -> bool:
	return is_dead_puck_phase(phase)
