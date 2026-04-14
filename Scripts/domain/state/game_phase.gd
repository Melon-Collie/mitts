class_name GamePhase

# Domain enum for the game's phase FSM. Lives in the domain layer so rules and
# the eventual GameStateMachine can reference it without going through
# GameManager.
#
# Usage: `GamePhase.Phase.PLAYING` from anywhere in the project.

enum Phase {
	PLAYING,        # normal gameplay
	GOAL_SCORED,    # dead puck, celebration freeze
	FACEOFF_PREP,   # players teleporting, puck resetting
	FACEOFF,        # puck live at center, waiting for pickup or timeout
	END_OF_PERIOD,  # clock hit zero; brief pause before next-period faceoff
	GAME_OVER,      # all periods done; locked until manual reset
}
