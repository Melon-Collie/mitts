class_name BufferedStateInterpolator

# Shared interpolation helper for PuckController / RemoteController /
# GoalieController. All three buffer timestamped network-state snapshots
# and interpolate between bracketing pairs; this class collapses the bracket
# search and stale-trim logic into one place. The per-field lerp stays in
# each controller because each state type has its own field mix.
#
# Buffer element contract (duck-typed): { timestamp: float, state }.

class BracketResult:
	var from_state: Variant = null
	var to_state: Variant = null
	var t: float = 0.0            # clamped [0, 1]; 1.0 when extrapolating
	var is_extrapolating: bool = false
	var extrapolation_dt: float = 0.0  # seconds past the newest snapshot
	var bracket_dt: float = 0.0   # time span between from and to snapshots

# Returns a BracketResult locating render_time within the buffer, or null if
# the buffer is empty or render_time hasn't reached the oldest entry yet.
# When render_time overshoots the newest snapshot, returns is_extrapolating=true
# with extrapolation_dt set so callers can dead-reckon with the newest velocity.
# Works with a single-entry buffer for the extrapolation case.
static func find_bracket(buffer: Array, render_time: float) -> BracketResult:
	if buffer.is_empty():
		return null
	var newest = buffer[buffer.size() - 1]
	if render_time > newest.timestamp:
		var r := BracketResult.new()
		r.from_state = newest.state
		r.to_state = newest.state
		r.t = 1.0
		r.is_extrapolating = true
		r.extrapolation_dt = render_time - newest.timestamp
		return r
	if buffer.size() < 2:
		# Only one snapshot and render_time is behind it — display it directly
		# rather than holding at the spawn position until a second arrives.
		var r := BracketResult.new()
		r.from_state = newest.state
		r.to_state = newest.state
		r.t = 0.0
		r.is_extrapolating = false
		r.bracket_dt = 0.0
		return r
	for i in range(buffer.size() - 1):
		var a = buffer[i]
		var b = buffer[i + 1]
		if a.timestamp <= render_time and render_time <= b.timestamp:
			return _make(a, b, render_time)
	return null

# Drops stale buffer entries; keeps at least min_keep at the tail so the next
# tick still has material to bracket against.
static func drop_stale(buffer: Array, render_time: float, min_keep: int = 2) -> void:
	while buffer.size() > min_keep and buffer[1].timestamp < render_time:
		buffer.pop_front()

static func hermite(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, t: float, dt: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return (2.0*t3 - 3.0*t2 + 1.0) * p0 \
		 + (t3 - 2.0*t2 + t) * dt * v0 \
		 + (-2.0*t3 + 3.0*t2) * p1 \
		 + (t3 - t2) * dt * v1

static func lerp_facing(from: Vector2, to: Vector2, t: float) -> Vector2:
	var a := lerp_angle(atan2(from.x, from.y), atan2(to.x, to.y), t)
	return Vector2(sin(a), cos(a))

# Cubic Hermite interpolation for scalar angles (radians).
# a0/a1: endpoint angles; av0/av1: angular velocities at each endpoint (rad/s).
# t: normalized [0,1]; dt: bracket time span (seconds).
# Safe as long as |av| < π/dt — always satisfied at hockey rotation speeds.
static func hermite_angle(a0: float, av0: float, a1: float, av1: float, t: float, dt: float) -> float:
	var t2: float = t * t
	var t3: float = t2 * t
	return (2.0*t3 - 3.0*t2 + 1.0) * a0 \
		 + (t3 - 2.0*t2 + t) * dt * av0 \
		 + (-2.0*t3 + 3.0*t2) * a1 \
		 + (t3 - t2) * dt * av1

static func _make(a, b, render_time: float) -> BracketResult:
	var r := BracketResult.new()
	r.from_state = a.state
	r.to_state = b.state
	var span: float = b.timestamp - a.timestamp
	r.t = clampf((render_time - a.timestamp) / span, 0.0, 1.0) if span > 0.0 else 0.0
	r.bracket_dt = span
	return r
