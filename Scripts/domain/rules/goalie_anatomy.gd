class_name GoalieAnatomy

# The goalie's BODY, as one source of truth.
#
# ── Why this exists ──────────────────────────────────────────────────────────
# Nothing connects a literal to the collider it was copied from, so a planner
# holding its own numbers for how wide the pads splay or how far the glove
# reaches drifts silently off the body that actually makes the saves. Every
# read of the keeper's shape is derived from here instead, so changing the body
# moves the planner for free.
#
# This file is the goalie's dimensions. GoalieStickRules is his stick (same
# pattern, split out because the blade also owns an aim solve). Between them,
# anything the planner believes about the keeper's SHAPE should come from here.
#
# ── Scope: shape, not skill ──────────────────────────────────────────────────
# Physical CAPABILITY (reaction delays, push speed, butterfly drop time) is not
# here — it is tier-varied and already shared through GoalieSkillProfile /
# set_goalie_profile, which is the correct mechanism. And the BOT's own decision
# knobs (action hysteresis, settle references) are not claims about the goalie
# at all, so they are not anatomy either. This file answers exactly one
# question: how big is he, and where.
#
# Values mirror Scenes/Goalie.tscn's collision shapes and GoalieController's
# pose exports; the controller and pose builder default FROM these so there is
# one place to change.

# ── Collider boxes (Scenes/Goalie.tscn) ──────────────────────────────────────
# Leg pad: 0.28 x 0.84 x 0.2 (LeftPad / RightPad).
const PAD_BOX_WIDTH_M: float = 0.28
const PAD_BOX_HEIGHT_M: float = 0.84
const PAD_BOX_DEPTH_M: float = 0.20
# Torso: 0.62 x 0.72 x 0.28 (Body) — as wide as the pants' flare.
const TORSO_BOX_WIDTH_M: float = 0.62
const TORSO_BOX_HEIGHT_M: float = 0.72
# Glove: 0.25 x 0.32 x 0.2 (Glove) — taller than wide, as the trapper is —
# centred this far above the hand point, where the trapper's pocket is.
const GLOVE_BOX_WIDTH_M: float = 0.25
const GLOVE_BOX_HEIGHT_M: float = 0.32
const GLOVE_BOX_OFFSET_Y_M: float = 0.07

# ── Pose (GoalieController exports / GoalieBodyConfigBuilder stance) ─────────
# Lateral offset of each pad's centre from the body midline.
const PAD_LOCAL_OFFSET_M: float = 0.42
# Half-width a pad presents once ROTATED FLAT in the butterfly — the pad's long
# axis goes lateral, so this is the splayed span, not PAD_BOX_WIDTH_M * 0.5.
const BUTTERFLY_PAD_HALF_WIDTH_M: float = 0.42
# Furthest the glove hand travels outboard on a full reach
# (GoalieBodyConfigBuilder.glove_max_x_outward, sign-stripped).
const GLOVE_MAX_X_OUTWARD_M: float = 0.85
# The READY glove (GoalieBodyConfigBuilder.READY_GLOVE): out in front between
# belt and chest, on the glove side. The READY blocker is wherever the stick
# puts it (GoalieStickRules.READY_WRIST_X_M, upright_wrist_y).
const READY_GLOVE_X_M: float = 0.46
const READY_GLOVE_Y_M: float = 0.92


static func butterfly_pad_edge_half_width() -> float:
	return PAD_LOCAL_OFFSET_M + BUTTERFLY_PAD_HALF_WIDTH_M


# Half-width of the torso alone — the part of the high band that is covered no
# matter what the hands are doing.
static func torso_half_width() -> float:
	return TORSO_BOX_WIDTH_M * 0.5


# Head: 0.24 x 0.33 x 0.28 (Head) — the goalie mask, longer than it is wide —
# centred this far below the head's origin, crown to chin.
const HEAD_BOX_WIDTH_M: float = 0.24
const HEAD_BOX_HEIGHT_M: float = 0.33
const HEAD_BOX_OFFSET_Y_M: float = -0.017

const PAD_CENTER_Y_STANDING_M: float = 0.44
const TORSO_CENTER_Y_STANDING_M: float = 1.22
const HEAD_CENTER_Y_STANDING_M: float = 1.79

# Head centre above trunk centre, the same in every stance.
const NECK_M: float = HEAD_CENTER_Y_STANDING_M - TORSO_CENTER_Y_STANDING_M

const PAD_CENTER_Y_BUTTERFLY_M: float = 0.14
# Down, he sits on his heels between the flat pads, so the trunk starts at their
# tops.
const TORSO_CENTER_Y_BUTTERFLY_M: float = PAD_CENTER_Y_BUTTERFLY_M \
		+ PAD_BOX_WIDTH_M * 0.5 + TORSO_BOX_HEIGHT_M * 0.5
const HEAD_CENTER_Y_BUTTERFLY_M: float = TORSO_CENTER_Y_BUTTERFLY_M + NECK_M


# The hands down in the save stances (GoalieBodyConfigBuilder._set_down_hands):
# the blocker just above the flat pads' tops, the glove out at belly height.
const DOWN_BLOCKER_X_M: float = 0.40
const DOWN_BLOCKER_Y_M: float = PAD_CENTER_Y_BUTTERFLY_M + PAD_BOX_WIDTH_M * 0.5 \
		+ GLOVE_BOX_WIDTH_M * 0.5
const DOWN_GLOVE_Y_M: float = TORSO_CENTER_Y_BUTTERFLY_M


# Vertical extent (bottom, top) of a part, as a Vector2 so callers can test a
# height against it without allocating.
static func _span(center_y: float, height: float) -> Vector2:
	return Vector2(center_y - height * 0.5, center_y + height * 0.5)


# The leg pads. Standing they are a 0.84 m column bottoming at the ice and
# topping out at the pad-top seam (GameRules.DEFAULT_GOALIE_PAD_TOP_SEAM_M);
# rolled flat in the butterfly they are only their own box WIDTH tall — 0.28 m,
# which is 11 inches, the real NHL pad width. That collapse is the whole reason
# the over-the-pad shot exists: going down trades 0.58 m of vertical coverage
# for 0.48 m of lateral splay.
static func pad_span(down: bool) -> Vector2:
	if down:
		return _span(PAD_CENTER_Y_BUTTERFLY_M, PAD_BOX_WIDTH_M)
	return _span(PAD_CENTER_Y_STANDING_M, PAD_BOX_HEIGHT_M)


# The trunk. Standing it is glued to the pad-top seam (0.86–1.58); in the save
# stances it sits on the flat pads, 0.28–1.00.
static func torso_span(down: bool) -> Vector2:
	if down:
		return _span(TORSO_CENTER_Y_BUTTERFLY_M, TORSO_BOX_HEIGHT_M)
	return _span(TORSO_CENTER_Y_STANDING_M, TORSO_BOX_HEIGHT_M)


static func head_span(down: bool) -> Vector2:
	if down:
		return _span(HEAD_CENTER_Y_BUTTERFLY_M + HEAD_BOX_OFFSET_Y_M, HEAD_BOX_HEIGHT_M)
	return _span(HEAD_CENTER_Y_STANDING_M + HEAD_BOX_OFFSET_Y_M, HEAD_BOX_HEIGHT_M)


# Half the vertical reach of a hand about its own centre — how far off a hand's
# height a puck can arrive and still meet it.
static func hand_vertical_half_extent() -> float:
	return GLOVE_BOX_HEIGHT_M * 0.5


# Does a hand centred at `hand_y` meet a puck arriving at `arrival_y`?
static func hand_covers_height(arrival_y: float, hand_y: float) -> bool:
	return absf(arrival_y - hand_y) <= hand_vertical_half_extent()


# Half-width the keeper's STRUCTURE covers at arrival height `y` — pads, trunk
# and head only. The HANDS are deliberately absent: they move, they are raced
# against the shot's flight in the planner's reaction model, and their live
# positions arrive as replicated pose. This answers the part of the question
# that is pure shape, and the caller adds whatever the hands win.
#
# The result is symmetric because every structural part is centred on the
# midline; only the hands are sided.
static func structural_cover_half_width_at(y: float, down: bool) -> float:
	var cover: float = 0.0
	var pads: Vector2 = pad_span(down)
	if y >= pads.x and y <= pads.y:
		cover = maxf(cover, butterfly_pad_edge_half_width() if down
				else GoalieBehaviorRules.STANDING_PAD_CENTER_X_M + PAD_BOX_WIDTH_M * 0.5)
	var torso: Vector2 = torso_span(down)
	if y >= torso.x and y <= torso.y:
		cover = maxf(cover, torso_half_width())
	var head: Vector2 = head_span(down)
	if y >= head.x and y <= head.y:
		cover = maxf(cover, HEAD_BOX_WIDTH_M * 0.5)
	return cover


# ── The arms ─────────────────────────────────────────────────────────────────
# Upper arm and forearm-to-glove-centre, and the shoulder joint in the trunk's
# frame (±x). Goalie draws the arms from these, and the pose builder holds the
# hands out at a distance these arms can reach at a real bend — a hand posed
# nearer than the arm allows can only be drawn by folding the elbow into the
# body.
const ARM_UPPER_M: float = 0.38
const ARM_FOREARM_M: float = 0.38
const SHOULDER_OFFSET := Vector3(0.23, 0.24, 0.0)

# The blocker is a glove on the arm (Goalie._seat_blocker): the hand is posed,
# the elbow hangs (TwoBoneIK.solve_elbow_hanging), and the board stands on the
# back of the hand, its finger end at the grip, its face rotated out from the
# shooter by BLOCKER_FACE_OUTWARD_DEG — "blocker rotated outwards slightly", the
# coaching cue for steering rebounds to the corner. Where the board's centre
# sits: back from the grip toward the wrist, and out off the back of the hand,
# clear of the forearm's padding.
const BLOCKER_BOARD_ALONG_M: float = 0.06
const BLOCKER_BOARD_OUT_M: float = 0.09
const BLOCKER_FACE_OUTWARD_DEG: float = 15.0
# How far the wrist turns the board off the forearm toward upright: a hand held
# out in front reaches forward and down, and the wrist stands the board back up
# square to the shooter. A gripping wrist's flexion, inside its ~80° range. A
# forearm laid flatter than this cannot stand the board, so the elbow rises
# instead — which is what a blocker held high does.
const BLOCKER_WRIST_COCK_MAX_DEG: float = 60.0

