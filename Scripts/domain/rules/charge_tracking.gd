class_name ChargeTracking

# Tracks the wrister STROKE — its accumulated blade travel and the "setting up"
# reset — from the cursor (intent) delta and the shot-line bearing. Power is NOT
# tracked here: it's the raw cursor speed (SkaterAimingBehavior.cursor_speed_ema).
# The hand isn't either: WristerLoad reads it from where the puck sits against
# the aim. What this answers is "how much blade path has this stroke actually
# swept" (the travel that gates the power CEILING — see
# ShotMechanics.wrister_travel_cap_t, currently dormant) and "did the player
# break their stroke".
#
#   - DIRECTION & variance check: derived from the cursor (intent) delta.
#     The intent_pos is conventionally screen space (pixel position
#     packed as Vector3(x, 0, y)), which is the camera-immune frame —
#     pixel motion captures the player's mouse drag intent independent
#     of camera lag, body rotation, or skater locomotion. World-space
#     intent leaks transient bias from camera-follow lag during brakes
#     and direction changes; screen-space doesn't.
#
# Resets the stroke when the cursor's direction of motion changes by more
# than max_direction_variance_deg — models the player "setting up" the shot:
# a straight drag holds one stroke; a zig-zag starts a fresh one.
#
# STROKE TRAVEL: the accumulated XZ path length (meters) of the shot-line bearing
# (cursor − swing_anchor below) over the stroke. Measured in that anchored frame
# so locomotion doesn't bank travel; it only accrues on ticks with real cursor
# intent and resets to zero on a variance break. Each tick's contribution is
# capped at max_travel_step: the blade TARGET is a closed-form ROM clamp (not the
# speed-capped smoothed blade), so a forged or teleporting cursor could
# otherwise bank a whole arc of travel in one tick. Callers pass their on-axis
# blade-speed budget × delta.
#
# Reusable output of accumulate_into (below) — a caller-owned scratch so the
# per-tick wrister-charge path allocates nothing (see SkaterAimingBehavior).
#   - direction: the most recent meaningful cursor-motion unit vector.
#     Caller passes this as prev_direction next tick. Vector3.ZERO means
#     "no direction yet recorded" (first frame or negligible cursor motion).
#   - reset: true when the direction-variance break fired this tick — a NEW
#     stroke started.
#   - travel: accumulated XZ path length (meters) of the anchored bearing over
#     the stroke; feed to ShotMechanics.wrister_travel_cap_t at release.
class Result:
	var direction: Vector3 = Vector3.ZERO
	var reset: bool = false
	var travel: float = 0.0


# Core accumulation — fills the caller-owned `out` instead of returning a fresh
# Dictionary, so the 120 Hz wrister-charge path (and its reconcile-replay re-runs)
# don't churn the heap. `accumulate` below wraps this for the tests / any caller
# that wants a plain Dictionary.
static func accumulate_into(
		out: Result,
		prev_intent_pos: Vector3,
		current_intent_pos: Vector3,
		prev_blade_pos: Vector3,
		current_blade_pos: Vector3,
		prev_direction: Vector3,
		max_direction_variance_deg: float,
		current_travel: float = 0.0,
		max_travel_step: float = INF) -> void:
	var intent_delta := current_intent_pos - prev_intent_pos
	intent_delta.y = 0.0
	var intent_dist: float = intent_delta.length()
	if intent_dist <= 0.001:
		# Cursor not moving — no drag intent this tick. Hold direction and travel
		# unchanged regardless of what the blade did (e.g., locomotion-induced
		# blade motion doesn't extend the stroke without intent).
		out.direction = prev_direction
		out.reset = false
		out.travel = current_travel
		return

	var current_dir: Vector3 = intent_delta.normalized()
	var new_travel: float = current_travel
	var was_reset: bool = false
	if prev_direction != Vector3.ZERO:
		var angle_deg: float = rad_to_deg(prev_direction.angle_to(current_dir))
		if angle_deg > max_direction_variance_deg:
			new_travel = 0.0
			was_reset = true

	new_travel += travel_step(prev_blade_pos, current_blade_pos, max_travel_step)

	out.direction = current_dir
	out.reset = was_reset
	out.travel = new_travel


# Dictionary-returning wrapper over accumulate_into. Kept for tests and any
# caller that doesn't hold a Result scratch. Returns { "direction", "reset",
# "travel" }.
static func accumulate(
		prev_intent_pos: Vector3,
		current_intent_pos: Vector3,
		prev_blade_pos: Vector3,
		current_blade_pos: Vector3,
		prev_direction: Vector3,
		max_direction_variance_deg: float,
		current_travel: float = 0.0,
		max_travel_step: float = INF) -> Dictionary:
	var r := Result.new()
	accumulate_into(r, prev_intent_pos, current_intent_pos,
			prev_blade_pos, current_blade_pos, prev_direction,
			max_direction_variance_deg, current_travel, max_travel_step)
	return {"direction": r.direction, "reset": r.reset, "travel": r.travel}


# Anchor the travel bearing is measured from this tick. The wrister's aim
# origin is pinned in WORLD space, but the travel read wants the player's
# GESTURE, and the right frame depends on where the device's cursor lives:
#   - cursor_world_anchored (the gamepad shot cursor, re-anchored every frame on
#     the pinned origin's screen projection): the world-pinned origin already
#     isolates the gesture — returned unchanged.
#   - camera-framed cursor (the mouse: a screen point ray-projected through a
#     camera that follows the skater): locomotion translates the cursor's world
#     point while a world-pinned anchor stays put, so skating would bank travel
#     nobody gestured. Translating the anchor by the skater's motion since the
#     pin (the camera tracks the skater) cancels the drift and leaves only the
#     gesture.
# XZ only (drift y flattened), like the bearings it anchors.
static func swing_anchor(origin_world: Vector3, skater_pos: Vector3,
		skater_pos_at_pin: Vector3, cursor_world_anchored: bool) -> Vector3:
	if cursor_world_anchored:
		return origin_world
	var drift := skater_pos - skater_pos_at_pin
	drift.y = 0.0
	return origin_world + drift


# Blade XZ path-length step (meters) from `prev_rel` to `curr_rel`, capped at
# max_step (the caller's per-tick blade-speed budget — bounds what a single
# tick can bank against target teleports). Pure XZ (y ignored).
static func travel_step(prev_rel: Vector3, curr_rel: Vector3, max_step: float = INF) -> float:
	var d := curr_rel - prev_rel
	d.y = 0.0
	return minf(d.length(), max_step)
