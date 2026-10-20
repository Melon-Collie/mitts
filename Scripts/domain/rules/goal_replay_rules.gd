class_name GoalReplayRules

# What a post-goal replay shows: where the clip starts, where its slow motion
# lands, and where the behind-the-goal camera stands. Everything is anchored on
# the goal — the clip's last frame, the one moment the replay is certain of —
# and on the scoring touch, the last skater contact before it. Events are the
# recorder's { event: { kind, pos, ... }, host_ts } pairs in ascending host_ts.

# A skater's stick or body moving the puck. Goalie, post, board and net-frame
# contacts shape a finish but are nobody's touch, so a puck that rings around
# the boards and in is anchored on whoever last played it, not on the boards.
const _SCORING_TOUCH_KINDS: Array[String] = [
	"shot", "nudge", "puck_deflection", "puck_body_block", "puck_strip", "puck_pickup",
]
# The decisive touches of a net-front scramble: when one precedes the scoring
# touch, the clip opens on the last of them instead of the whole pile-up.
const _CONTEST_KINDS: Array[String] = [
	"body_check", "stick_lift", "puck_strip", "puck_deflection",
]

# Clip start (seconds, game time).
const PICKUP_CHAIN_GAP: float = 2.0         # max gap between pickups still in one passing chain
const PRE_PICKUP_BUFFER: float = 0.5        # shown before the earliest chained pickup
const PRE_CONTEST_BUFFER: float = 0.75      # shown before the last contest when it cuts the clip
const MIN_PRE_TOUCH: float = 1.5            # floor when the chain captured pickups, or none exist
const MIN_PRE_TOUCH_LONG_CARRY: float = 3.0 # floor for a lone carry that began outside the chain
const MAX_PRE_TOUCH: float = 6.5

# Slow motion (seconds, game time). The budget is what keeps a bouncer from
# playing its whole trip at quarter speed: at most the last SLOWMO_MAX_SPAN of
# the clip, however long ago the scoring touch was.
const SLOWMO_SPEED: float = 0.4
const SLOWMO_LEAD: float = 0.3      # wind-up shown slowed before the scoring touch
const SLOWMO_MIN_SPAN: float = 0.5  # a point-blank tap still gets a readable slowed beat
const SLOWMO_MAX_SPAN: float = 1.0  # 2.5 s on screen at SLOWMO_SPEED
const SLOWMO_RAMP: float = 0.15     # ease from full speed into slow motion

# Behind-the-goal camera: on the glass inside the end boards, high enough to see
# over the crossbar to the slot and over skaters circling behind the net.
const NET_CAM_BEHIND_GOAL_LINE: float = 2.3
const NET_CAM_HEIGHT: float = 2.6
const NET_CAM_BOARD_MARGIN: float = 0.5
const NET_CAM_LATERAL_SCALE: float = 0.35  # mirrors the touch across the net so its path crosses frame
const NET_CAM_MAX_LATERAL: float = 3.0
# The cut waits until the puck is this close to the goal: from behind the net, a
# puck farther out is a dot.
const NET_CAM_CUT_RANGE: float = 15.0
# The camera frames the goal mouth rather than following the puck over the line
# into the net, which from 2 m away would whip the view straight down.
const NET_CAM_MIN_LOOK_DEPTH: float = 1.0


# Index of the last scoring touch at or before goal_ts, or -1 when the clip has
# none (a puck that only ever met goalies and boards on camera).
static func scoring_touch_index(events: Array[Dictionary], goal_ts: float) -> int:
	for i: int in range(events.size() - 1, -1, -1):
		var entry: Dictionary = events[i]
		if float(entry.host_ts) > goal_ts:
			continue
		if _is_kind(entry, _SCORING_TOUCH_KINDS):
			return i
	return -1


# Where the scoring play opens, given the moment it is anchored on (the scoring
# touch, or the goal when there is none). Two candidates, whichever sits closer
# to the anchor wins, so a late scramble touch shortens the clip rather than the
# possession chain dragging it back through the whole pile-up:
#   - the pickup-chain possession start (passing plays, a long carry), and
#   - the last contest before the anchor.
# Clamped to [anchor - MAX_PRE_TOUCH, anchor - MIN_PRE_TOUCH].
static func clip_start_ts(events: Array[Dictionary], anchor_ts: float) -> float:
	var play_start: float = _pickup_chain_start_ts(events, anchor_ts)
	var contest_ts: float = _last_event_before(events, anchor_ts, _CONTEST_KINDS)
	if contest_ts >= 0.0:
		play_start = maxf(play_start, contest_ts - PRE_CONTEST_BUFFER)
	return clampf(play_start, anchor_ts - MAX_PRE_TOUCH, anchor_ts - MIN_PRE_TOUCH)


# Game time the slow motion begins: just before the scoring touch, but never
# more than SLOWMO_MAX_SPAN before the goal. touch_ts < 0 means no touch, which
# slows only the last SLOWMO_MAX_SPAN.
static func slowmo_start_ts(touch_ts: float, goal_ts: float) -> float:
	if touch_ts < 0.0:
		return goal_ts - SLOWMO_MAX_SPAN
	return clampf(touch_ts - SLOWMO_LEAD, goal_ts - SLOWMO_MAX_SPAN, goal_ts - SLOWMO_MIN_SPAN)


# Playback rate at game time `clock`: full speed, easing to SLOWMO_SPEED over
# SLOWMO_RAMP from slowmo_start.
static func playback_speed(clock: float, slowmo_start: float) -> float:
	var t: float = smoothstep(slowmo_start, slowmo_start + SLOWMO_RAMP, clock)
	return lerpf(1.0, SLOWMO_SPEED, t)


# The behind-the-goal camera for a goal whose line sits at goal_line_z, mirrored
# across the net from the scoring touch's x.
static func net_cam_position(goal_line_z: float, touch_x: float) -> Vector3:
	var z_sign: float = signf(goal_line_z)
	var lateral: float = clampf(-touch_x * NET_CAM_LATERAL_SCALE,
			-NET_CAM_MAX_LATERAL, NET_CAM_MAX_LATERAL)
	var xz := Vector2(lateral, goal_line_z + z_sign * NET_CAM_BEHIND_GOAL_LINE)
	xz = GameRules.clamp_to_rink_inner(xz, NET_CAM_BOARD_MARGIN)
	return Vector3(xz.x, NET_CAM_HEIGHT, xz.y)


# What the behind-the-goal camera aims at: the puck, held at the goal mouth
# once it crosses the line.
static func net_cam_look_target(puck_pos: Vector3, goal_line_z: float) -> Vector3:
	var z_sign: float = signf(goal_line_z)
	var frame_z: float = goal_line_z - z_sign * NET_CAM_MIN_LOOK_DEPTH
	if (puck_pos.z - frame_z) * z_sign > 0.0:
		puck_pos.z = frame_z
	return puck_pos


# The pickup-chain possession start. Three cases:
#   - pickups within PICKUP_CHAIN_GAP of each other (passing plays) extend the
#     clip back to PRE_PICKUP_BUFFER before the earliest of them;
#   - a lone pickup well before the anchor (a long carry) floors the clip at
#     MIN_PRE_TOUCH_LONG_CARRY rather than showing the whole carry;
#   - no pickup at all floors it at MIN_PRE_TOUCH.
static func _pickup_chain_start_ts(events: Array[Dictionary], anchor_ts: float) -> float:
	var play_start: float = anchor_ts
	var prev_ts: float = anchor_ts
	var has_any_pickup: bool = false
	for i: int in range(events.size() - 1, -1, -1):
		var entry: Dictionary = events[i]
		var ts: float = entry.host_ts
		if ts >= anchor_ts or not _is_kind_named(entry, "puck_pickup"):
			continue
		has_any_pickup = true
		if prev_ts - ts > PICKUP_CHAIN_GAP:
			break
		play_start = ts
		prev_ts = ts
	if play_start == anchor_ts:
		return anchor_ts - (MIN_PRE_TOUCH_LONG_CARRY if has_any_pickup else MIN_PRE_TOUCH)
	return play_start - PRE_PICKUP_BUFFER


# Timestamp of the last event of one of `kinds` strictly before anchor_ts, or
# -1.0 when there is none.
static func _last_event_before(events: Array[Dictionary], anchor_ts: float,
		kinds: Array[String]) -> float:
	for i: int in range(events.size() - 1, -1, -1):
		var entry: Dictionary = events[i]
		var ts: float = entry.host_ts
		if ts < anchor_ts and _is_kind(entry, kinds):
			return ts
	return -1.0


static func _is_kind(entry: Dictionary, kinds: Array[String]) -> bool:
	var ev: Dictionary = entry.event
	return ev.has("kind") and kinds.has(String(ev.kind))


static func _is_kind_named(entry: Dictionary, kind: String) -> bool:
	var ev: Dictionary = entry.event
	return ev.has("kind") and ev.kind == kind
