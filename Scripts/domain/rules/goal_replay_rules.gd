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
# The decisive touches of a net-front scramble: when one follows the play's last
# pickup, the clip opens on the last of them instead of the whole pile-up.
const _CONTEST_KINDS: Array[String] = [
	"body_check", "stick_lift", "puck_strip", "puck_deflection",
]

# Clip start (seconds, game time). The clip walks back through the scoring
# team's possession, one pickup at a time, keeping a pickup only while the link
# from it is worth watching: a quick pass (tic-tac-toe, a cycle) or a rush that
# carried the puck up ice (an outlet into a 2-on-1, coast to coast). A turnover
# or a slow regroup ends the play.
const QUICK_LINK: float = 2.0             # a pass or short carry this fast is always the play
const RUSH_LINK_MAX: float = 6.0          # a link up to this long is the play if it was a rush...
const RUSH_ADVANCE: float = 15.0          # ...gaining this many metres toward the net (≈ a zone)
const PRE_PICKUP_BUFFER: float = 0.5      # shown before the play's first pickup
const PRE_CONTEST_BUFFER: float = 0.75    # shown before the last contest when it cuts the clip
const MIN_PRE_TOUCH: float = 1.5          # floor when nothing before the touch is the play
const MIN_PRE_TOUCH_LONG_CARRY: float = 3.0  # floor for a slow carry that isn't the play
const MAX_PRE_TOUCH: float = 10.0

# Slow motion (seconds, game time). The budget is what keeps a bouncer from
# playing its whole trip at quarter speed: at most the last SLOWMO_MAX_SPAN of
# the clip, however long ago the scoring touch was.
const SLOWMO_SPEED: float = 0.4
const SLOWMO_LEAD: float = 0.3      # wind-up shown slowed before the scoring touch
const SLOWMO_MIN_SPAN: float = 0.5  # a point-blank tap still gets a readable slowed beat
const SLOWMO_MAX_SPAN: float = 1.0  # 2.5 s on screen at SLOWMO_SPEED
const SLOWMO_RAMP: float = 0.15     # ease from full speed into slow motion
# Game time the clip runs past the goal, still slowed: the puck meeting the net.
const POST_GOAL_TAIL: float = 0.5

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


# Index of the scoring team's last touch at or before goal_ts. A goal that team
# never touched on camera (an own goal) falls back to anyone's last touch; -1
# when the clip has none at all (a puck that only met goalies and boards).
static func scoring_touch_index(events: Array[Dictionary], goal_ts: float,
		scoring_team: int) -> int:
	var any_touch: int = -1
	for i: int in range(events.size() - 1, -1, -1):
		var entry: Dictionary = events[i]
		if float(entry.host_ts) > goal_ts or not _is_kind(entry, _SCORING_TOUCH_KINDS):
			continue
		var ev: Dictionary = entry.event
		if int(ev.get("team", -1)) == scoring_team:
			return i
		if any_touch == -1:
			any_touch = i
	return any_touch


# Where the scoring play opens, given the moment it is anchored on (the scoring
# touch, or the goal when there is none) and where that was. The play is
# `team`'s possession (-1: whoever made the last pickup). attack_sign is the
# sign of the scored-on goal's z — the direction a rush gains ground; 0 counts
# only quick links. A contest after the play's last pickup (a net-front
# scramble) opens the clip on that contest instead. Clamped to
# [anchor - MAX_PRE_TOUCH, anchor - MIN_PRE_TOUCH].
static func clip_start_ts(events: Array[Dictionary], anchor_ts: float,
		anchor_z: float, attack_sign: float, team: int) -> float:
	var play_start: float = anchor_ts - MIN_PRE_TOUCH
	var link_ts: float = anchor_ts
	var link_z: float = anchor_z
	var chain_team: int = team if team >= 0 else -2  # -2: take the last pickup's team
	var first_pickup_ts: float = -1.0
	var last_pickup_ts: float = -1.0
	var saw_pickup: bool = false
	for i: int in range(events.size() - 1, -1, -1):
		var entry: Dictionary = events[i]
		var ts: float = entry.host_ts
		if ts >= anchor_ts or not _is_kind_named(entry, "puck_pickup"):
			continue
		saw_pickup = true
		var ev: Dictionary = entry.event
		var pickup_team: int = int(ev.get("team", -1))
		if chain_team == -2:
			chain_team = pickup_team
		elif pickup_team != chain_team:
			break
		var pos: Array = ev.pos
		var z: float = pos[2]
		if not _link_is_the_play(link_ts - ts, (link_z - z) * attack_sign):
			break
		first_pickup_ts = ts
		if last_pickup_ts < 0.0:
			last_pickup_ts = ts
		link_ts = ts
		link_z = z
	if first_pickup_ts >= 0.0:
		play_start = first_pickup_ts - PRE_PICKUP_BUFFER
	elif saw_pickup:
		play_start = anchor_ts - MIN_PRE_TOUCH_LONG_CARRY
	var contest_ts: float = _last_event_before(events, anchor_ts, _CONTEST_KINDS)
	if contest_ts > last_pickup_ts:
		play_start = maxf(play_start, contest_ts - PRE_CONTEST_BUFFER)
	return clampf(play_start, anchor_ts - MAX_PRE_TOUCH, anchor_ts - MIN_PRE_TOUCH)


# Game time the slow motion begins: just before the scoring touch, but never
# more than SLOWMO_MAX_SPAN before the goal. It runs on through POST_GOAL_TAIL. touch_ts < 0 means no touch, which
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


static func _link_is_the_play(duration: float, advance: float) -> bool:
	return duration <= QUICK_LINK or (duration <= RUSH_LINK_MAX and advance >= RUSH_ADVANCE)


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
