class_name AICarrierPassTrace

# An instrument's per-receiver record of the carrier's last pass search, filled
# only while an AICarrierPassSearch holds one (its `trace`): each teammate's peer
# id, his feed's EV before it is floored at 0 (so a feed worse than keeping the
# puck reads negative; -1 when he is filtered before pricing, out of play or
# outside a zone we hold), the full-pace flat lane, his spot's worth with the
# puck (AICarrierField.receiver_value_at), and the Gate that zeroed the
# full-pace feed. With a trace held, no receiver is pruned, so every EV is the
# honest one; the prune is exact, so the search's pick is unchanged.

enum Gate { PRICED, LEAD_PAST_GOAL_LINE, LEAD_OUT_OF_ZONE, ENTRY_BLOCKED,
		SOFT_TOO_LONG, THROUGH_NET, ACROSS_OWN_SLOT, LANE_CLOSED }

var peer: Array[int] = []
var ev: Array[float] = []
var lane: Array[float] = []
var worth: Array[float] = []
var gate: Array[int] = []


func clear() -> void:
	peer.clear()
	ev.clear()
	lane.clear()
	worth.clear()
	gate.clear()


func record(peer_id: int, feed_ev: float, flat_lane: float, spot_worth: float,
		stopped_at: int) -> void:
	peer.append(peer_id)
	ev.append(feed_ev)
	lane.append(flat_lane)
	worth.append(spot_worth)
	gate.append(stopped_at)
