class_name AIActionScoring

# Pure-function scoring for on-puck actions: the shot and xG models, pass lanes
# and pass risk, the turnover and counter-rush costs, the difficulty-synced
# goalie mirror, and the primitives other evaluators share (the arrival clock
# `time_to_arrive`, the net-obstacle tests, the dump release search). See
# Scripts/domain/ai/CLAUDE.md → "Where an evaluator goes".
#
# Two shot models, not interchangeable:
#   · the hole geometry (`score_shoot` / `open_net_danger`) — relative shot
#     quality saturating at 1.0, NOT a goal probability. It is the truth for
#     executing a committed shot (loft, aim) and for the threat reads.
#   · the value seam (`score_shoot_value` / `score_pass_value` → AIShotValue) —
#     a calibrated goal probability, the currency the carrier's compete ranks
#     SHOOT / PASS / CARRY in (CLAUDE.md → "One currency").

# Shared read-only empty arrays, so the leaf scorers don't allocate an empty
# array per call. Two traps. They are for ARGUMENT sites only: a shared empty
# used as a *parameter default* trips a Godot type-binding error at call time,
# so the `= []` defaults below stay literals. And EMPTY_VEC3 must be a `static var`,
# not a `const`: a typed-`const` array loses its element type when passed as a
# typed-array argument (Godot rejects it — "does not have the same element
# type"), whereas a typed static var keeps it. EMPTY_CAPS is untyped, so a
# read-only `const` is fine there.
static var EMPTY_VEC3: Array[Vector3] = []
const EMPTY_CAPS: Array = []

static func _static_init() -> void:
	EMPTY_VEC3.make_read_only()
	var goal := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	XG_SLOT_REF = AIShotValue.for_release(slot_reference_release(goal), goal, 0.0)

# xG of a clean look from the slot ring, head-on, against a set keeper: the
# situation position_potential reads as 1.0, measured on the live shot model.
# It converts an in-zone xG value into position_potential's unit.
static var XG_SLOT_REF: float = 0.0

# The slot ring (m from the goal): position_potential's closeness peaks here,
# the realization discount travels to it, and XG_SLOT_REF's reference release
# sits on it.
const SLOT_RADIUS_M: float = 6.0

# ── Shot danger: hole-based open-net model ───────────────────────────────────
# score_shoot scores the classic goalie holes (HOLE_KIND / HOLE_BAND below) as
# separate targets from the shooter's eye and takes the BEST; the same hole
# decides the loft and aim (best_shot_loft / best_shot_aim). Distance, angle
# and coverage all emerge from the geometry (_hole_open_angle). The model in
# full: Scripts/domain/ai/CLAUDE.md → "Shot danger".

# [LOW, HIGH] cover half-width (m), fully deployed. LOW is the live butterfly's
# splayed pad edge — pad_local_offset 0.42 + butterfly_pad_half_width 0.42
# (GoalieController's pose); undersell it and the planner invents low-corner
# windows the real keeper closes. HIGH is the glove/blocker held up in stance,
# the narrowest core.
const HOLE_BAND_CORE: Array[float] = [0.84, 0.40]

# The goalie's paddle lying across the ice (every other `stick` in this file is
# a SKATER's blade, LANE_DEFENDER_REACH_M). It floors the LOW cover only — the
# blade is GoalieStickRules.BLADE_HEIGHT_M tall, so an elevated puck clears it —
# un-raced (already on the ice in the stance) and symmetric (the blade-aim
# solve yaws it toward the threat).
#
# Its own WIDTH, not its reach: do not feed standing_lateral_reach() here. That
# is a placement envelope, and the band cover is consumed as a DISC half-width
# by the tangent-cone occlusion, so the envelope would make him a 0.64 m solid
# disc that shuts the flat net at every range. Pricing where the blade can be
# PUT needs a per-hole placement race, not a wider floor.
static func stick_low_cover() -> float:
	return GoalieStickRules.BLADE_WIDTH_M * 0.5
# Reaction-gated extension to the placement. LOW has none of its own: the pad
# column's widening IS the butterfly drop, and everything beyond it is the
# lateral push (goalie_lateral_reach in _cover_at_height). HIGH CORE + EXT
# (0.85 m) is the live glove's reach, glove_max_x_outward.
const HOLE_BAND_EXT: Array[float] = [0.0, AIGoalieModel.GLOVE_EXTENSION_M]


# Read latency for a puck arriving at `arrival_y`: the leg delay under his
# current pad top, the slower arm delay over it (difficulty-synced — see
# set_goalie_profile). A question about HEIGHT, not band index: down, the pads
# collapse to 0.28 m and an over-the-pad puck is the hands' problem.
static func _delay_at_height(arrival_y: float, goalie_down: bool) -> float:
	if arrival_y <= GoalieAnatomy.pad_span(goalie_down).y:
		return AIGoalieModel.goalie_leg_delay_s
	return AIGoalieModel.goalie_arm_delay_s

# ── HIGH-band viability under the angle ladder ────────────────────────────────
# The loft levels are SET ANGLES (docs/elevation-rework-plan.md v3), so a
# top-band look is a RUNG CHOICE at full pace. The band a rung must arrive in:
#   · floor — his pad top (GoalieAnatomy.pad_span): below it the pad column the
#     LOW band models contests the shot.
#   · ceiling — the scoring cavity's top (HIGH_BAND_CEILING_M); bots never
#     deliberately miss high.
#   · a STANDING keeper's plane — the arc must cross him above his stick
#     assembly (GoalieStickRules.PADDLE_HEIGHT_M); a DOWN goalie's paddle is on
#     the ice and bars nothing.
# Scoring cavity top: NET_HEIGHT − post radius − puck half-height, less a
# whisker — mirrors goal detection's under-the-bar bound.
const HIGH_BAND_CEILING_M: float = 1.17
# The league M92 ladder (GameRules): the default wherever a build isn't known.
const DEFAULT_LOFT_TANS: Vector3 = Vector3(GameRules.DEFAULT_LOFT_TAN_LOW,
		GameRules.DEFAULT_LOFT_TAN_MID, GameRules.DEFAULT_LOFT_TAN_HIGH)


# Arrival height (m above launch) of a set-angle arc at `dist`:
#   h = d·tan − g·d²·(1 + tan²) / (2p²)
static func _arrival_height(dist: float, speed: float, tan_a: float) -> float:
	return dist * tan_a \
			- GameRules.GRAVITY_M_S2 * dist * dist * (1.0 + tan_a * tan_a) / (2.0 * speed * speed)


# The elevated LEVEL (ELEVATION_LOW..HIGH) whose arc from `dist` arrives inside
# the band where the least of his structure is in the way, or 0
# (ELEVATION_FLAT) when no rung arrives inside it — the committed loft of a
# HIGH-band hole (best_shot_loft) and its viability.
static func _best_high_rung(dist: float, shot_speed_m_s: float,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS, goalie_dist: float = -1.0,
		goalie_down: bool = false) -> int:
	var best_level: int = ShotMechanics.ELEVATION_FLAT
	var best_cover: float = INF
	# Standing, his pad top is the 0.86 m seam; down, the pads collapse to
	# 0.28 m and the rungs between become real targets. No puck inset here: the
	# cover model charges whatever actually is at that height.
	var floor_y: float = GoalieAnatomy.pad_span(goalie_down).y
	for i: int in 3:
		var tan_a: float = loft_tans[i]
		var arrive: float = _arrival_height(dist, shot_speed_m_s, tan_a)
		if arrive <= floor_y or arrive > HIGH_BAND_CEILING_M:
			continue
		if goalie_dist > 0.0 and not goalie_down and _arrival_height(
				goalie_dist, shot_speed_m_s, tan_a) < GoalieStickRules.PADDLE_HEIGHT_M:
			continue
		# SHAPE picks the rung: the height where the least of him is in the
		# way. The race (hands, push, his read budget) is not consulted here —
		# it needs a pace that needs a rung, and resolving that circularity by
		# guessing would make the choice depend on its own answer. A shooter
		# reads posture; whether the shot beats him is _cover_at_height's
		# question. Ties keep the FLATTER rung — the easier contact, and the
		# same preference LOFT_TIE_FRAC applies between holes.
		var cover: float = GoalieAnatomy.structural_cover_half_width_at(
				arrive, goalie_down)
		if cover < best_cover:
			best_cover = cover
			best_level = ShotMechanics.ELEVATION_LOW + i
	return best_level


# The rung a hole's shot flies: FLAT along the ice for the low bands, the
# posture-picked rung for a HIGH hole (ELEVATION_FLAT there means the band is
# structurally closed — no rung clears his pads without missing high). Callers
# read this ONCE and derive pace, arrival height and cover from it, so the
# score, the loft and the aim cannot describe different shots.
static func _hole_rung(band: int, dist: float, shot_speed_m_s: float,
		loft_tans: Vector3, goalie_dist: float, goalie_down: bool) -> int:
	if band != HOLE_BAND_HIGH:
		return ShotMechanics.ELEVATION_FLAT
	return _best_high_rung(dist, shot_speed_m_s, loft_tans, goalie_dist, goalie_down)


# Horizontal pace of a release on `level` — a lofted arc spends pace on the
# climb, a flat shot keeps all of it.
static func _rung_pace(level: int, shot_speed_m_s: float,
		loft_tans: Vector3) -> float:
	if level == ShotMechanics.ELEVATION_FLAT:
		return maxf(shot_speed_m_s, 1.0)
	var tan_a: float = loft_tans[level - ShotMechanics.ELEVATION_LOW]
	return shot_speed_m_s / sqrt(1.0 + tan_a * tan_a)


# Height that rung crosses the net line at. FLAT rides the ice.
static func _rung_arrival(level: int, dist: float, shot_speed_m_s: float,
		loft_tans: Vector3) -> float:
	if level == ShotMechanics.ELEVATION_FLAT:
		return 0.0
	return _arrival_height(dist, shot_speed_m_s,
			loft_tans[level - ShotMechanics.ELEVATION_LOW])


# The splayed (butterfly) pad's half-LENGTH — the x-extent a 90°-rolled pad
# presents. HOLE_BAND_CORE[LOW] (0.84) = pad offset 0.42 + this, the same
# anatomy the declared constant was derived from.
const PAD_SPLAY_HALF_M: float = 0.42


# A pad's LOW-band x-extent from its replicated roll, consumed as
# SPLAYED-vs-STANDING (45° threshold): a standing pad — including the
# stance's cosmetic ~12° A-frame lean — presents its box width (exactly
# the declared stance column, calibration-checked), a rolled-flat pad its
# full splayed half-length. Fine roll interpolation is deliberately NOT
# modeled: the butterfly-drop race in _cover_at_height owns mid-transition
# growth, and no instrument calibrates the intermediate angles — an
# uncheckable curve would be shape-fitting, not measurement.
static func _pad_half_extent(roll: float) -> float:
	if absf(sin(roll)) > 0.707:
		return PAD_SPLAY_HALF_M
	return GoalieBehaviorRules.PAD_BOX_WIDTH_M * 0.5


# The goalie's covered half-width (m) at the puck's arrival height, given the
# READ budget `t_read` — the puck's travel time to HIS body less screen
# occlusion and caught-moving lateness (see _hole_margin). Shared by
# _hole_margin and _hole_aim_x so aim and score read the same edge. The shape
# comes from GoalieAnatomy; this function races it (_best_high_rung is the
# other half of that split — shape picks the rung, the race scores it).
#   HIGH (over his pads): structure + the reaction-gated arm extension, raced
#         from where the hand actually is when the pose is known; a DOWN
#         goalie's glove starts at pad height, so the extension is conceded.
#   LOW:  the standing pad column widened to the splayed butterfly edge by the
#         drop race, floored by the stick. A DOWN goalie is already sealed.
#   BOTH: plus the accel-limited lateral push he lands inside the read window
#         (goalie_lateral_reach) — the recovery race of a goalie left off the
#         shot line — and the puck's own radius.
static func _cover_at_height(arrival_y: float, t_read: float, goalie_down: bool,
		side: int = 0, goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF) -> float:
	var t_move: float = maxf(0.0, t_read - _delay_at_height(arrival_y, goalie_down))
	var push: float = AIGoalieModel.goalie_lateral_reach(t_move)
	var pads_top: float = GoalieAnatomy.pad_span(goalie_down).y
	var band: int = HOLE_BAND_LOW if arrival_y <= pads_top else HOLE_BAND_HIGH
	# The puck's own radius rides on the cover edge: a puck whose CENTER
	# passes within a radius of the pad/glove edge is clipped — the mirror of
	# the clean-entry inset the post side charges, so sub-puck slivers past the
	# edge never read as windows.
	var edge: float = GameRules.PUCK_COLLISION_RADIUS + push
	if band == HOLE_BAND_HIGH:
		# ── Above his pads: STRUCTURE plus whatever the hands win ────────
		# The structural floor is the trunk/head actually at this height
		# (GoalieAnatomy). Above the standing seam it is floored by
		# HOLE_BAND_CORE[HIGH]: 0.40 was measured for that band and the raw
		# box list under-represents it there (shoulders and arm roots are not
		# colliders). Below the seam the geometry stands on its own.
		var structural: float = GoalieAnatomy.structural_cover_half_width_at(
				arrival_y, goalie_down)
		if arrival_y >= GameRules.DEFAULT_GOALIE_PAD_TOP_SEAM_M:
			structural = maxf(structural, HOLE_BAND_CORE[HOLE_BAND_HIGH])
		# With the replicated pose in scope (goalie_hands finite, a signed
		# hole side), the reaction race STARTS where the hand actually is: a
		# READY hand deploys at the stance rate, a hand committed LOW must LIFT
		# to the puck's height before its lateral coverage counts, and a hand
		# on the wrong side pays the cross-over.
		if side != 0 and goalie_hands.is_finite():
			var arm_speed: float = HOLE_BAND_EXT[HOLE_BAND_HIGH] \
					/ maxf(AIGoalieModel.goalie_arm_deploy_s, 0.001)
			var cap: float = HOLE_BAND_CORE[HOLE_BAND_HIGH] \
					+ HOLE_BAND_EXT[HOLE_BAND_HIGH]
			# The hand defending this side: the one with the larger
			# side-ward offset from the goalie's center.
			var dx_a: float = goalie_hands.x * float(side)
			var dx_b: float = goalie_hands.z * float(side)
			var hand_lat: float = dx_a
			# The glove's box sits above its hand point (the pocket); the blocker's does not.
			var hand_y: float = goalie_hands.y + GoalieAnatomy.GLOVE_BOX_OFFSET_Y_M
			if dx_b > dx_a:
				hand_lat = dx_b
				hand_y = goalie_hands.w
			var t_arm: float = t_move
			# A hand below the PUCK covers nothing until it has risen to it —
			# the lift spends read budget at the arm's pace. Racing to the
			# puck's own height, not a fixed seam, is what makes the armpit a
			# real target.
			var reach_y: float = arrival_y - GoalieAnatomy.hand_vertical_half_extent()
			if hand_y < reach_y:
				t_arm = maxf(0.0, t_arm - (reach_y - hand_y) / arm_speed)
				if t_arm <= 0.0:
					# Hand still below the puck at arrival — structure only.
					return structural + edge
			# A hand caught on the WRONG side (negative side-ward offset)
			# pays the cross-over distance — it starts from where it is.
			var start_lat: float = clampf(hand_lat, -cap, cap)
			var hand_cover: float = clampf(start_lat + arm_speed * t_arm, 0.0, cap)
			return maxf(structural, hand_cover) + edge
		var deploy: float = 0.0 if goalie_down \
				else clampf(t_move / AIGoalieModel.goalie_arm_deploy_s, 0.0, 1.0)
		return structural + HOLE_BAND_EXT[HOLE_BAND_HIGH] * deploy + edge
	# ── LOW: the side's REAL pad when the pads are replicated ────────────
	# The cover starts at the MEASURED pad edge (its lateral offset plus
	# _pad_half_extent of its roll) and the butterfly drop RACE grows it toward
	# the splay edge at the same average pace the declared-stance lerp below
	# uses. A DOWN goalie's measurement IS the truth (nothing left to drop).
	# The stick FLOORS whatever the pads have managed, down as well as up.
	var stick: float = stick_low_cover()
	if side != 0 and goalie_pads.is_finite():
		var d_left: float = goalie_pads.x * float(side) + _pad_half_extent(goalie_pads.y)
		var d_right: float = goalie_pads.z * float(side) + _pad_half_extent(goalie_pads.w)
		var measured: float = maxf(maxf(d_left, d_right), 0.0)
		if goalie_down:
			return maxf(measured, stick) + edge
		var drop_rate: float = (HOLE_BAND_CORE[HOLE_BAND_LOW] - AIGoalieModel.LOW_CORE_STANDING_M) \
				/ maxf(AIGoalieModel.goalie_butterfly_drop_s, 0.001)
		return maxf(minf(measured + drop_rate * t_move,
				maxf(HOLE_BAND_CORE[HOLE_BAND_LOW], measured)), stick) + edge
	var core: float = HOLE_BAND_CORE[HOLE_BAND_LOW]
	if not goalie_down:
		var drop: float = clampf(t_move / AIGoalieModel.goalie_butterfly_drop_s, 0.0, 1.0)
		core = lerpf(AIGoalieModel.LOW_CORE_STANDING_M, HOLE_BAND_CORE[HOLE_BAND_LOW], drop)
	return maxf(core, stick) + edge

# best_shot_loft takes the flattest hole whose opening is within this fraction
# of the widest: a flat release is the easier contact, and when both are open
# the roof buys nothing. The SCORE is still the widest opening; this only picks
# the loft.
const LOFT_TIE_FRAC: float = 0.85
const HOLE_BAND_LOW: int = 0
const HOLE_BAND_HIGH: int = 1

# Hole kinds (how the opening is measured — see _hole_open_angle).
const HOLE_KIND_CORNER: int = 0   # net-relative post; opening = net cleared past the cover edge
const HOLE_KIND_FIVE: int = 1     # goalie-relative low-centre gap; opens when he's UNSETTLED

# The five holes as parallel arrays (indexed 0..4, no per-call allocation).
const HOLE_KIND: Array[int] = [
		HOLE_KIND_CORNER, HOLE_KIND_CORNER,   # 1,2 top corners
		HOLE_KIND_CORNER, HOLE_KIND_CORNER,   # 3,4 bottom corners
		HOLE_KIND_FIVE,                       # 5   five-hole
]
const HOLE_SIDE: Array[int] = [-1, 1, -1, 1, 0]   # net/goalie side; 0 = centred
const HOLE_BAND: Array[int] = [
		HOLE_BAND_HIGH, HOLE_BAND_HIGH,
		HOLE_BAND_LOW, HOLE_BAND_LOW,
		HOLE_BAND_LOW,
]
const HOLE_COUNT: int = 5

# Five-hole: a set goalie seals it; it opens as he's caught moving (see
# UNSETTLE_READ_PENALTY_S). A physical GAP (m) between the pads, so its angular
# size foreshortens with range like any target. Only a roughly head-on look
# threads the legs (centrality falls off past FIVE_CENTER_REF_M of lateral
# offset).
const FIVE_GAP_M: float = 0.18
const FIVE_CENTER_REF_M: float = 1.6

# A goalie caught moving (goalie_unsettled_factor) reads the release LATE —
# this much added read delay (s) at unsettled = 1, mirroring the shot-outcome
# sim (shot_sim_harness.UNSETTLE_REACT_PENALTY_S). A read delay rather than a
# reaction-killing scalar, so a long flight hands it back through the same
# reach race and the recovery needs no constant of its own.
const UNSETTLE_READ_PENALTY_S: float = 0.15

# The sharpest release scatter the game actually produces (the Hard bot hand;
# a human flick is no cleaner). Floors the make-probability division below so
# a zero-spread agent still reads window WIDTH as value gradient rather than
# collapsing every sliver to a certainty.
const MIN_RELEASE_SPREAD_RAD: float = 0.010

# ── The cover edge is not a knife-edge ───────────────────────────────────────
# 1σ of WHERE the goal/save boundary actually falls, measured laterally at the
# keeper's body. The hole geometry computes one exact edge from one predicted
# pose; the real edge is a distribution, and this is its width.
#
# Derived by ELIMINATION, because most edge uncertainty is charged elsewhere:
# pose (the drop race in _cover_at_height), the puck's radius (_cover_at_height
# adds PUCK_COLLISION_RADIUS — charging it here double-counts) and the lateral
# push (goalie_lateral_reach). What is left is the timing residual: his
# position at arrival versus the prediction, about a tick of travel at t-push
# speed, ~0.03 m.
#
# Consumed by goalie_edge_spread, which foreshortens it to an angle at the
# shooter's range. test_shot_currency_saturation.gd and the real-goalie
# calibration are the readouts whenever it moves.
const GOALIE_EDGE_SOFTNESS_M: float = 0.03

# 1σ of a well-aimed shot's arrival scatter BEYOND the shooter's aim error, in
# radians. ZERO by measurement: the release applies exactly the aim angle plus
# the tier's error and the puck flies deterministic physics. Do not raise it to
# buy the decision currency more range — it charges every shot for dispersion
# the simulation does not produce. Kept as a named zero so the seam is visible
# if the shot ever does gain dispersion.
const PLACEMENT_DISPERSION_RAD: float = 0.0

# What _hole_margin returns for a hole that is not a target at all — behind the
# goal line, a band no legal power reaches, a deployed post seal, a release
# already inside his body. Structurally impossible rather than merely covered,
# so it must sit far below any softness width and never read as "nearly open".
const HOLE_STRUCTURALLY_CLOSED_RAD: float = -1.0

# The clean slot look XG_SLOT_REF is measured from, for the net at `goal`.
static func slot_reference_release(goal: Vector3) -> Vector3:
	return Vector3(goal.x, 0.0, goal.z - signf(goal.z) * SLOT_RADIUS_M)


# ── The delay discount ───────────────────────────────────────────────────────
# A future action (a carry that arrives in `t` s, a pass in flight, a spot whose
# shot must still be skated to) is worth less than the same value NOW, because
# the read it was scored against decays: the survival function of a
# CONSTANT-HAZARD process, exp(-t / τ). The one free parameter is τ, the mean
# time (s) a tactical read stays roughly valid — an honest aggregate (physical
# decorrelation times span ~0.4 s to several seconds) and the one "how much do
# I trust the near future" feel dial. Raise it for more patient play.
#
# Bounds: the unit suite guards the IMPATIENT edge (developing feeds and
# walkouts fail below τ ≈ 2.8 s); test_delay_discount_bounds_patience bounds the
# PATIENT one (τ < ~6.3 s). Every future-valued score grows with τ against
# ABSOLUTE giveaway bars, so a longer τ also lets settle doubt hold fewer
# marginal releases (test_role_carrier's settle-doubt outlet is sized for this
# value).
const READ_VALIDITY_TAU_S: float = 6.0
# Once a fire intent is set, its (positive) score is scaled by (1 + this) when
# re-scored, so a challenger must beat it by 15% — damping flicker between two
# close fire options during pre-aim. PROPORTIONAL, not additive, because scores
# span ~0.02 (deep-DZ escapes) to ~0.7 (slot chances): a flat margin sane in the
# OZ exceeds the whole gap between options in the DZ. Applied only to positive
# scores and only to fire intents (shoot, pass, a rim).
const ACTION_HYSTERESIS_MARGIN_FRAC: float = 0.15


# Value multiplier for a play `delay_s` seconds in the future,
# exp(-delay_s / READ_VALIDITY_TAU_S). Every future-action scorer routes through
# here.
static func delay_discount(delay_s: float) -> float:
	return exp(-maxf(delay_s, 0.0) / READ_VALIDITY_TAU_S)


# Shot value in [0, 1] — the MAKE PROBABILITY of firing at the best goalie
# hole (best_signed_margin: how far the net clears his cover edge, NEGATIVE by
# the overlap depth when he has it covered). best_shot_loft / best_shot_aim
# read the same winning hole.
#
# The goal/save boundary is not a line, so the margin maps to a probability
# under two uncertainties (danger_from_margin): the shooter's placement scatter
# and the keeper's edge (GOALIE_EDGE_SOFTNESS_M). A covered look is then
# small-but-ordered by HOW covered, and an open one keeps climbing instead of
# pinning — which is what lets "carry left and make him track" out-score "pass
# it back and let him re-square". Never go back to clamping a raw window
# against release scatter alone: it saturates at a tiny opening and a hard
# zero throws the overlap depth away (test_shot_currency_saturation.gd
# measures both).
#
# Execution geometry for a chosen shot, not the decision currency (shot value).
# expected_goals reads the CLAMPED best_open_angle with a context-only spread,
# never the shooter's skill, so goals-above-expected cannot be circular.
static func open_net_danger(
		shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float,
		goalie_unsettled_factor: float = 0.0,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		aim_spread_rad: float = 0.0,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> float:
	# Allocation-free — safe per carry candidate at tick rate. Pace is per-rung
	# inside _hole_margin (_rung_pace).
	var margin: float = best_signed_margin(shooter, attacking_goal, goalie_pos,
			net_half_width, shot_speed_m_s, goalie_unsettled_factor,
			goalie_five_hole_m, goalie_down,
			goalie_post_seal_x, goalie_post_seal_tall, aim_spread_rad,
			screen_dist_m, goalie_hands, goalie_pads, loft_tans)
	# The two spreads stay SEPARATE arguments: the keeper's edge is a symmetric
	# uncertainty on the window, the shooter's dispersion a half-normal miss
	# distance (_make_probability). Never fold them into one sigma that softens
	# the window — a wider hand would then widen the window too.
	return danger_from_margin(shooter, goalie_pos, margin, aim_spread_rad)


# The margin -> make-probability mapping, split out so it has exactly one
# implementation. AIDangerField interpolates the MARGIN and maps afterwards:
# the margin is smooth geometry, while the mapping is a sigmoid whose knee is
# the steepest feature on the surface.
static func danger_from_margin(shooter: Vector3, goalie_pos: Vector3,
		margin: float, aim_spread_rad: float = 0.0) -> float:
	return _make_probability(margin, placement_spread(aim_spread_rad),
			goalie_edge_spread(shooter, goalie_pos))


# 8-point Gauss–Legendre nodes and weights on [−1, 1] (within 5e-4 of a dense
# reference: test_shot_danger_properties.gd).
const _GL8_X: Array[float] = [-0.9602898564975363, -0.7966664774136267,
		-0.5255324099163290, -0.1834346424956498, 0.1834346424956498,
		0.5255324099163290, 0.7966664774136267, 0.9602898564975363]
const _GL8_W: Array[float] = [0.1012285362903763, 0.2223810344533745,
		0.3137066458778873, 0.3626837833783620, 0.3626837833783620,
		0.3137066458778873, 0.2223810344533745, 0.1012285362903763]


# P(goal) for a signed `margin`, a shooter whose placement scatters by
# `sigma_p`, and a cover edge uncertain by `sigma_e` — all radians at the eye:
# P(|X| − ε < margin/2) exactly, as Φ₂(h, h; ρ) by its integral over arcsin ρ
# (Scripts/domain/ai/CLAUDE.md → Shot geometry). Never replace it with a
# moment-matched normal: that lets a covered shot score higher the worse the hand.
static func _make_probability(margin: float, sigma_p: float,
		sigma_e: float) -> float:
	var var_sum: float = sigma_p * sigma_p + sigma_e * sigma_e
	if var_sum <= 1e-12:
		return 1.0 if margin > 0.0 else 0.0
	var h: float = margin * 0.5 / sqrt(var_sum)
	var hh: float = h * h
	var half_angle: float = 0.5 * asin(clampf(
			(sigma_e * sigma_e - sigma_p * sigma_p) / var_sum, -1.0, 1.0))
	var integral: float = 0.0
	for i: int in 8:
		integral += _GL8_W[i] * exp(-hh / (1.0 + sin(half_angle * (1.0 + _GL8_X[i]))))
	var phi_h: float = 0.5 * (1.0 + _erf(h / sqrt(2.0)))
	return clampf(phi_h * phi_h + integral * half_angle / TAU, 0.0, 1.0)


# 1σ of the keeper's cover EDGE for this look, in radians at the shooter's eye.
# GOALIE_EDGE_SOFTNESS_M is a linear figure at his body, so it foreshortens
# with range exactly like every other target: the same physical fuzziness is a
# wide uncertainty from in tight and a narrow one from the point.
static func goalie_edge_spread(shooter: Vector3, goalie_pos: Vector3) -> float:
	var dx: float = goalie_pos.x - shooter.x
	var dz: float = goalie_pos.z - shooter.z
	return GOALIE_EDGE_SOFTNESS_M / maxf(sqrt(dx * dx + dz * dz), 0.5)


# 1σ of where the shot actually ARRIVES, in radians: the shooter's aim error
# (the tier dial / the bot's own hand) in quadrature with the dispersion every
# release carries however well aimed — blade contact, puck roll, release
# timing. Without that floor the dial alone governs saturation, and at the Hard
# hand's 0.01 rad the currency pins at a 0.02 rad window.
static func placement_spread(aim_spread_rad: float) -> float:
	var aim: float = maxf(aim_spread_rad, MIN_RELEASE_SPREAD_RAD)
	return sqrt(aim * aim + PLACEMENT_DISPERSION_RAD * PLACEMENT_DISPERSION_RAD)


# The best signed margin (radians) over the five holes — how far the widest
# hole clears the keeper's cover edge, NEGATIVE by the overlap depth when he
# has every hole covered. The raw geometry open_net_danger (the bot's decision
# currency) sits on. Pure value-type math, no allocation.
static func best_signed_margin(
		shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float,
		goalie_unsettled_factor: float = 0.0,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		aim_spread_rad: float = 0.0,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> float:
	var best: float = HOLE_STRUCTURALLY_CLOSED_RAD
	for i: int in HOLE_COUNT:
		var m: float = _hole_margin(i, shooter, attacking_goal, goalie_pos,
				net_half_width, shot_speed_m_s, goalie_unsettled_factor,
				goalie_five_hole_m, goalie_down,
				goalie_post_seal_x, goalie_post_seal_tall, aim_spread_rad,
				screen_dist_m, goalie_hands, goalie_pads, loft_tans)
		if m > best:
			best = m
	return best


# The widest goalie-beating opening (radians) over the five holes, CLAMPED at
# zero — the "is there a window, and how wide" read. expected_goals (the
# post-game analytic) sits on this; so do the aim / loft / power choosers,
# which only ever target a hole that is genuinely open. Pure value-type math,
# no allocation.
static func best_open_angle(
		shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float,
		goalie_unsettled_factor: float = 0.0,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		aim_spread_rad: float = 0.0,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> float:
	var best_angle: float = 0.0
	for i: int in HOLE_COUNT:
		var a: float = _hole_open_angle(i, shooter, attacking_goal, goalie_pos,
				net_half_width, shot_speed_m_s, goalie_unsettled_factor,
				goalie_five_hole_m, goalie_down,
				goalie_post_seal_x, goalie_post_seal_tall, aim_spread_rad,
				screen_dist_m, goalie_hands, goalie_pads, loft_tans)
		if a > best_angle:
			best_angle = a
	return best_angle


# ── Expected goals (xG) — the analytics stat ─────────────────────────────────
# Beating a goalie is TWO things: getting net open, and putting the puck in it.
# Unlike open_net_danger, which prices the bot's OWN precision (right for a
# decision it then executes), this prices a context-only spread, so it is a
# stat about arbitrary shooters.
#
#   xG = P(placement lands in the open window) + P(miss it) × P(goalie leaks)
#
#   1. GEOMETRY — best_open_angle: the open net past the goalie, in radians,
#      measured with a SHARP hand (XG_ENTRY_SPREAD_RAD): "what is open" is a
#      question about the goalie, and charging the release spread here too
#      would double-count it.
#   2. EXECUTION — the release spread, as a Gaussian placement distribution over
#      that window.
#
# Passes are excluded upstream — expected_goals only ever sees a shot the
# resolution gate counted.
const XG_ENTRY_SPREAD_RAD: float = MIN_RELEASE_SPREAD_RAD
# Release scatter (radians, 1σ) for a reference shooter taking a SETTLED shot.
# Calibrated against the observed on-net fraction: every missed shot is direct
# evidence about this number, and a game has far more misses than goals.
const XG_BASE_SPREAD_RAD: float = 0.12
# A backhand is materially harder to place than a forehand.
const XG_BACKHAND_SPREAD_MULT: float = 1.6
# Shooting on the move — across the body, in transition, out of a deke — widens
# the release, scaled by speed against a reference clip.
const XG_MOTION_SPREAD_GAIN: float = 0.6
const XG_MOTION_REFERENCE_M_S: float = 8.0
# A shot the goalie can physically cover still goes in sometimes: a misplay, a
# five-hole leak, a deflection off traffic, a rebound he can't smother. Without
# this term the model floors at exactly zero for every point shot and every
# in-tight look at a square goalie — the false zeros at both ends of the curve.
const XG_COVERED_LEAK: float = 0.04
# Nothing is a certain goal — you can still fan on it or ring it off the iron
# with the net empty. Mirrors the leak at the other end of the range.
const XG_MAX: float = 0.95


# Release scatter for a shot's CONTEXT — never for the shooter's skill. A weaker
# player drawing lower xG on an identical chance would make goals-above-expected
# circular, so this reads the situation (hand, motion) and nothing about who is
# holding the stick.
static func xg_release_spread(is_backhand: bool, skater_speed_m_s: float) -> float:
	var spread: float = XG_BASE_SPREAD_RAD
	if is_backhand:
		spread *= XG_BACKHAND_SPREAD_MULT
	spread *= 1.0 + XG_MOTION_SPREAD_GAIN \
			* clampf(skater_speed_m_s / XG_MOTION_REFERENCE_M_S, 0.0, 2.0)
	return spread


# Fraction of a Gaussian release distribution landing inside a window of
# `window_rad` TOTAL angular width, aimed at its centre.
static func _placement_probability(window_rad: float, spread_rad: float) -> float:
	if window_rad <= 0.0:
		return 0.0
	if spread_rad <= 0.0001:
		return 1.0
	return _erf(window_rad * 0.5 / (spread_rad * sqrt(2.0)))


# erf via Abramowitz & Stegun 7.1.26 (|error| < 1.5e-7) — GDScript has no erf.
static func _erf(x: float) -> float:
	var ax: float = absf(x)
	var t: float = 1.0 / (1.0 + 0.3275911 * ax)
	var poly: float = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741
			+ t * (-1.453152027 + t * 1.061405429))))
	return signf(x) * (1.0 - poly * exp(-ax * ax))


static func expected_goals(
		shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float,
		goalie_unsettled_factor: float = 0.0,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS,
		release_spread_rad: float = XG_BASE_SPREAD_RAD) -> float:
	var window: float = best_open_angle(shooter, attacking_goal, goalie_pos,
			net_half_width, shot_speed_m_s, goalie_unsettled_factor,
			goalie_five_hole_m, goalie_down,
			goalie_post_seal_x, goalie_post_seal_tall, XG_ENTRY_SPREAD_RAD,
			screen_dist_m, goalie_hands, goalie_pads, loft_tans)
	var placed: float = _placement_probability(window, release_spread_rad)
	# Miss the open window and the goalie still has to actually stop it.
	return minf(XG_MAX, placed + (1.0 - placed) * XG_COVERED_LEAK)


# The LOFT the bot should shoot with, from the same hole geometry that
# open_net_danger scores: ELEVATION_FLAT for a LOW-band hole (bottom corner,
# five-hole), the posture-picked rung (_best_high_rung) for a top corner. The
# hole is _choose_shot_hole's. Called once when SHOOT commits.
static func best_shot_loft(
		shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float,
		goalie_unsettled_factor: float = 0.0,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		aim_spread_rad: float = 0.0,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> int:
	var hole: int = _choose_shot_hole(shooter, attacking_goal, goalie_pos,
			net_half_width, shot_speed_m_s, goalie_unsettled_factor,
			goalie_five_hole_m, goalie_down,
			goalie_post_seal_x, goalie_post_seal_tall, aim_spread_rad,
			screen_dist_m, goalie_hands, goalie_pads, loft_tans)
	if hole < 0 or HOLE_BAND[hole] != HOLE_BAND_HIGH:
		return ShotMechanics.ELEVATION_FLAT
	return _best_high_rung(shooter.distance_to(attacking_goal), shot_speed_m_s,
			loft_tans, _xz_dist(shooter, goalie_pos), goalie_down)


# The world aim POINT (on the net plane, y = 0) of the CHOSEN hole — the exact
# target the loft was picked for, so aim and loft always describe the same hole.
# The state machine locks this as the wrister aim at charge start. Falls back to
# the goal centre if the goalie leaves nothing (defensive — SHOOT only commits
# when there's an opening).
static func best_shot_aim(
		shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float,
		goalie_unsettled_factor: float = 0.0,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		aim_spread_rad: float = 0.0,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> Vector3:
	var hole: int = _choose_shot_hole(shooter, attacking_goal, goalie_pos,
			net_half_width, shot_speed_m_s, goalie_unsettled_factor,
			goalie_five_hole_m, goalie_down,
			goalie_post_seal_x, goalie_post_seal_tall, aim_spread_rad,
			screen_dist_m, goalie_hands, goalie_pads, loft_tans)
	if hole < 0:
		return Vector3(attacking_goal.x, 0.0, attacking_goal.z)
	var aim_x: float = _hole_aim_x(hole, shooter, attacking_goal, goalie_pos,
			net_half_width, shot_speed_m_s, goalie_unsettled_factor, aim_spread_rad,
			goalie_down, screen_dist_m, goalie_hands, goalie_pads, loft_tans)
	return Vector3(aim_x, 0.0, attacking_goal.z)


# Picks the shot hole the bot commits to: the widest opening, then tie-broken
# toward the FLATTEST loft within LOFT_TIE_FRAC of it (bury it low if you can,
# ride the toe only when the top is the real way in), and within that flattest
# tier the widest opening. Returns the hole index, or -1 if nothing is open.
# One chooser shared by best_shot_loft and best_shot_aim so they never disagree.
static func _choose_shot_hole(
		shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float, unsettled: float,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		aim_spread_rad: float = 0.0,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> int:
	# Chosen on the SIGNED margin, not the clamped opening, so the bot aims at
	# the hole open_net_danger scored — the LEAST-BAD one when all are covered,
	# never a dead-centre fallback. Only a structurally impossible hole is off
	# the table.
	var best_margin: float = HOLE_STRUCTURALLY_CLOSED_RAD
	for i: int in HOLE_COUNT:
		var a: float = _hole_margin(i, shooter, attacking_goal, goalie_pos,
				net_half_width, shot_speed_m_s, unsettled, goalie_five_hole_m, goalie_down,
				goalie_post_seal_x, goalie_post_seal_tall, aim_spread_rad,
				screen_dist_m, goalie_hands, goalie_pads, loft_tans)
		if a > best_margin:
			best_margin = a
	if best_margin <= HOLE_STRUCTURALLY_CLOSED_RAD:
		return -1
	# Same "within LOFT_TIE_FRAC of the best" slack, written so it also means
	# something for a negative best: identical to best × LOFT_TIE_FRAC whenever
	# best is positive, and a symmetric widening below zero.
	var threshold: float = best_margin - (1.0 - LOFT_TIE_FRAC) * absf(best_margin)
	var chosen: int = -1
	var chosen_loft: int = ShotMechanics.ELEVATION_HIGH + 1
	var chosen_angle: float = HOLE_STRUCTURALLY_CLOSED_RAD
	for i: int in HOLE_COUNT:
		var a: float = _hole_margin(i, shooter, attacking_goal, goalie_pos,
				net_half_width, shot_speed_m_s, unsettled, goalie_five_hole_m, goalie_down,
				goalie_post_seal_x, goalie_post_seal_tall, aim_spread_rad,
				screen_dist_m, goalie_hands, goalie_pads, loft_tans)
		if a < threshold or a <= HOLE_STRUCTURALLY_CLOSED_RAD:
			continue
		var band_loft: int = HOLE_BAND[i]   # LOW band (flat) orders before HIGH
		if band_loft < chosen_loft or (band_loft == chosen_loft and a > chosen_angle):
			chosen_loft = band_loft
			chosen_angle = a
			chosen = i
	return chosen


# The net-plane aim x for a chosen hole. Corners aim at the open segment's
# midpoint, biased toward the post by AIShotAim.DEFAULT_CORNER_BIAS; the
# five-hole aims at the goalie's centre (between the legs). Reuses
# _hole_margin's body-disc cover and read budget so aim and score agree.
static func _hole_aim_x(
		i: int, shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float, unsettled: float,
		aim_spread_rad: float = 0.0, goalie_down: bool = false,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> float:
	var kind: int = HOLE_KIND[i]
	var side: int = HOLE_SIDE[i]
	var band: int = HOLE_BAND[i]
	# Same rung the opening was scored with (_hole_margin), so aim and score
	# read the same arrival height and cover. A chosen hole is never
	# band-unreachable, so the FLAT fallback on a HIGH hole is belt-and-braces.
	var dist_to_goal: float = shooter.distance_to(attacking_goal)
	var level: int = _hole_rung(band, dist_to_goal, shot_speed_m_s, loft_tans,
			_xz_dist(shooter, goalie_pos), goalie_down)
	var pace: float = _rung_pace(level, shot_speed_m_s, loft_tans)
	var arrival_y: float = _rung_arrival(level, dist_to_goal, shot_speed_m_s,
			loft_tans)
	var net_z: float = attacking_goal.z
	var post_lo_x: float = attacking_goal.x - net_half_width
	var post_hi_x: float = attacking_goal.x + net_half_width
	# Post clearance: the widest |x| the puck's CENTER can cross the line at
	# without clipping the pipe (post + puck radius — see
	# GameRules.NET_ENTRY_HALF_WIDTH), PLUS the shooter's own execution spread
	# projected to the net plane, so a noisy hand's wobble lands as goals, saves
	# and misses rather than iron.
	var entry_inset: float = GameRules.NET_POST_RADIUS \
			+ GameRules.PUCK_COLLISION_RADIUS \
			+ aim_spread_rad * shooter.distance_to(attacking_goal)
	var entry_lo_x: float = post_lo_x + entry_inset
	var entry_hi_x: float = post_hi_x - entry_inset

	if kind == HOLE_KIND_FIVE:
		return clampf(_shadow_x(shooter, goalie_pos.x, goalie_pos.z, net_z),
				entry_lo_x, entry_hi_x)

	# Corner: aim at the open segment [post ↔ cover edge] on the hole's side.
	# Cover edges come from _hole_margin's disc-tangent body model, projected
	# back onto the net plane so the midpoint math stays in x.
	var u: float = goalie_pos.x - shooter.x
	var net_normal_z: float = -signf(attacking_goal.z)
	var fwd: float = (shooter.z - attacking_goal.z) * net_normal_z
	var dv: float = fwd - (goalie_pos.z - attacking_goal.z) * net_normal_z
	# Same read budget as _hole_margin: the puck's travel to HIS body, not the
	# goal line, less the screened and caught-moving lateness.
	var t_reach: float = sqrt(u * u + dv * dv) / pace
	var t_read: float = t_reach - screen_dist_m / pace \
			- clampf(unsettled, 0.0, 1.0) * UNSETTLE_READ_PENALTY_S
	var cover: float = _cover_at_height(arrival_y, t_read, goalie_down, side,
			goalie_hands, goalie_pads)
	var cov_lo_x: float = post_hi_x
	var cov_hi_x: float = post_lo_x
	if dv >= 0.001:
		var d: float = sqrt(u * u + dv * dv)
		if d <= cover:
			# Smothered (scored 0 anyway) — degenerate; aim the near entry edge.
			return entry_lo_x if side < 0 else entry_hi_x
		var alpha: float = atan2(u, dv)
		var beta: float = asin(clampf(cover / d, 0.0, 1.0))
		var g_lo: float = alpha - beta
		var g_hi: float = alpha + beta
		cov_lo_x = post_lo_x if g_lo <= -PI * 0.5 + 0.001 \
				else clampf(shooter.x + tan(g_lo) * fwd, post_lo_x, post_hi_x)
		cov_hi_x = post_hi_x if g_hi >= PI * 0.5 - 0.001 \
				else clampf(shooter.x + tan(g_hi) * fwd, post_lo_x, post_hi_x)
	if side < 0:
		var mid_lo: float = (post_lo_x + cov_lo_x) * 0.5
		return maxf(lerpf(mid_lo, post_lo_x, AIShotAim.DEFAULT_CORNER_BIAS), entry_lo_x)
	var mid_hi: float = (cov_hi_x + post_hi_x) * 0.5
	return minf(lerpf(mid_hi, post_hi_x, AIShotAim.DEFAULT_CORNER_BIAS), entry_hi_x)


# Projects a point (px at depth pz) onto the net plane (z = net_z) along the
# sightline from the shooter — the point's "shadow" on the net. Only the
# five-hole aim uses this centre-point projection; the corners read the cover
# as a body-disc tangent cone (_hole_margin), which keeps sharp angles honest.
static func _shadow_x(shooter: Vector3, px: float, pz: float, net_z: float) -> float:
	var dz: float = pz - shooter.z
	if absf(dz) < 0.000001:
		return px
	return shooter.x + (net_z - shooter.z) / dz * (px - shooter.x)


# RAW open angle (radians, from the shooter's eye) of hole `i` — 0 if the
# goalie covers it. The CLAMPED view of _hole_margin, for the consumers that
# only care whether a hole is a target at all: the aim / loft / power choosers
# and expected_goals. open_net_danger reads the signed margin instead, because
# HOW covered a covered hole is is exactly the gradient it needs (see there).
static func _hole_open_angle(
		i: int, shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float, unsettled: float,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		aim_spread_rad: float = 0.0,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> float:
	return maxf(0.0, _hole_margin(i, shooter, attacking_goal, goalie_pos,
			net_half_width, shot_speed_m_s, unsettled, goalie_five_hole_m,
			goalie_down, goalie_post_seal_x, goalie_post_seal_tall,
			aim_spread_rad, screen_dist_m, goalie_hands, goalie_pads, loft_tans))


# The five-hole's SIGNED margin from an effective slot width (m). The puck
# either fits between his pads or it does not, and that verdict does NOT
# foreshorten, so a slot the puck cannot pass is structurally closed — never a
# shortfall divided by range, which would read a sealed slot as "a hair closed"
# from distance and let the soft edge pay out on it. Only a real opening is
# measured as an angle. The unsettle gradient lives upstream, in `slot`.
static func _five_hole_margin(slot: float, dist: float) -> float:
	var clearance: float = slot - 2.0 * GameRules.PUCK_COLLISION_RADIUS
	if clearance <= 0.0:
		return HOLE_STRUCTURALLY_CLOSED_RAD
	return clearance / maxf(dist, 0.5)


# SIGNED margin (radians, from the shooter's eye) of hole `i`: how much net
# clears the reaction-gated cover edge, going NEGATIVE by the overlap depth
# when the keeper has the hole covered. The five-hole is a central gap that
# opens with the goalie's unsettle, signed by how far the slot falls short of
# the puck's own diameter. The shooter's execution spread does NOT enter here
# (open_net_danger's make-probability mapping owns it, exactly once); the
# `_aim_spread_rad` slot keeps the chooser/aim/score call chain positionally
# aligned with _hole_aim_x, which does consume it.
#
# Holes that are not targets at all — behind the goal line, an unreachable
# band, a deployed post seal, a release inside his body — return
# HOLE_STRUCTURALLY_CLOSED_RAD rather than a near-zero negative, so the
# softness tail in open_net_danger never reads them as nearly open.
static func _hole_margin(
		i: int, shooter: Vector3, attacking_goal: Vector3, goalie_pos: Vector3,
		net_half_width: float, shot_speed_m_s: float, unsettled: float,
		goalie_five_hole_m: float = -1.0, goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		_aim_spread_rad: float = 0.0,
		screen_dist_m: float = 0.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> float:
	var net_normal_z: float = -signf(attacking_goal.z)
	var forward: float = (shooter.z - attacking_goal.z) * net_normal_z
	if forward < 0.001:
		# On/behind the goal line — no shot in.
		return HOLE_STRUCTURALLY_CLOSED_RAD
	var kind: int = HOLE_KIND[i]
	var side: int = HOLE_SIDE[i]
	var band: int = HOLE_BAND[i]
	# One rung read, shared by the pace, the arrival height and the cover, so
	# the score and the aim describe a single shot. A HIGH hole with no legal
	# rung is structurally closed — not a target at all.
	var dist_to_goal: float = shooter.distance_to(attacking_goal)
	var level: int = _hole_rung(band, dist_to_goal, shot_speed_m_s, loft_tans,
			_xz_dist(shooter, goalie_pos), goalie_down)
	if band == HOLE_BAND_HIGH and level == ShotMechanics.ELEVATION_FLAT:
		return HOLE_STRUCTURALLY_CLOSED_RAD
	var pace: float = _rung_pace(level, shot_speed_m_s, loft_tans)
	var arrival_y: float = _rung_arrival(level, dist_to_goal, shot_speed_m_s,
			loft_tans)
	# Reach budget: the puck crosses the goalie's reach envelope at HIS body —
	# the shooter→goalie gap at the rung's pace. Never budget on the flight to
	# the goal line: that hands a challenging keeper time he does not have.
	var u: float = goalie_pos.x - shooter.x
	var dv: float = forward - (goalie_pos.z - attacking_goal.z) * net_normal_z
	var t_reach: float = sqrt(u * u + dv * dv) / pace
	# Delayed read: his clock starts when the puck EMERGES past the worst
	# screener (screen_dist_m / pace), and a caught-moving keeper reads late on
	# top of it. Only the READ budget shrinks: a screened or scrambling goalie
	# still fills his ice, he just deploys late.
	var t_read: float = t_reach - screen_dist_m / pace \
			- clampf(unsettled, 0.0, 1.0) * UNSETTLE_READ_PENALTY_S

	# A post-seal stance (VH/RVH — GoalieNetworkState.post_seal_x_sign) is a
	# DEPLOYED wall at the post, not reaction-gated. Both close the five-hole;
	# VH closes sealed-side LOW and HIGH, RVH only sealed-side LOW (its short-side
	# HIGH weakness stays measured). The FAR side is read from his actual
	# position below, which keeps the walkout / cross-crease counter visible.
	#
	# The wall only exists if he can ACTUALLY reach the seal post: goalie_pos
	# already bakes in the setup time, so the check is positional — his body
	# edge (LOW_CORE_STANDING_M plus the push he lands inside t_read) must reach
	# the post. A stranded keeper does not seal (the back-door tap-in).
	if goalie_post_seal_x != 0.0 \
			and absf(attacking_goal.x + signf(goalie_post_seal_x)
					* GameRules.NET_HALF_WIDTH - goalie_pos.x) \
				<= AIGoalieModel.LOW_CORE_STANDING_M + AIGoalieModel.goalie_lateral_reach(maxf(t_read, 0.0)):
		if kind == HOLE_KIND_FIVE:
			return HOLE_STRUCTURALLY_CLOSED_RAD
		if float(side) == signf(goalie_post_seal_x) \
				and (goalie_post_seal_tall or HOLE_BAND[i] == HOLE_BAND_LOW):
			return HOLE_STRUCTURALLY_CLOSED_RAD
	if kind == HOLE_KIND_FIVE:
		# Jam smother: a release already inside the goalie's standing pad
		# column (a behind-the-goalie release clamped to his toes) has no
		# five-hole — the body it would thread is ON the puck. Mirrors the
		# corner branch's release-inside-the-body smother.
		var jam_r: float = AIGoalieModel.LOW_CORE_STANDING_M + GameRules.PUCK_COLLISION_RADIUS
		if u * u + dv * dv <= jam_r * jam_r:
			return HOLE_STRUCTURALLY_CLOSED_RAD
		# Between-the-legs gap; only a roughly head-on look can thread the legs
		# (centrality). What scores is the gap's CLEARANCE past the puck's own
		# diameter (_five_hole_margin), so the standing ~0.16-0.20 m slot is the
		# razor-thin look it is and the live five-hole is the DOWN goalie's
		# slide leak.
		var centrality: float = clampf(
				1.0 - absf(shooter.x - goalie_pos.x) / FIVE_CENTER_REF_M, 0.0, 1.0)
		var dist: float = shooter.distance_to(attacking_goal)
		if goalie_five_hole_m >= 0.0:
			# MEASURED slot from the replicated pose (GoalieBehaviorRules.
			# five_hole_gap_m). Standing, he seals it by DROPPING once he reads
			# the release — leg delay then pads-to-floor, raced against the puck
			# reaching HIM — so only an in-tight release beats the drop. Down,
			# the residual gap (slide leak) is already the measurement.
			var gap: float = goalie_five_hole_m
			if not goalie_down:
				var seal: float = clampf(
						(t_read - _delay_at_height(0.0, goalie_down))
							/ AIGoalieModel.goalie_butterfly_drop_s,
						0.0, 1.0)
				gap *= 1.0 - seal
			# Do not subtract the PADDLE here (GoalieStickRules.
			# five_hole_gap_after_blade): its 0.38 m width clamps a ~0.20 m slot
			# to zero for every standing keeper at every range, and the drop race
			# stops mattering. The blade is 0.07 m tall — a lifted wrister clears
			# it through the legs — and the LOW band has no height resolution to
			# represent "over the blade, between the pads" as its own hole.
			#
			# Centrality narrows the SLOT rather than scaling the finished margin:
			# scaling a NEGATIVE margin toward zero would read a hopeless
			# off-axis look as nearly open.
			return _five_hole_margin(gap * centrality, dist)
		# Proxy (no replicated stance in scope — threat surfaces, tests): the
		# nominal standing slot raced against the same read-delayed butterfly
		# seal the measured branch runs.
		var proxy_gap: float = FIVE_GAP_M
		var proxy_seal: float = clampf(
				(t_read - _delay_at_height(0.0, goalie_down)) / AIGoalieModel.goalie_butterfly_drop_s,
				0.0, 1.0)
		proxy_gap *= 1.0 - proxy_seal
		return _five_hole_margin(proxy_gap * centrality, dist)

	# Cover at the height this shot actually arrives at, raced against t_read.
	var cover: float = _cover_at_height(arrival_y, t_read, goalie_down, side,
			goalie_hands, goalie_pads)

	# Net posts and the goalie's cover, all as bearings from the shooter's eye.
	var post_lo_x: float = attacking_goal.x - net_half_width
	var post_hi_x: float = attacking_goal.x + net_half_width
	var net_lo: float = atan2(post_lo_x - shooter.x, forward)
	var net_hi: float = atan2(post_hi_x - shooter.x, forward)
	# The goalie occludes as a BODY (a disc of the cover radius), not a paper
	# cutout on the x-axis: he squares to the puck, so the covered bearing
	# interval is the disc's tangent cone. From a sharp angle his DEPTH then
	# occludes the cross-crease lane; a zero-depth model leaves the far post
	# "open" from beside the net.
	var covb_lo: float
	var covb_hi: float
	if dv < 0.001:
		# Goalie at/behind the release plane — he covers nothing (upstream release
		# clamps keep real shooters from exploiting this; it's a degenerate read).
		covb_lo = net_hi
		covb_hi = net_lo
	else:
		var d_sq: float = u * u + dv * dv
		if d_sq <= cover * cover:
			# Release inside the goalie's body — smothered.
			return HOLE_STRUCTURALLY_CLOSED_RAD
		var alpha: float = atan2(u, dv)
		var beta: float = asin(clampf(cover / sqrt(d_sq), 0.0, 1.0))
		# Bounded ABOVE by the far post (a keeper entirely off the net can only
		# open the net's own width) but NOT below: clamping the near side to the
		# post throws the overlap depth away and flat-lines the covered region
		# at exactly 0.
		covb_lo = minf(alpha - beta, net_hi)
		covb_hi = maxf(alpha + beta, net_lo)

	var open_angle: float
	if side < 0:
		open_angle = covb_lo - net_lo   # left post → cover's left edge
	else:
		open_angle = net_hi - covb_hi   # cover's right edge → right post
	# The puck has to FIT: a corner only scores what remains after the puck's
	# clean-entry inset off the pipe — post radius + puck radius, the
	# GameRules.NET_ENTRY_HALF_WIDTH inset _hole_aim_x buys the aim point — a
	# HARD geometric requirement, subtracted outright. (_cover_at_height charges
	# the mirror inset off the pad/glove edge.)
	var pipe_clearance: float = (GameRules.NET_POST_RADIUS + GameRules.PUCK_COLLISION_RADIUS) \
			/ maxf(shooter.distance_to(attacking_goal), 0.5)
	return maxf(open_angle - pipe_clearance, HOLE_STRUCTURALLY_CLOSED_RAD)


# ── Screen perception (sightline occlusion) ──────────────────────────────────
# Planning mirror of the live goalie's screen model
# (GoalieBehaviorRules.screen_occlusion_delay): a body between the release and
# the goalie hides the puck, and his read clock only starts when the puck
# EMERGES past the screener. Returns the worst screener's along-sightline
# distance (m) from the release — 0.0 for a clean look. A DISTANCE, not a
# time: each hole band divides by its own pace (_hole_margin's t_read), so
# the slower lofted arc is hidden longer than the bullet on the same geometry.
#
# Two body lists so callers hand over defenders + own teammates without
# merging (hot-path: no combined array). BOTH sides screen; the block risk the
# defender bodies also carry is priced separately by lane_clear. Radius and
# shooter self-exclusion mirror GoalieBehaviorRules.ScreenConfig.
const SCREEN_BODY_HALF_WIDTH_M: float = 0.6
const SCREEN_MIN_ALONG_M: float = 0.6

static func _xz_dist(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


static func screen_along_m(
		shooter: Vector3, goalie_pos: Vector3,
		bodies_a: Array[Vector3], bodies_b: Array[Vector3]) -> float:
	var dx: float = goalie_pos.x - shooter.x
	var dz: float = goalie_pos.z - shooter.z
	var goalie_along: float = sqrt(dx * dx + dz * dz)
	if goalie_along <= SCREEN_MIN_ALONG_M:
		return 0.0
	var hx: float = dx / goalie_along
	var hz: float = dz / goalie_along
	var worst: float = _worst_screener_along(
			bodies_a, shooter, hx, hz, goalie_along, 0.0)
	return _worst_screener_along(bodies_b, shooter, hx, hz, goalie_along, worst)


# One body list's worst on-sightline screener (see screen_along_m). A screener
# counts only ON the line (perp < body half-width), past the shooter's own
# body, and NEARER than the goalie (a body level with or behind him can't
# hide an incoming puck). Scalar loop, allocation-free.
static func _worst_screener_along(
		bodies: Array[Vector3], shooter: Vector3,
		hx: float, hz: float, goalie_along: float, worst: float) -> float:
	for s: Vector3 in bodies:
		var relx: float = s.x - shooter.x
		var relz: float = s.z - shooter.z
		var along: float = relx * hx + relz * hz
		if along <= SCREEN_MIN_ALONG_M or along >= goalie_along:
			continue
		if absf(relx * -hz + relz * hx) >= SCREEN_BODY_HALF_WIDTH_M:
			continue
		if along > worst:
			worst = along
	return worst


# ── Shoot-for-tip EV ──────────────────────────────────────────────────────────
# The value of ripping a shot AT THE NET through a net-front teammate's blade.
# Above the deflect threshold the puck redirects off his angled blade at
# near-full pace (PuckCollisionRules.deflect_velocity; the finisher's reactive
# TIP mode steps onto the shot path), so the outcome is a NEW release from the
# tip point. Three independent events compose:
#   P(rip reaches the tipper)   — lane_clear over release→tip vs the DEFENDERS
# × P(blade contacts the puck)  — the same reach/reaction race a lane defender
#                                 runs (_lane_block_at)
# × score_shoot(tip point → net) — the redirect on the hole geometry; its
#                                 short flight sits inside the goalie's read.
# max() against the direct read at the call site, never additive — the two are
# different aims of the same rip.

# Puck.deflect_min_speed (test_bot_mirrors.gd), the receiver-relative pace above
# which a blade deflects instead of catching: a rip below it lands on the
# tape as a pass — no tip outcome exists.
const TIP_DEFLECT_MIN_SPEED_M_S: float = 22.0

# Outgoing-line scatter of a deflection (radians), fed to score_shoot's
# aim-spread term. A set net-front blade controls its FACE angle to roughly
# ±7°, and reflection doubles face error into outgoing error (~±14°). Without
# it a tip reads as an aimed corner snipe rather than "get a piece, change the
# line".
const TIP_AIM_SPREAD_RAD: float = 0.25


static func tip_ev(
		release: Vector3,
		tip_man: Vector3,
		attacking_goal: Vector3,
		goalie_pos: Vector3,
		net_half_width: float,
		opponents: Array[Vector3],
		shot_speed_m_s: float,
		opponent_caps: Array = [],
		tip_caps: AISkaterCaps = null) -> float:
	if shot_speed_m_s < TIP_DEFLECT_MIN_SPEED_M_S:
		return 0.0
	# Shot line: release → net centre (the reactive tip steps ONTO this line,
	# so planning against it is self-consistent with the execution).
	var dx: float = attacking_goal.x - release.x
	var dz: float = attacking_goal.z - release.z
	var line_len: float = sqrt(dx * dx + dz * dz)
	if line_len < 0.001:
		return 0.0
	var hx: float = dx / line_len
	var hz: float = dz / line_len
	# Tip point: the tipper's foot on the line — where blade meets puck. Must
	# be a real mid-flight contact: past the shooter's own handle, short of
	# the goal mouth.
	var relx: float = tip_man.x - release.x
	var relz: float = tip_man.z - release.z
	var along: float = relx * hx + relz * hz
	if along <= SCREEN_MIN_ALONG_M or along >= line_len - 0.3:
		return 0.0
	var tip_pt := Vector3(release.x + hx * along, 0.0, release.z + hz * along)
	# P(blade contacts): the tipper's real stick reach + lateral close.
	var stick: float = AIPuckLane.LANE_DEFENDER_REACH_M
	var close: float = AIPuckLane.LANE_DEFENDER_CLOSE_SPEED_M_S
	if tip_caps != null:
		stick = tip_caps.stick_reach
		close = AIPuckLane.LANE_LATERAL_FRACTION * tip_caps.max_speed
	var speed: float = maxf(shot_speed_m_s, 1.0)
	var p_contact: float = AIPuckLane.lane_block_at(
			release.x, release.z, hx * speed, hz * speed, along / speed,
			tip_man.x, tip_man.z, 0.0, 0.0, stick, close)
	if p_contact <= 0.0:
		return 0.0
	# P(rip reaches him): the defenders' lane over the release→tip segment.
	var lane: float = AIPuckLane.lane_clear(release, tip_pt, opponents, speed, EMPTY_VEC3, opponent_caps)
	if lane <= 0.0:
		return 0.0
	# The redirect: a new release at the tip point holding the incoming pace
	# (a tip keeps the along-face glance), scattered by the deflection's
	# outgoing-line control (TIP_AIM_SPREAD_RAD). No unsettle bonus — the
	# collapsed read window IS the tip's edge, and it falls out of t_reach.
	var redirect: float = score_shoot(
			tip_pt, attacking_goal, goalie_pos, net_half_width, opponents,
			speed, 0.0, opponent_caps, -1.0, false, 0.0, false,
			TIP_AIM_SPREAD_RAD)
	return p_contact * lane * redirect


# SHOOT score in [0, 1] on the hole geometry: open_net_danger × lane clearance
# × the release contest. `predicted_goalie_pos` is the goalie at shot release
# (predict_goalie_pos). `shot_speed_m_s` sets the puck's pace (goalie read
# budget) and the lane math; `goalie_unsettled_factor` delays his read.
# `screeners` are ADDITIONAL sightline bodies (the shooter's own teammates);
# the defender bodies in `opponents` screen implicitly.
static func score_shoot(
		shooter: Vector3,
		attacking_goal: Vector3,
		predicted_goalie_pos: Vector3,
		net_half_width: float,
		opponents: Array[Vector3],
		shot_speed_m_s: float = AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
		goalie_unsettled_factor: float = 0.0,
		opponent_caps: Array = [],
		goalie_five_hole_m: float = -1.0,
		goalie_down: bool = false,
		goalie_post_seal_x: float = 0.0,
		goalie_post_seal_tall: bool = false,
		aim_spread_rad: float = 0.0,
		screeners: Array[Vector3] = [],
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		loft_tans: Vector3 = DEFAULT_LOFT_TANS) -> float:
	# No shot from on/behind the goal line. Checked BEFORE the release clamp
	# below, which would teleport a behind-the-net release to a phantom
	# point-blank spot in front of the goalie (the wraparound is a CARRY).
	if (shooter.z - attacking_goal.z) * -signf(attacking_goal.z) < 0.001:
		return 0.0
	# The puck can't be shot from behind the goalie — clamp the shooter to the
	# jam distance in front of him, or a projected release in the crease reads
	# as a phantom open net. No-op for any normal in-front shot.
	shooter = AIGoalieModel.release_ahead_of_goalie(shooter, attacking_goal, predicted_goalie_pos)
	var screen_dist: float = screen_along_m(
			shooter, predicted_goalie_pos, opponents, screeners)
	var shot_quality: float = open_net_danger(
			shooter, attacking_goal, predicted_goalie_pos, net_half_width,
			shot_speed_m_s, goalie_unsettled_factor,
			goalie_five_hole_m, goalie_down,
			goalie_post_seal_x, goalie_post_seal_tall, aim_spread_rad,
			screen_dist, goalie_hands, goalie_pads, loft_tans)
	if shot_quality <= 0.0:
		return 0.0
	# Lane clear vs the aim point AIShotAim picks (past the goalie's shadow).
	var aim: Vector3 = AIShotAim.compute_open_net_aim(
			shooter, predicted_goalie_pos, attacking_goal.z,
			net_half_width, AIGoalieModel.GOALIE_SHADOW_HALF_M)
	var lane: float = AIPuckLane.lane_clear(shooter, aim, opponents, shot_speed_m_s, EMPTY_VEC3, opponent_caps)
	# Release duress: opponents whose blade can reach the puck during the
	# windup (bodies on the shot line are the lane's job).
	var pressure_factor: float = AIPuckLane.release_contest_clean(
			AIPuckLane.release_point_toward(shooter, attacking_goal), opponents, opponent_caps)
	return shot_quality * lane * pressure_factor


# ── The SEAM's composed counterpart ──────────────────────────────────────────
# score_shoot's structure with AIShotValue supplying the shot quality — a
# smooth, goalie-displacement-aware probability — instead of the hole geometry.
# Same guards, release clamp and defender terms: the lane and the release
# contest are facts about DEFENDERS, not the goalie model.
static func score_shoot_value(
		shooter: Vector3,
		attacking_goal: Vector3,
		predicted_goalie_pos: Vector3,
		keeper_displacement_m: float,
		net_half_width: float,
		opponents: Array[Vector3],
		shot_speed_m_s: float = AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
		opponent_caps: Array = [],
		shot_type: int = ShotEvent.ShotType.SHOT,
		loft_tan_high: float = GameRules.DEFAULT_LOFT_TAN_HIGH) -> float:
	if (shooter.z - attacking_goal.z) * -signf(attacking_goal.z) < 0.001:
		return 0.0
	shooter = AIGoalieModel.release_ahead_of_goalie(shooter, attacking_goal, predicted_goalie_pos)
	# The seal is derived from the same geometric trigger the live keeper uses
	# (derive_post_seal_x_sign — inside the post zone AND past the bearing), so
	# predictive and shoot-now paths agree about it without threading state.
	var seal_x: float = AIGoalieModel.derive_post_seal_x_sign(shooter, attacking_goal)
	var quality: float = AIShotValue.for_release(
			shooter, attacking_goal, keeper_displacement_m, shot_type,
			seal_x != 0.0, Vector2(predicted_goalie_pos.x - attacking_goal.x,
					predicted_goalie_pos.z - attacking_goal.z).length(),
			loft_tan_high, shot_speed_m_s)
	if quality <= 0.0:
		return 0.0
	var aim: Vector3 = AIShotAim.compute_open_net_aim(
			shooter, predicted_goalie_pos, attacking_goal.z,
			net_half_width, AIGoalieModel.GOALIE_SHADOW_HALF_M)
	var lane: float = AIPuckLane.lane_clear(shooter, aim, opponents, shot_speed_m_s,
			EMPTY_VEC3, opponent_caps)
	var pressure: float = AIPuckLane.release_contest_clean(
			AIPuckLane.release_point_toward(shooter, attacking_goal), opponents, opponent_caps)
	return quality * lane * pressure


# score_pass's twin on the seam — lane × the receiver's shot value from where
# he catches it, with the keeper's displacement at the receiver's release the
# one goalie term (score_pass reads the whole pose instead).
#
# The DEVELOPING-feed hold must be priced here, not by score_pass: it competes
# with the fire as `fire_score >= hold_value`, and a hole-geometry hold is a
# permanent veto on shooting (CLAUDE.md → "One currency").
static func score_pass_value(
		shooter: Vector3,
		receiver: Vector3,
		attacking_goal: Vector3,
		keeper_displacement_m: float,
		opponents: Array[Vector3],
		pass_speed_m_s: float = AIPuckLane.PASS_SPEED_M_S,
		opponent_caps: Array = EMPTY_CAPS,
		shot_type: int = ShotEvent.ShotType.SHOT) -> float:
	if _is_past_goal_line(receiver, attacking_goal):
		return 0.0
	if AINetObstacle.pass_lane_blocked_by_net(shooter, receiver):
		return 0.0
	var lane: float = AIPuckLane.lane_clear(shooter, receiver, opponents, pass_speed_m_s,
			EMPTY_VEC3, opponent_caps)
	if lane <= 0.0:
		return 0.0
	return lane * AIShotValue.for_release(
			receiver, attacking_goal, keeper_displacement_m, shot_type,
			AIGoalieModel.derive_post_seal_x_sign(receiver, attacking_goal) != 0.0)


# FIELDED twin of score_shoot for the threat-surface consumer family
# (threat_surface_shoot / threat_local_shoot / the zone soft-lock read):
# the goalie-hole core comes from AIDangerField's memoized surface — league
# pace, unsettled 0, declared stance, seal derived from position, goalie at
# his CURRENT spot, which are exactly this family's inputs — and only the
# defender terms (shot lane, release contest) run live, so a hypothetical
# defender body still blocks exactly. One deliberate drop vs the exact twin,
# bounded by test_danger_field.gd: sightline screening (the fielded read
# understates a screened shooter). Same guard + release clamp as the exact
# twin, applied BEFORE sampling so the memo is keyed on the clamped release.
static func score_shoot_threat_fielded(
		shooter: Vector3,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		net_half_width: float,
		defenders: Array[Vector3],
		defender_caps: Array = EMPTY_CAPS) -> float:
	if (shooter.z - our_net.z) * -signf(our_net.z) < 0.001:
		return 0.0
	var clamped: Vector3 = AIGoalieModel.release_ahead_of_goalie(shooter, our_net, our_goalie_pos)
	var q: float = AIDangerField.quality(
			clamped, our_net, our_goalie_pos, net_half_width)
	if q <= 0.0:
		return 0.0
	var aim: Vector3 = AIShotAim.compute_open_net_aim(
			clamped, our_goalie_pos, our_net.z,
			net_half_width, AIGoalieModel.GOALIE_SHADOW_HALF_M)
	var lane: float = AIPuckLane.lane_clear(clamped, aim, defenders, AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
			EMPTY_VEC3, defender_caps)
	var pressure: float = AIPuckLane.release_contest_clean(
			AIPuckLane.release_point_toward(clamped, our_net), defenders, defender_caps)
	return q * lane * pressure


# PASS score in [0, 1] for a specific receiver on the hole geometry: the lane
# × the receiver's score_shoot from where he catches it. No receiver-quality
# terms (open man, advancement) and no further pass — this leaf does not
# recurse, so evaluation cannot loop pass-back-and-forth. The carrier's own
# compete prices passes through the seam instead (score_pass_value).
static func score_pass(
		shooter: Vector3,
		receiver: Vector3,
		attacking_goal: Vector3,
		predicted_goalie_pos: Vector3,
		net_half_width: float,
		opponents: Array[Vector3],
		pass_speed_m_s: float = AIPuckLane.PASS_SPEED_M_S,
		goalie_unsettled_factor: float = 0.0,
		precomputed_lane: float = -1.0,
		goalie_hands: Vector4 = Vector4.INF,
		goalie_pads: Vector4 = Vector4.INF,
		opponent_caps: Array = EMPTY_CAPS) -> float:
	if _is_past_goal_line(receiver, attacking_goal):
		return 0.0
	if AINetObstacle.pass_lane_blocked_by_net(shooter, receiver):
		return 0.0
	# Lane-clear's reaction window scales with puck flight time, so pass the
	# actual fire speed (expected_pass_speed). `precomputed_lane` (>= 0) lets a
	# caller that already ran the identical lane_clear hand it in.
	# `opponent_caps` (index-matched to `opponents`) prices each lane
	# defender's real stick reach and closing pace; empty = league.
	var lane: float = precomputed_lane if precomputed_lane >= 0.0 \
			else AIPuckLane.lane_clear(shooter, receiver, opponents, pass_speed_m_s,
					EMPTY_VEC3, opponent_caps)
	if lane <= 0.0:
		return 0.0
	# The caller predicts the goalie at the receiver's release time (flight +
	# charge — predict_goalie_pos); goalie_unsettled_factor credits a feed that
	# catches him mid-slide. Receiver shot speed is the league default
	# (cross-player). The receiver's spot reads the predicted post-seal, so a
	# dead-angle receiver has no phantom value.
	var seal_x: float = AIGoalieModel.derive_post_seal_x_sign(receiver, attacking_goal)
	var receiver_shot: float = score_shoot(
			receiver, attacking_goal, predicted_goalie_pos, net_half_width, opponents,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, goalie_unsettled_factor, opponent_caps, -1.0, false,
			seal_x, seal_x != 0.0, 0.0, EMPTY_VEC3, goalie_hands, goalie_pads)
	return lane * receiver_shot


# ── Helpers ──────────────────────────────────────────────────────────────────


# True if `pos` is past the attacking goal line in the direction the
# attacking team is going (i.e. "behind the net" relative to the
# shooter). For Team 0 attacking -Z (attacking_goal.z = -26.65),
# "past" means z < -26.65; for Team 1 attacking +Z, z > +26.65.
static func _is_past_goal_line(pos: Vector3, attacking_goal: Vector3) -> bool:
	return (pos.z - attacking_goal.z) * signf(attacking_goal.z) > 0.0


# True when `pos` is on the attacking side of the attacking blue line — the
# offensive zone, and the value-map regime boundary: the carrier's `AICarrierField.value_at`
# prices in-zone positions through the value seam and out-of-zone positions by
# position_potential. Sign-folded for either attacking direction.
# `buffer` demands the position sit that much DEEPER than the line — the
# carrier's blue-line keep-out bands (retreat / reception) use it so "in the
# zone" can mean "in the zone with margin for the stick's reach".
static func in_offensive_zone(pos: Vector3, attacking_goal: Vector3,
		buffer: float = 0.0) -> bool:
	return pos.z * signf(attacking_goal.z) > GameRules.BLUE_LINE_Z + buffer


# Position potential in [0, 1] — the value of being at this position with no
# specific shot or pass in view, as closeness × the goal mouth's projected width
# from this bearing × openness (each derived below). `AICarrierField.value_at` reads it only
# while the CARRIER is outside the offensive zone; in the zone the bot prices
# real shot danger instead. Behind the attacking goal line it returns 0.
static func position_potential(
		pos: Vector3,
		attacking_goal: Vector3,
		opponents: Array[Vector3],
		opponent_caps: Array = EMPTY_CAPS) -> float:
	var net_normal_z: float = -signf(attacking_goal.z)
	var forward: float = (pos.z - attacking_goal.z) * net_normal_z
	if forward < 0.001:
		return 0.0
	var dist: float = pos.distance_to(attacking_goal)
	# Closeness: 0 at the goal, 1 on the slot ring, 0 at goal-to-goal
	# distance — the gradient covers the whole rink so deep-zone positions
	# still have a forward-progress signal.
	var rink_length: float = absf(GameRules.GOAL_LINE_Z) * 2.0
	var closeness: float
	if dist <= SLOT_RADIUS_M:
		closeness = clampf(dist / SLOT_RADIUS_M, 0.0, 1.0)
	else:
		closeness = clampf(
				1.0 - (dist - SLOT_RADIUS_M) / (rink_length - SLOT_RADIUS_M),
				0.0, 1.0)
	# Angle quality = the goal mouth's PROJECTED width from this bearing,
	# cos(θ) = forward / horizontal_distance: 1 head-on, → 0 along the goal line.
	var lateral: float = pos.x - attacking_goal.x
	var horiz_dist: float = sqrt(forward * forward + lateral * lateral)
	var angle_factor: float = forward / horiz_dist
	# Openness: could a carrier get his action off from this spot — the same
	# release contest the shot scorers use.
	var openness: float = AIPuckLane.release_contest_clean(
			AIPuckLane.release_point_toward(pos, attacking_goal), opponents, opponent_caps)
	return closeness * angle_factor * openness


# Realization discount for position_potential when it prices a CARRY /
# receiver destination in the carrier's compete: potential is FUTURE value,
# cashed only by skating from `pos` to the slot, so it pays the same
# delay_discount every other future action pays. Without it the stand-still
# candidate holds its potential undecayed while every movement candidate pays
# travel decay, and an open carrier plants at the blue line; with it an
# on-route step trades travel decay for realization decay one-for-one.
#
# Travel time is to the slot ring (SLOT_RADIUS_M) at the league reference
# speed (cross-player: receivers use it too).
static func potential_realization_discount(pos: Vector3,
		attacking_goal: Vector3) -> float:
	var travel_dist: float = maxf(0.0, pos.distance_to(attacking_goal) - SLOT_RADIUS_M)
	return delay_discount(travel_dist / AIArrival.SKATER_REF_SPEED_M_S)


# ── Dump races ────────────────────────────────────────────────────────────────
# The race primitives the dump searches (below, and AICarrierDumpSearch)
# and the rim pricing read. The dump itself is a residual, never entered in the
# value compete — see Scripts/domain/ai/CLAUDE.md → "Dumps are searched
# RELEASES".

# The head-start that turns a 50/50 loose-puck race into a near-sure recovery:
# a stride, expressed as the TIME a stride buys at reference pace, because the
# race below is run in time. A metre band saturates to 0 or 1 over the 30-40 m
# a clear travels.
const CHASE_CONTEST_MARGIN_M: float = 2.0
const CHASE_CONTEST_MARGIN_S: float = CHASE_CONTEST_MARGIN_M / AIArrival.SKATER_REF_SPEED_M_S


# True when `pos` is on the attacking side of centre ice (z = 0) — past the red
# line, where a dump-in to the offensive zone can't be icing.
static func past_center_toward_attack(pos: Vector3, attacking_goal: Vector3) -> bool:
	return pos.z * signf(attacking_goal.z) > 0.0


# Probability our team wins the race to a loose puck at `target`: an ARRIVAL
# race between our first body there and theirs, with a contest band around a
# tie (CHASE_CONTEST_MARGIN_S). 1.0 uncontested, 0.0 if we have no chaser.
#
# Momentum-honest, through time_to_arrive: nearest by ETA, never by metres — a
# body two metres nearer but skating the other way loses this race. Keep the
# clock and the probability on the same arrival model.
#
# `our_vels` / `opp_vels` are index-matched to their position arrays; omit them
# and every chaser races from rest. Everyone runs at the league reference build
# — the same simplification counter_rush_cost makes for teammates.
static func chase_recovery(
		target: Vector3,
		our_chasers: Array[Vector3],
		opp_chasers: Array[Vector3],
		our_vels: Array[Vector3] = EMPTY_VEC3,
		opp_vels: Array[Vector3] = EMPTY_VEC3) -> float:
	if our_chasers.is_empty():
		return 0.0
	var our_t: float = _first_arrival(target, our_chasers, our_vels)
	if opp_chasers.is_empty():
		return 1.0
	var opp_t: float = _first_arrival(target, opp_chasers, opp_vels)
	return clampf(0.5 + (opp_t - our_t) / (2.0 * CHASE_CONTEST_MARGIN_S), 0.0, 1.0)


# Soonest any of `chasers` reaches `target`. `vels` is used only when it is
# index-matched to `chasers`, so callers that hold no velocities pass EMPTY_VEC3
# and every body races from rest.
#
# Exact prune: time_to_arrive only ever ADDS time to `straight_line_distance /
# cap`, so a chaser whose bound is already beaten cannot win. It matters
# because the dump searches call this per candidate spot.
static func _first_arrival(target: Vector3, chasers: Array[Vector3],
		vels: Array[Vector3]) -> float:
	var has_vels: bool = vels.size() == chasers.size()
	var vmax: float = maxf(AIArrival.SKATER_REF_SPEED_M_S, AIArrival.MIN_TRAVEL_SPEED_M_S)
	var best: float = INF
	for i: int in chasers.size():
		if chasers[i].distance_to(target) >= best * vmax:
			continue
		best = minf(best, AIArrival.time_to_arrive(chasers[i], target,
				vels[i] if has_vels else Vector3.ZERO))
	return best


# How far (m) from the net mouth the goalie still counts as HOME for the
# threat-surface shot skips below — the crease depth plus a stride. Beyond it
# (pulled, or out playing the puck) the direct-shot branch must be computed
# from anywhere on the rink.
const THREAT_GOALIE_HOME_M: float = 3.0

# "Threat surface" — the value an opponent can extract from his current
# position, from a defender's perspective: max(fielded shot, position_potential).
# The shot fades to ~0 far from our net; the positional fallback keeps a
# non-zero gradient over any legal position, so a defender still has a reason
# to close a far-but-dangerous man (reducing his openness).
static func threat_surface_shoot(
		opp_pos: Vector3,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		net_half_width: float,
		defenders: Array[Vector3],
		defender_caps: Array = EMPTY_CAPS) -> float:
	var positional: float = position_potential(opp_pos, our_net, defenders,
			defender_caps)
	# Hot-path skip, not a shaping choice: with the goalie HOME, a direct shot
	# from outside the zone is dead by the hole geometry's own coverage math,
	# so the max() below is always the positional branch there. A displaced or
	# pulled goalie voids the proof, so it computes fully.
	if not in_offensive_zone(opp_pos, our_net) \
			and our_goalie_pos.distance_to(our_net) < THREAT_GOALIE_HOME_M:
		return positional
	# FIELDED read (AIDangerField): the goalie-hole core, predicted post-seal
	# included, comes from the memoized surface; only the lane and
	# release-contest terms run against `defenders` live.
	var shoot: float = score_shoot_threat_fielded(
			opp_pos, our_net, our_goalie_pos, net_half_width, defenders,
			defender_caps)
	return maxf(shoot, positional)


# LOCAL threat — the shot branch of threat_surface_shoot WITHOUT the
# positional fallback. The fallback is right for positioning and WRONG for
# absolute turnover pricing: it floors possession-against-us at ~0.25-0.55
# everywhere on the rink. Turnover pricing reads the immediate danger here and
# the FUTURE carry-in danger via counter_rush_cost, which sees the covering set.
static func threat_local_shoot(
		opp_pos: Vector3,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		net_half_width: float,
		defenders: Array[Vector3],
		defender_caps: Array = EMPTY_CAPS) -> float:
	if not in_offensive_zone(opp_pos, our_net) \
			and our_goalie_pos.distance_to(our_net) < THREAT_GOALIE_HOME_M:
		return 0.0
	# FIELDED read — same memoized core as threat_surface_shoot (seal derived
	# inside the field), live lane/contest terms.
	return score_shoot_threat_fielded(
			opp_pos, our_net, our_goalie_pos, net_half_width, defenders,
			defender_caps)


# Pass-threat surface — score_pass with a positional fallback for the same
# reason as threat_surface_shoot: when the receiver's shot collapses to 0 the
# lane still has value to defend, so the fallback rewards defenders for being
# in the lane AND for closing on the receiver. `defender_caps` (index-matched
# to `defenders`) prices each defending blade's real reach and closing pace;
# empty = league.
static func threat_surface_pass(
		carrier_pos: Vector3,
		receiver_pos: Vector3,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		net_half_width: float,
		defenders: Array[Vector3],
		defender_caps: Array = EMPTY_CAPS) -> float:
	if AINetObstacle.pass_lane_blocked_by_net(carrier_pos, receiver_pos):
		return 0.0
	# Assume the opponent fires this hypothetical pass at the speed our bots
	# would, or the quick-pass default overstates defender reaction time on
	# long passes.
	var pass_speed: float = AIPuckLane.expected_pass_speed(carrier_pos, receiver_pos)
	# Compute the lane once: it feeds both score_pass and the positional floor
	# below, on a per-candidate defensive read.
	var lane: float = AIPuckLane.lane_clear(carrier_pos, receiver_pos, defenders, pass_speed,
			EMPTY_VEC3, defender_caps)
	var pass_score: float = score_pass(
			carrier_pos, receiver_pos, our_net, our_goalie_pos,
			net_half_width, defenders, pass_speed, 0.0, lane,
			Vector4.INF, Vector4.INF, defender_caps)
	var positional: float = position_potential(receiver_pos, our_net, defenders,
			defender_caps)
	return maxf(pass_score, lane * positional)


# Expected turnover cost — the defensive half of the carrier's expected-value
# model: the possession value the OPPONENT gains if we lose the puck at
# `loss_point`, times the probability of losing it. "Don't turn it over where it
# hurts" falls out of geometry: small far from our net, large in front of it.
#
# The cost must be in the unit of the gains it competes with, or one side wins by
# scale alone. `in_xg` is for a carrier in the offensive zone, whose gains are
# xG: the opponent's value is then his shot xG through the value seam, or his
# possession promise (potential × realization × XG_SLOT_REF) where no shot cashes
# it. Otherwise the gains are on the potential scale, and so is
# threat_surface_shoot.
#
# `our_defenders` are our skaters (excluding the carrier, who just got beat); they
# block the opponent's lane and contest his release. Returns 0 when there is no
# loss location (INF) or no loss probability.
static func turnover_cost(
		loss_point: Vector3,
		loss_prob: float,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		net_half_width: float,
		our_defenders: Array[Vector3],
		defender_caps: Array = EMPTY_CAPS,
		in_xg: bool = false) -> float:
	if not loss_point.is_finite():
		return 0.0
	if loss_prob <= 0.0:
		return 0.0
	if not in_xg:
		return loss_prob * threat_surface_shoot(
				loss_point, our_net, our_goalie_pos, net_half_width, our_defenders,
				defender_caps)
	var value: float = position_potential(loss_point, our_net, our_defenders, defender_caps) \
			* potential_realization_discount(loss_point, our_net) * XG_SLOT_REF
	# Outside our zone with the keeper home his shot xG beats that promise by at
	# most a long shot's logistic tail, ~0.003 at the far end
	# (test_in_xg_turnover_shot_skip_is_safe), so the shot read is skipped there.
	if in_offensive_zone(loss_point, our_net) \
			or our_goalie_pos.distance_to(our_net) >= THREAT_GOALIE_HOME_M:
		value = maxf(value, score_shoot_value(
				loss_point, our_net, our_goalie_pos, 0.0, net_half_width,
				our_defenders, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, defender_caps))
	return loss_prob * value


# ── Transition-exposure: the counter-rush cost (5v5-gated at the caller) ─────
# turnover_cost above prices the threat AT the loss point, so it can't see a
# defenseman caught deep: a loss in the O-zone reads ~0 there, while the true
# cost is the COUNTER-RUSH into the ice the carrier vacated. This is the
# additive second half, priced with only the defenders who beat that rush home.
#
#   counter_point  = the slot in front of OUR net (where a rush shoots from —
#                    a physical landmark, not a shape parameter).
#   t_counter      = the fastest opponent's time to collect the loss and
#                    carry to the counter_point (momentum-aware first leg at
#                    his real Speed cap, straight carry second leg).
#   covering set   = every teammate — and the carrier himself, recovering
#                    from the candidate spot — who can reach the counter
#                    point by t_counter. Bodies that can't beat the rush
#                    home don't exist to this read. Covering bodies stand at
#                    the goal-side cover anchor (AIThreatAssignment.cover_anchor).
#   cost           = loss_prob × threat_surface_shoot(counter_point | covering
#                    set) × delay_discount(t_counter)   — a future threat,
#                    decayed over the time the rush needs to develop.
#
# One-up-one-back falls out with no pairing rule: a partner holding the point
# beats any counter home, so the other D is free to attack; both D deep and
# the deep carry prices itself out. Teammates race at the league reference
# speed (their caps are not in scope — a perception simplification).

# Scratch for the covering-defender positions (caller-owned pattern; this
# is per-candidate hot-ish path at the AI dispatch cadence).
static var _scratch_counter_cover: Array[Vector3] = []


# The counter point a rush shoots from, and each teammate's standing-start
# ETA to it — candidate-invariant inputs the carrier precomputes once per
# compete (fill_counter_cover_etas) instead of re-racing per candidate.
static func counter_point_for(our_net: Vector3) -> Vector3:
	var own_dir: float = signf(our_net.z)
	return Vector3(0.0, 0.0, our_net.z - own_dir * GameRules.SLOT_DIST_M)


static func fill_counter_cover_etas(our_net: Vector3,
		teammates: Array[Vector3], out_etas: Array[float]) -> void:
	var cp: Vector3 = counter_point_for(our_net)
	out_etas.clear()
	for tm: Vector3 in teammates:
		out_etas.append(tm.distance_to(cp) / AIArrival.SKATER_REF_SPEED_M_S)


static func counter_rush_cost(
		loss_point: Vector3,
		loss_prob: float,
		our_net: Vector3,
		our_goalie_pos: Vector3,
		net_half_width: float,
		teammates: Array[Vector3],
		self_recover_pos: Vector3,
		self_max_speed: float,
		opponents: Array[Vector3],
		opponent_vels: Array[Vector3],
		opponent_caps: Array,
		mate_etas: Array[float] = [],
		threat_by_cover: Array[float] = [],
		in_xg: bool = false) -> float:
	if not loss_point.is_finite() or loss_prob <= 0.0 or opponents.is_empty():
		return 0.0
	var counter_point: Vector3 = counter_point_for(our_net)

	# Fastest opponent: collect the loss, then carry to the counter point at
	# his top speed.
	var carry_dist: float = loss_point.distance_to(counter_point)
	var t_counter: float = INF
	var t_collect_best: float = INF
	var has_vels: bool = opponent_vels.size() == opponents.size()
	var has_caps: bool = opponent_caps.size() == opponents.size()
	for i: int in opponents.size():
		var speed: float = AIArrival.SKATER_REF_SPEED_M_S
		if has_caps:
			var caps: AISkaterCaps = opponent_caps[i]
			if caps != null:
				speed = caps.max_speed
		var vel: Vector3 = opponent_vels[i] if has_vels else Vector3.ZERO
		var t_collect: float = AIArrival.time_to_arrive(opponents[i], loss_point, vel, speed)
		if t_collect < t_collect_best:
			t_collect_best = t_collect
		var t: float = t_collect + carry_dist / maxf(speed, 0.001)
		if t < t_counter:
			t_counter = t
	if t_counter == INF:
		return 0.0
	# PASS-FORWARD leg: the counter can hit an outlet already AHEAD. From the
	# fastest collect, price the hardest feed to each other opponent and HIS
	# carry home from rest, and let the min compete with the lone-carrier time.
	for j: int in opponents.size():
		var j_speed: float = AIArrival.SKATER_REF_SPEED_M_S
		if has_caps:
			var j_caps: AISkaterCaps = opponent_caps[j]
			if j_caps != null:
				j_speed = j_caps.max_speed
		var j_carry: float = opponents[j].distance_to(counter_point)
		# The feed only helps when the outlet is genuinely AHEAD of the
		# lug — skip receivers whose own carry isn't shorter.
		if j_carry >= carry_dist:
			continue
		var t_pf: float = t_collect_best \
				+ loss_point.distance_to(opponents[j]) \
						/ GameRules.DEFAULT_WRISTER_POWER_MAX_M_S \
				+ AIArrival.time_to_arrive(opponents[j], counter_point, Vector3.ZERO, j_speed)
		if t_pf < t_counter:
			t_counter = t_pf

	# Covering set: bodies that beat the counter home WITH TIME TO SET — the
	# same brake-to-arrive margin AIRoleSlots5.assign charges the RUSH_D1
	# deadline (stride-for-stride beside the rush is chasing, not covering). League-paced, like the mate
	# ETAs it pads.
	var setup_margin: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S \
			/ AISteering.ARRIVAL_BRAKE_DECEL_M_S2
	var cover_anchor: Vector3 = AIThreatAssignment.cover_anchor(
			counter_point, our_net)
	_scratch_counter_cover.clear()
	if mate_etas.size() == teammates.size():
		# Precomputed teammate races (fill_counter_cover_etas) — the hot
		# per-candidate path.
		for eta: float in mate_etas:
			if eta + setup_margin <= t_counter:
				_scratch_counter_cover.append(cover_anchor)
	else:
		for tm: Vector3 in teammates:
			if tm.distance_to(counter_point) / AIArrival.SKATER_REF_SPEED_M_S \
					+ setup_margin <= t_counter:
				_scratch_counter_cover.append(cover_anchor)
	if self_recover_pos.is_finite() \
			and self_recover_pos.distance_to(counter_point) \
					/ maxf(self_max_speed, 0.001) + setup_margin <= t_counter:
		_scratch_counter_cover.append(cover_anchor)

	# score_shoot directly, not threat_surface_shoot: the counter point IS a
	# shot location (the slot), squarely in score_shoot's domain — the
	# positional fallback would hold its value regardless of the covering
	# set (closeness × angle ignore defenders' block) and dilute the whole
	# covered-vs-open signal this term exists to read.
	#
	# Memo by cover count: within one compete the only thing a candidate
	# changes here is HOW MANY bodies stand at the anchor, so the caller may
	# pass a -1-seeded scratch (`threat_by_cover`, indexed by cover count,
	# reset each compete).
	#
	# `in_xg` prices the shot through the value seam (see turnover_cost). A memo
	# must only ever hold one unit.
	var cover_count: int = _scratch_counter_cover.size()
	var threat: float = -1.0
	if cover_count < threat_by_cover.size():
		threat = threat_by_cover[cover_count]
	if threat < 0.0:
		if in_xg:
			threat = score_shoot_value(
					counter_point, our_net, our_goalie_pos, 0.0, net_half_width,
					_scratch_counter_cover)
		else:
			threat = score_shoot(
					counter_point, our_net, our_goalie_pos, net_half_width,
					_scratch_counter_cover)
		if cover_count < threat_by_cover.size():
			threat_by_cover[cover_count] = threat
	return loss_prob * threat * delay_discount(t_counter)


# ── Dump delivery search ─────────────────────────────────────────────────────
# A dump is a RELEASE, not a spot: both dumps search launches and read where
# each one actually comes to rest (AITrajectory.puck_release_landing). The DZ
# clear filters for legal launches (dump_clear_candidates); the NZ dump-in is
# scored on winning the race to the resting spot (solve_dump_in). See
# Scripts/domain/ai/CLAUDE.md → "Dumps are searched RELEASES".

# Launch bearings tried per dump, as offsets from the aim axis. Spread wide
# enough to include the steep bank into the near boards — the delivery that
# makes a DZ clear legal — and dense enough that the corner it wraps into is
# resolved. Each bearing is one closed-form landing solve.
const DUMP_SEARCH_BEARINGS_RAD: Array = [
	-1.20, -0.90, -0.60, -0.30, 0.0, 0.30, 0.60, 0.90, 1.20,
]

# Launch PACES tried per bearing on the dump-IN, as fractions of the release
# band between the soft-touch floor (DEFAULT_WRISTER_POWER_MIN_M_S) and the pace
# the dumper can produce. Bearing alone cannot place a dump: every pace the bot
# can make out-slides the rink several times over, so where it stops is set by
# what the boards take out of it.
#
# Spaced toward the SOFT end, because runout goes as v² and the metre-scale
# placement lives in the first few m/s above the floor. Full pace stays as the
# last rung: a hard rim around the boards can genuinely beat a defender to the
# corner.
const DUMP_SEARCH_PACE_FRACS: Array = [0.0, 0.18, 0.45, 1.0]


# Does the KEEPER get to a puck resting at `spot` before our nearest chaser?
#
# `chase_recovery` sees skaters only, so without this a dump dying on the
# doorstep — the spot `position_potential` rates highest — reads as a free
# recovery.
#
# A straight race at both sides' real builds, no margin term: he leaves the
# paint at a keeper's pace (GOALIE_PUCK_PLAY_*, ramped from rest) and collects
# from a paddle's length; we run at skater pace. That bounds how far out the
# ice is his without a picked radius. Deliberately blind to the trip
# conditions the live keeper also weighs (net-front exclusion, cooldown, the
# tiered GO margin): each only makes him STAY, so ignoring them errs toward not
# feeding him.
static func keeper_collects_first(spot: Vector3, keeper_pos: Vector3,
		our_chasers: Array[Vector3], chaser_speed: float) -> bool:
	if our_chasers.is_empty():
		return true
	var ours: float = INF
	for c: Vector3 in our_chasers:
		ours = minf(ours, c.distance_to(spot))
	var keeper_dist: float = maxf(
			keeper_pos.distance_to(spot) - AIGoalieModel.GOALIE_PUCK_PLAY_REACH_M, 0.0)
	return GoalieBehaviorRules.travel_time_from_rest(
			keeper_dist, AIGoalieModel.GOALIE_PUCK_PLAY_SPEED_M_S, AIGoalieModel.GOALIE_PUCK_PLAY_ACCEL_M_S2) \
			<= ours / maxf(chaser_speed, 0.001)


# Hang time (s) of a release at `loft_level` — the airborne window, 2·vy/g;
# 0 for any level without a fixed vertical launch (FLAT, MID).
static func dump_loft_hang_s(loft_level: int) -> float:
	var vy: float = 0.0
	if loft_level == ShotMechanics.ELEVATION_LOW:
		vy = GameRules.DEFAULT_LOFT_VY_LOW_M_S
	elif loft_level == ShotMechanics.ELEVATION_HIGH:
		vy = GameRules.DEFAULT_LOFT_VY_HIGH_M_S
	return 2.0 * vy / GameRules.GRAVITY_M_S2


# The DZ clear: enumerate the launches it is LEGAL to make, and leave the
# choosing to the caller.
#
# Two refusals, both DOCTRINE rather than valuation — filters, never penalties
# a good enough price could outvote:
#   ICES — a launch that reaches their goal line starts a hybrid icing race.
#     Legality is bought by the PATH: a steep bank into the near boards sheds
#     pace on contact and lengthens the route, so the puck dies before the line.
#   DOESN'T CLEAR — a launch that comes to rest still inside our own zone.
#
# It does not CHOOSE among the survivors — `AICarrierDumpSearch.search` does, in
# CONCESSION. Never rank here by depth: that ranks in metres while the caller
# prices in concession.
#
# `out_vels` / `out_spots` are caller-owned and index-matched (the caller-owned
# out-param pattern — the search allocates nothing on the compete path). Returns
# the candidate count; 0 means no legal clear exists from here, which leaves the
# caller to decide what to do with a puck that cannot be cleared at all.
static func dump_clear_candidates(origin: Vector3, up_ice_dir: float,
		launch_speed: float, loft_level: int, our_net: Vector3,
		out_vels: Array[Vector3], out_spots: Array[Vector3]) -> int:
	var hang_s: float = dump_loft_hang_s(loft_level)
	# Their goal line is the one icing is judged at: up-ice of us.
	var their_line_z: float = up_ice_dir * GameRules.GOAL_LINE_Z
	var axis := Vector3(0.0, 0.0, up_ice_dir)
	out_vels.clear()
	out_spots.clear()
	for offset: float in DUMP_SEARCH_BEARINGS_RAD:
		var vel: Vector3 = axis.rotated(Vector3.UP, offset) * launch_speed
		var landing: Transform3D = AITrajectory.puck_release_landing(
				origin, vel, hang_s, their_line_z, up_ice_dir)
		if landing.basis.x.x > 0.5:
			continue
		if in_offensive_zone(landing.origin, our_net):
			continue  # dies in our own zone — that is not a clear
		out_vels.append(vel)
		out_spots.append(landing.origin)
	return out_spots.size()


# The NZ dump-in: search launches — BEARING x PACE — and take the one whose
# RESTING spot we are most likely to win. `out_landing` receives the chosen spot
# and `max_launch_speed` bounds the pace ladder (the top of the dumper's own
# release band); the returned velocity's LENGTH is the pace that won, which the
# release then has to actually fire at. Caller-owned out-param, so the search
# allocates nothing on the compete path.
#
# Scored as recovery × realized position value — the same realization
# discount every other future-value read pays, so the search optimizes what
# AICarrierDumpSearch prices. No icing branch: this dump is only offered past the red
# line, and icing requires a release from our own half.
static func solve_dump_in(origin: Vector3, attacking_goal: Vector3,
		max_launch_speed: float, loft_level: int,
		our_chasers: Array[Vector3], opp_chasers: Array[Vector3],
		keeper_pos: Vector3, out_landing: Array[Vector3],
		our_vels: Array[Vector3] = EMPTY_VEC3,
		opp_vels: Array[Vector3] = EMPTY_VEC3) -> Vector3:
	var hang_s: float = dump_loft_hang_s(loft_level)
	var goal_dir: float = signf(attacking_goal.z)
	var axis := Vector3(0.0, 0.0, goal_dir)
	var best_vel: Vector3 = Vector3.ZERO
	var best_score: float = -INF
	var best_spot: Vector3 = origin
	var floor_speed: float = GameRules.DEFAULT_WRISTER_POWER_MIN_M_S
	var band: float = maxf(max_launch_speed - floor_speed, 0.0)
	for offset: float in DUMP_SEARCH_BEARINGS_RAD:
		var dir: Vector3 = axis.rotated(Vector3.UP, offset)
		for frac: float in DUMP_SEARCH_PACE_FRACS:
			var vel: Vector3 = dir * (floor_speed + band * frac)
			var landing: Transform3D = AITrajectory.puck_release_landing(
					origin, vel, hang_s)
			var spot: Vector3 = landing.origin
			# A dump-in that does not get the puck deeper than we already are is
			# not a dump-in; it is a giveaway in the neutral zone.
			if goal_dir * (spot.z - origin.z) <= 0.0:
				continue
			# A puck the keeper collects is not a dump-in at any pace.
			if keeper_collects_first(spot, keeper_pos, our_chasers,
					AIArrival.SKATER_REF_SPEED_M_S):
				continue
			# What the spot is worth if we win it OUTRIGHT — the candidate's
			# ceiling, since recovery is a probability. A spot whose ceiling
			# already loses cannot win: an exact prune that keeps the pace
			# ladder affordable.
			var ceiling: float = position_potential(spot, attacking_goal, opp_chasers) \
					* potential_realization_discount(spot, attacking_goal)
			if ceiling <= best_score:
				continue
			# The race is run to where the puck STOPS.
			var recovery: float = chase_recovery(
					spot, our_chasers, opp_chasers, our_vels, opp_vels)
			var score: float = recovery * ceiling
			if score > best_score:
				best_score = score
				best_spot = spot
				best_vel = vel
	out_landing[0] = best_spot
	return best_vel
