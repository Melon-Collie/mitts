class_name GoaliePassRead

# Where a pass in flight will be SHOT from.
#
# A pass is not a threat to the net; the stick it is travelling to is. So the
# goalie reads the puck's line, finds the first opposing blade that line reaches,
# and plays the one-timer from THERE — squared to the reception, not to a puck
# that is only passing through. This is the ball-flight read every goalie makes
# on a pass-out from behind the net or a feed across the slot, and it is a read
# of the line, not a guess about intent: a pass that misses every stick reads as
# nothing.
#
# Planar (XZ) and straight-line: a pass is a sliding puck, and a skater a stick
# length from its line can reach it. The receiver's own skating is ignored —
# the read is re-run every tick, so a receiver closing on the line is picked up
# the tick the line reaches him.
#
# Pure/static. The caller owns the Reception scratch (filled in place).

class Reception:
	var found: bool = false
	# Where the puck first comes within the receiver's stick reach, on its line.
	var point: Vector3 = Vector3.ZERO
	# Seconds until it gets there.
	var time: float = INF


# First opposing stick the puck's line reaches, within `max_time`. Fills `out`
# and returns whether one was found.
static func find_reception(puck_pos: Vector3, puck_vel: Vector3,
		receivers: PackedVector3Array, stick_reach: float, max_time: float,
		out: Reception) -> bool:
	out.found = false
	out.time = INF
	var speed_sq: float = puck_vel.x * puck_vel.x + puck_vel.z * puck_vel.z
	if speed_sq < 0.0001:
		return false
	var speed: float = sqrt(speed_sq)
	var reach_sq: float = stick_reach * stick_reach
	for r: Vector3 in receivers:
		var rx: float = r.x - puck_pos.x
		var rz: float = r.z - puck_pos.z
		var t_closest: float = (rx * puck_vel.x + rz * puck_vel.z) / speed_sq
		if t_closest <= 0.0:
			continue   # behind the puck — the pass is leaving him
		var mx: float = rx - puck_vel.x * t_closest
		var mz: float = rz - puck_vel.z * t_closest
		var miss_sq: float = mx * mx + mz * mz
		if miss_sq > reach_sq:
			continue   # the line never comes within his stick
		# Enters the reach circle before the closest approach.
		var t_touch: float = maxf(t_closest - sqrt(reach_sq - miss_sq) / speed, 0.0)
		if t_touch > max_time or t_touch >= out.time:
			continue
		out.found = true
		out.time = t_touch
		out.point = Vector3(puck_pos.x + puck_vel.x * t_touch, puck_pos.y,
				puck_pos.z + puck_vel.z * t_touch)
	return out.found
