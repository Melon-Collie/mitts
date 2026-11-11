class_name ShotStateAuthority
extends RefCounted

# Whether reconcile overwrites the client's live shot state with the host's.
#
# The host's state is the one at the ack, a whole unacked window behind the
# client, so a difference is usually the client already having done what the
# host has not processed yet. The replay settles most of it: run from the
# host's state through the same unacked inputs, it lands where the host will.
# When that is the live state, the host's is only late and never applies. When
# it is not, the guards hold the in-flight transitions the replay cannot
# reproduce (the shooter's timers ride no wire), and anything else is a real
# divergence the host wins.

const State = SkaterStateMachine.State


static func server_applies(server: State, live: State, replayed: State,
		has_puck: bool, slapshot_pinning: bool) -> bool:
	if server == live or replayed == live:
		return false
	match live:
		# The release already went out; a server still winding up is lag.
		State.FOLLOW_THROUGH:
			if server == State.WRISTER_AIM or server == State.SLAPPER_CHARGE_WITH_PUCK \
					or server == State.SLAPPER_CHARGE_WITHOUT_PUCK \
					or server == State.ONE_TIMER_RETENTION:
				return false
		# Client-owned outright: the hold self-terminates within
		# one_timer_retention_time.
		State.ONE_TIMER_RETENTION:
			return false
		# The shoot press is in flight to the host. Gated on the puck so a steal
		# (which clears it before the next reconcile) still overrides.
		State.WRISTER_AIM, State.SLAPPER_CHARGE_WITH_PUCK:
			if has_puck and (server == State.SKATING_WITH_PUCK
					or server == State.SKATING_WITHOUT_PUCK):
				return false
		# The puckless wind-up's slap press is in flight.
		State.SLAPPER_CHARGE_WITHOUT_PUCK:
			if server == State.SKATING_WITHOUT_PUCK:
				return false
		# A slapshot called off, through the recovery that follows: the button is
		# already up, so the host's wind-up re-armed here would fire one. Bounded
		# by the recovery's pin.
		State.SKATING_WITH_PUCK:
			if server == State.SLAPPER_CHARGE_WITH_PUCK and slapshot_pinning:
				return false
	return true
