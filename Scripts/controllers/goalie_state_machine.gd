class_name GoalieStateMachine
extends RefCounted

# The goalie's stance as the wire carries it (GoalieNetworkState.state_enum)
# and the bots and the pad sounds read it. The keeper sets it from his rest
# (KeeperController._stance): READY on his feet, BUTTERFLY down, RVH_* on a
# post. The rest are the old goalie's, kept because the numeric values ride
# the wire as a u8, so states are only ever APPENDED — reordering silently
# re-labels every goalie on every client.
enum State {
	STANDING, BUTTERFLY, RECOVERING, RVH_LEFT, RVH_RIGHT, READY, SLIDING, COILING,
	VH_LEFT, VH_RIGHT, COVERING, PLAYING_PUCK, CATCHING, CATCHING_DOWN,
	HALF_BUTTERFLY_LEFT, HALF_BUTTERFLY_RIGHT,
}

var current: State = State.STANDING


# Pads flat on the ice: both in every full-down stance (the post seals and the
# cover included), one in a half butterfly. RECOVERING counts as up — the legs
# are already rising off the ice.
static func pads_on_ice(state: State) -> int:
	match state:
		State.BUTTERFLY, State.SLIDING, State.COILING, State.RVH_LEFT, State.RVH_RIGHT, \
				State.VH_LEFT, State.VH_RIGHT, State.COVERING, State.CATCHING_DOWN:
			return 2
		State.HALF_BUTTERFLY_LEFT, State.HALF_BUTTERFLY_RIGHT:
			return 1
	return 0


# On his feet, set to make a save from: STANDING or READY.
func is_upright() -> bool:
	return current == State.STANDING or current == State.READY
