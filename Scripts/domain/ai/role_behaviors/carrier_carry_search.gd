class_name AICarrierCarrySearch
extends RefCounted

# The carrier's CARRY: where to take the puck next — the candidate set (the
# field-derived forward fan, the rear ring, the slot anchor, zone-exit walls,
# post walkouts, the 5v5 wheel, the directed evasion seam, standing still),
# each scored on arrival value, the lane and safety of getting there and the
# pass option it opens, under a two-ply beam. AIRoleCarrier owns one over its
# AICarrierField, calls forward_space() then search() in the commit phase and
# reads the result fields; it never writes them.

var _field: AICarrierField

# ── Result of search() ───────────────────────────────────────────────────────
# The best plan's value floored at 0 (what the compete reads), where it goes,
# and the unfloored value (what the dump is judged against).
var value: float = 0.0
var anchor: Vector3 = Vector3.ZERO
var raw_value: float = 0.0


# ── Attacking blue-line keep-out bands ──────────────────────────────────────
# Physical measurements of how far play around the carried puck extends past
# the body: the offside puck-line is the TRUE blue line, while these decisions
# are made in body positions.
#
# RETREAT: how close to the line the OZ one-way valve lets a carry candidate
# sit (see _score_move_candidate_base). The charged pass windup sweeps the
# carried puck up to a stick's reach back from the body, and the ~135 ms charge
# drifts a still-retreating body further (~7 m/s × 0.135 s); parked closer, the
# puck crosses the line mid-pass and the pass lands the whole team offside.
const OZ_RETREAT_LINE_BUFFER_M: float = GameRules.DEFAULT_STICK_LENGTH_M + 1.0

# The local step a carry candidate is never placed inside: the floor on the
# beat-scaled forward radii, and the horizon the space fan is sampled over.
const CARRY_SEARCH_STEP_M: float = 3.0

# Post-walkout candidates — one just outside each post, a step onto the rink
# side of the goal line, generated only while the carrier is behind a goal line,
# where every other route out front crosses the cage and prunes. The lateral
# clearance is physical: post half-span + a carried body's half-width + blade
# slop.
const WALKOUT_POST_CLEARANCE_M: float = 0.9
const WALKOUT_FRONT_M: float = 0.7

# The WHEEL (5v5 only — breakout plan §B): from behind our own goal line, the
# carry around the BACK of the cage and out the far half-wall — the escape when
# the retriever has a step on the chaser. Priced as a two-leg carry through the
# behind-net apex (_score_wheel_candidate). Exit depth = the top of the low
# battle ice (the value of AIZoneCoverage.LOW_ZONE_DEPTH_M); apex = the middle
# of the behind-net alley (cage back + half the gap to the boards).
const WHEEL_EXIT_UP_ICE_M: float = 8.0
const WHEEL_APEX_CLEARANCE_M: float = 0.75

# Zone-exit wall routes — a long-range carry candidate up each boards lane to
# just past our own blue line, generated only in our defensive zone. The slot
# anchor, the only other long-range candidate, runs through center ice where a
# forecheck sets up, so without these a deep carrier with a clogged middle has
# only short steps and the backpass. The NZ lead puts the destination across
# the blue line — a completed exit.
const CARRY_EXIT_WALL_INSET_M: float = 2.0
const CARRY_EXIT_NZ_LEAD_M: float = 3.0

# REAR/LATERAL ring angles, relative to the carry direction — the half of the
# bearing circle the space fan does not span (it looks only ±70°, where the
# carrier is trying to GO). Each bearing is taken at two fractions of its own
# beat reach, so the near one is the local reposition and the far one the
# committed peel-out; at a fixed 3 m, straight back would be a shuffle inside
# the defender's re-close radius.
const _REAR_ANGLES: Array[float] = [
		PI * 0.5, PI * 0.75, PI, -PI * 0.75, -PI * 0.5,
]

# A rear candidate below this displacement is not a distinct plan: inside one
# stick length, "skate there" and "stand still and reach" are the same play,
# and stand-still and the directed evasion seam are always in the compete.
const CARRY_REAR_MIN_STEP_M: float = AICarrySpace.EVADE_STICK_REACH_M

# FIELD-DERIVED FORWARD CANDIDATES (see the generator in search).
# BEARINGS: how many of the space fan's 7 bearings become carry candidates,
# ranked by control × forward projection.
# RADII: fractions of the planning beat. Two of them, so the near gradient a
# standstill carrier steers on survives when the beat stretches out at speed.
# PLAN_BEAT_S: the horizon a carry candidate is a PLAN over rather than a
# steering nudge — one second of travel, which reduces to a 3 m local step at a
# standstill and reaches ~9 m at a full stride.
const CARRY_FIELD_BEARINGS: int = 3
const CARRY_FIELD_RADII: Array[float] = [0.5, 1.0]

const CARRY_PLAN_BEAT_S: float = 1.0

# ── Scratch buffers (reused across ticks, refilled per call) ────────────────
# Opponents projected to a carry candidate's arrival.
var _scratch_opponents_path: Array[Vector3] = []

# Two-leg (wheel/apex) projections: filled at the apex arrival time for the
# second leg's reach read, then refilled at destination arrival for that
# leg's lane/pressure read.
var _scratch_opponents_cont: Array[Vector3] = []

# Per-bearing control from the carrier's own forward-space read, filled every
# re-eval by forward_space and consumed by search's candidate
# generator, which overwrites entries as it takes them.
var _scratch_bearing_control: Array[float] = []

# ── Carry-candidate beam (two-ply search budget) ─────────────────────────────
# The two-ply pass-OPTION read is ~90% of a carry candidate's cost, and the
# exact incumbent-bound prunes lose their teeth in open ice, where safety/lane
# ≈ 1 for every spot. So pass 1 (_score_move_candidate_base) scores every
# candidate ONE-PLY — a strict LOWER bound on its full value, since the two-ply
# reads only ever RAISE a spot — and pass 2 (_upgrade_candidate_two_ply)
# completes the two-ply reads for the CARRY_BEAM_WIDTH best one-ply rows only,
# best-first, under the exact incumbent-bound prunes. The argmax is therefore
# approximate (a spot whose whole winning margin lives in the second ply can
# miss the beam) — a search-budget policy, not an evaluation-model change.
# Candidates outside the beam keep their one-ply totals, which can never win.
const CARRY_BEAM_WIDTH: int = 5

# Beam rows — one entry per base-scored candidate this re-eval, index-matched
# (cleared per search; clear() keeps capacity, so steady state allocates
# nothing).
var _beam_pos: Array[Vector3] = []
var _beam_total: Array[float] = []
var _beam_dest: Array[float] = []
var _beam_lane: Array[float] = []
var _beam_decay: Array[float] = []
var _beam_safety: Array[float] = []
var _beam_cost: Array[float] = []

# Pass-1 running prune bound: stand-still's secured total, tightened to the
# BEST one-ply total seen so far. Exact for the argmax even though it can prune
# candidates out of the beam: a candidate whose ceiling ≤ the best one-ply row
# can never out-upgrade that row, since upgrades only raise values. Reset per
# search.
var _beam_prune_bound: float = -INF

# Is a carry candidate on ice this bot can legally stand and handle on? In
# front of the net: rink side of both goal lines, a body's width off the boards.
#
# With `allow_behind` (the carrier is already behind a goal line) the ice back
# there is legal too, except what is genuinely illegal: off the playing surface
# (corners included) and inside the cage. Without it a carrier behind the net
# has no lateral move in the search — every local candidate fails the goal-line
# clamp — and plants on the end wall until stripped. The route to each candidate
# is still checked against the net by _score_move_candidate_base.
func _candidate_ice_legal(candidate: Vector3, allow_behind: bool) -> bool:
	if absf(candidate.x) > GameRules.RINK_HALF_WIDTH - AIRoleHelpers.RINK_INSET_M:
		return false
	if absf(candidate.z) <= GameRules.GOAL_LINE_Z - AIRoleHelpers.GOAL_LINE_BUFFER_M:
		return true
	if not allow_behind:
		return false
	# On the surface (rounded corners honoured) with a body's clearance.
	var xz := Vector2(candidate.x, candidate.z)
	if not GameRules.clamp_to_rink_inner(xz, AIRoleHelpers.RINK_INSET_M) \
			.is_equal_approx(xz):
		return false
	# Outside the cage (the same exclusion box the skater body is held clear of).
	return GameRules.push_out_of_net(xz).is_equal_approx(xz)


func _init(field: AICarrierField) -> void:
	_field = field


# Searches the best carry into the result fields. `value` is floored at 0, the
# "keep the puck" value for the fire compete; `raw_value` keeps the honest sign
# for the dump's residual test (a pinned carry that will be stripped must read
# negative). Candidates:
#   - Stand-still (current position)
#   - Up to 6 field-derived FORWARD candidates: the space fan's best bearings
#     at two fractions of the planning beat (see CARRY_FIELD_*)
#   - Up to 10 REAR/LATERAL candidates: the five bearings the fan does not
#     span, each at two fractions of that bearing's OWN beat reach (see
#     _REAR_ANGLES)
#   - The OZ slot anchor (long-range "drive at slot")
#   - Two zone-exit wall routes in our defensive zone (see CARRY_EXIT_*)
#   - Two post walkouts when behind either goal line (see WALKOUT_*)
#   - The objective-directed evasion seam
#   - Two WHEEL exits, 5v5, behind our own goal line (see WHEEL_*)
#
# Movement candidates are scored in TWO PASSES (see CARRY_BEAM_WIDTH); a
# candidate whose straight route crosses a net frame prunes (the walkouts are
# the exempt, around-the-post routes).
#
# `shoot_now_score` is the top-level SHOOT eval (pre-ping, pre-hysteresis):
# stand-still's shot branch shares it verbatim — see the stand-still block.
func search(ctx: RoleContext, shoot_now_score: float,
		directed_seam: Vector3) -> void:
	var self_pos: Vector3 = ctx.self_pos
	_field.holds.configure_from(ctx)
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	var own_goal_dir: float = ctx.own_goal_dir
	var our_goalie: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)
	var slot_pos: Vector3 = AICarrierField.slot_anchor(own_goal_dir)
	# Forward = toward the slot; the attacking-goal axis when the bot is on it.
	var to_slot_x: float = slot_pos.x - self_pos.x
	var to_slot_z: float = slot_pos.z - self_pos.z
	var to_slot_len_sq: float = to_slot_x * to_slot_x + to_slot_z * to_slot_z
	var fwd_x: float
	var fwd_z: float
	if to_slot_len_sq < 0.001:
		fwd_x = 0.0
		fwd_z = -own_goal_dir
	else:
		var inv: float = 1.0 / sqrt(to_slot_len_sq)
		fwd_x = to_slot_x * inv
		fwd_z = to_slot_z * inv

	# Stand-still is compared last and wins only if STRICTLY greater than every
	# movement candidate: resolving carry ties toward movement keeps the bot
	# from dawdling when slot-drive is the play.
	var best_pos: Vector3 = self_pos
	var best_score: float = -INF

	# Stand-still is COMPUTED up front because it doubles as an exact pruning
	# floor: it always participates in this argmax, so a movement candidate whose
	# ceiling can't strictly beat stand_total can't affect the outcome. It seeds
	# the beam's pass-1 prune bound and the wheel's bound.
	var stand_score: float = shoot_now_score
	if not AIActionScoring.in_offensive_zone(self_pos, attacking_goal):
		var stand_potential: float = AIActionScoring.position_potential(
				self_pos, attacking_goal, _field.opponents)
		var stand_realization: float = AIActionScoring.potential_realization_discount(
				self_pos, attacking_goal)
		stand_score = maxf(stand_score, stand_potential * stand_realization)
	var stand_puck_pos: Vector3 = AICarrierField.puck_pos_at(self_pos, attacking_goal)
	var stand_safety: float = AICarrySpace.carry_safety(
			stand_puck_pos, stand_puck_pos, AICarrySpace.EVADE_HORIZON_S,
			_field.opponents, _field.opponent_vels, _field.opponent_caps)
	var stand_cost: float = _field.turnover_cost(ctx, stand_puck_pos,
			1.0 - stand_safety, our_goalie)
	stand_cost += _field.counter_exposure_cost(ctx, stand_puck_pos,
			1.0 - stand_safety, self_pos, our_goalie)
	var stand_total: float = stand_score * stand_safety - stand_cost

	# ── Pass 1 (beam base): one-ply rows for every legal candidate ───────────
	# Candidates stay ordered forward-first: the prune bound tightens to the
	# best one-ply total as rows land (see _beam_prune_bound), so a strong early
	# spot prunes the tail cheaply.
	_beam_pos.clear()
	_beam_total.clear()
	_beam_dest.clear()
	_beam_lane.clear()
	_beam_decay.clear()
	_beam_safety.clear()
	_beam_cost.clear()
	_beam_prune_bound = stand_total

	var behind_net: bool = absf(self_pos.z) > GameRules.GOAL_LINE_Z

	# FORWARD candidates — the top CARRY_FIELD_BEARINGS bearings of the space
	# field's per-bearing profile (_scratch_bearing_control), each at
	# CARRY_FIELD_RADII fractions of one planning beat of travel at the
	# carrier's real speed. Ranked by control × forward projection: control
	# alone would rate a wide-open sideways bearing above a merely-good netward
	# one, and the cos is the foreshortening the space aggregate itself uses.
	# See Scripts/domain/ai/CLAUDE.md → "Field-derived carry candidates".
	var beat_r: float = clampf(
			ctx.self_max_speed * CARRY_PLAN_BEAT_S,
			CARRY_SEARCH_STEP_M, AICarrierField.FORWARD_PRESSURE_HORIZON_M)
	if ctx.self_velocity.length_squared() > 1.0:
		beat_r = clampf(
				sqrt(ctx.self_velocity.x * ctx.self_velocity.x
						+ ctx.self_velocity.z * ctx.self_velocity.z) * CARRY_PLAN_BEAT_S,
				CARRY_SEARCH_STEP_M, AICarrierField.FORWARD_PRESSURE_HORIZON_M)
	for _rank: int in CARRY_FIELD_BEARINGS:
		var best_bi: int = -1
		var best_w: float = -1.0
		for bi: int in _scratch_bearing_control.size():
			var ang: float = AICarrySpace.SPACE_SAMPLE_ANGLES[bi]
			var wgt: float = _scratch_bearing_control[bi] * cos(ang)
			if wgt > best_w:
				best_w = wgt
				best_bi = bi
		if best_bi < 0:
			break
		var angle: float = AICarrySpace.SPACE_SAMPLE_ANGLES[best_bi]
		# Consume it so the next rank picks a different bearing.
		_scratch_bearing_control[best_bi] = -1.0
		var c: float = cos(angle)
		var s_a: float = sin(angle)
		var dir_x: float = fwd_x * c - fwd_z * s_a
		var dir_z: float = fwd_x * s_a + fwd_z * c
		for frac: float in CARRY_FIELD_RADII:
			var r: float = maxf(beat_r * frac, CARRY_SEARCH_STEP_M * 0.5)
			var candidate := Vector3(
					self_pos.x + dir_x * r, 0.0, self_pos.z + dir_z * r)
			if not _candidate_ice_legal(candidate, behind_net):
				continue
			_beam_score_base(ctx, candidate, our_goalie, false)

	# REAR/LATERAL ring (see _REAR_ANGLES). The radius is per BEARING, never the
	# forward beat_r: reusing it would grow the rear radii with speed, precisely
	# backwards — at pace a spot behind you costs shedding cross-speed, braking
	# out the reversal and re-accelerating. beat_reach_along returns negative
	# for a bearing off the reachable disc, so an unavailable direction produces
	# no candidate.
	for angle: float in _REAR_ANGLES:
		var c: float = cos(angle)
		var s_a: float = sin(angle)
		var dir_x: float = fwd_x * c - fwd_z * s_a
		var dir_z: float = fwd_x * s_a + fwd_z * c
		var reach: float = AICarrySpace.beat_reach_along(
				ctx.self_velocity, dir_x, dir_z, ctx.self_max_accel,
				CARRY_PLAN_BEAT_S)
		if reach < CARRY_REAR_MIN_STEP_M:
			continue
		for frac: float in CARRY_FIELD_RADII:
			var step: float = reach * frac
			if step < CARRY_REAR_MIN_STEP_M:
				continue
			var candidate := Vector3(
					self_pos.x + dir_x * step, 0.0, self_pos.z + dir_z * step)
			if not _candidate_ice_legal(candidate, behind_net):
				continue
			_beam_score_base(ctx, candidate, our_goalie, false)

	# Slot anchor — the long-range candidate, valid from anywhere on the rink.
	_beam_score_base(ctx, slot_pos, our_goalie, false)

	# Zone-exit wall routes (see CARRY_EXIT_*), only in our own DEFENSIVE ZONE:
	# never gate on own HALF, because past our blue line the exit target sits
	# BEHIND the carrier.
	if own_goal_dir * self_pos.z > GameRules.BLUE_LINE_Z:
		var exit_x: float = GameRules.RINK_HALF_WIDTH - CARRY_EXIT_WALL_INSET_M
		var exit_z: float = own_goal_dir * (GameRules.BLUE_LINE_Z - CARRY_EXIT_NZ_LEAD_M)
		_beam_score_base(ctx, Vector3(exit_x, 0.0, exit_z), our_goalie, false)
		_beam_score_base(ctx, Vector3(-exit_x, 0.0, exit_z), our_goalie, false)

	# Post walkouts (see WALKOUT_*): one outside each post; EV picks the side.
	if absf(self_pos.z) > GameRules.GOAL_LINE_Z:
		var behind_sign: float = signf(self_pos.z)
		var walk_z: float = behind_sign * (GameRules.GOAL_LINE_Z - WALKOUT_FRONT_M)
		var walk_x: float = GameRules.NET_HALF_WIDTH + WALKOUT_POST_CLEARANCE_M
		for side: float in [-1.0, 1.0]:
			_beam_score_base(
					ctx, Vector3(side * walk_x, 0.0, walk_z), our_goalie, true)

	# The objective-directed evasion seam (see evade_seam_world): the bot cuts
	# past a committed defender into the lane he vacates, and it wins only when
	# that space is worth carrying to.
	_beam_score_base(ctx, directed_seam, our_goalie, false)

	# ── Pass 2: complete the two-ply reads for the beam's best rows ──────────
	# Best-first, consuming each row as it upgrades. Rows outside the beam never
	# enter best_score (see CARRY_BEAM_WIDTH).
	for rank: int in CARRY_BEAM_WIDTH:
		var bi: int = -1
		var bt: float = -INF
		for j: int in _beam_total.size():
			if _beam_total[j] > bt:
				bt = _beam_total[j]
				bi = j
		if bi == -1:
			break
		var up_total: float = _upgrade_candidate_two_ply(ctx, bi)
		if up_total > best_score:
			best_score = up_total
			best_pos = _beam_pos[bi]
		_beam_total[bi] = -INF   # consumed — next rank takes the next-best row

	# WHEEL exits (see WHEEL_*), only for destinations whose straight route the
	# cage blocks — a side the straight line reaches is already covered above.
	# Already a complete two-leg read, so it competes after the beam.
	if absf(self_pos.z) > GameRules.GOAL_LINE_Z \
			and ctx.team_size >= 5 and own_goal_dir * self_pos.z > 0.0:
		var wheel_x: float = GameRules.RINK_HALF_WIDTH - CARRY_EXIT_WALL_INSET_M
		var wheel_z: float = own_goal_dir \
				* (GameRules.GOAL_LINE_Z - WHEEL_EXIT_UP_ICE_M)
		for side: float in [-1.0, 1.0]:
			var wheel := Vector3(side * wheel_x, 0.0, wheel_z)
			if not AINetObstacle.carry_path_blocked_by_net(self_pos, wheel):
				continue
			var wheel_total: float = _score_wheel_candidate(
					ctx, wheel, our_goalie, maxf(best_score, stand_total))
			if wheel_total > best_score:
				best_score = wheel_total
				best_pos = wheel

	# Stand-still last, winning only on STRICTLY greater. Its shot branch is the
	# shoot-now score verbatim because "hold and fire from here" and SHOOT are the
	# same physical act; priced separately at the CURRENT spot, a mid-cut hold
	# would read richer than the fire from the same instant and the bot would
	# hold exactly when the window is open. Sharing it makes fire-wins-ties hold
	# by definition: stand_total = shoot_now × safety − cost ≤ shoot_now ≤ fire.
	# Stand pays the strip cost like every candidate; without it freezing would be
	# the one option that never prices losing the puck, and a bot under a
	# converging forechecker would plant itself exactly when it should skate clear.
	if stand_total > best_score:
		best_score = stand_total
		best_pos = self_pos

	value = maxf(best_score, 0.0)
	anchor = best_pos
	raw_value = best_score


# Pass-1 candidate entry (see CARRY_BEAM_WIDTH): base-score `candidate` into
# the beam rows and tighten the running prune bound to the best one-ply
# total so far (see _beam_prune_bound for why that stays exact).
func _beam_score_base(ctx: RoleContext, candidate: Vector3,
		our_goalie: Vector3, is_post_walkout: bool) -> void:
	var total: float = _score_move_candidate_base(
			ctx, candidate, our_goalie, is_post_walkout, _beam_prune_bound)
	if total > _beam_prune_bound:
		_beam_prune_bound = total


# One-ply EV of one movement carry candidate — the scoring every non-stand-still
# candidate in the beam runs:
#
#   dest_score × lane × decay × safety − turnover_cost
#
# `safety` is the reachable clearance over the PUCK's path to the candidate
# across the arrival time, so it sees both a defender converging on the ROUTE
# and one waiting at the DESTINATION; a committed charger whose momentum
# carries him past reads as clear. 1 − safety is the strip probability, priced
# at the EARLIEST covered point on the route (carry_strip_point), not the
# destination: a carry that ends in open ice but threads our own slot pays the
# slot's turnover cost.
#
# Returns -INF for an illegal or unreachable candidate, or one whose ceiling
# cannot beat `best_so_far`. Every finite score appends a beam row stashing the
# intermediates _upgrade_candidate_two_ply needs, so pass 2 recomputes nothing.
func _score_move_candidate_base(ctx: RoleContext, candidate: Vector3,
		our_goalie: Vector3, is_post_walkout: bool = false,
		best_so_far: float = -INF) -> float:
	var self_pos: Vector3 = ctx.self_pos
	# One-way valve: once in the offensive zone, don't carry the puck back out,
	# buffered by OZ_RETREAT_LINE_BUFFER_M. Stand-still never trips this, so the
	# candidate set is never empty; a carrier already inside the band keeps only
	# deeper candidates, easing it off the line.
	if AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(
					candidate, ctx.attacking_goal_pos, OZ_RETREAT_LINE_BUFFER_M):
		return -INF
	# Its NHL mirror: with a teammate owing a tag-up, carrying in is whistled at
	# once. Judged on the body, so stand-still (outside) always survives; the last
	# stick of puck lead is the steering's offside brake on the puck.
	if ctx.zone_entry_blocked \
			and AIActionScoring.in_offensive_zone(candidate, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos):
		return -INF
	# The cage is a wall: the time/lane/safety math below assumes the straight
	# traverse. POST-WALKOUT candidates are exempt — they are reached around the
	# post (the steering's net detour), which the straight-segment test can't see.
	if not is_post_walkout \
			and AINetObstacle.carry_path_blocked_by_net(self_pos, candidate):
		return -INF
	var local_time: float = AIArrival.time_to_arrive(
			self_pos, candidate, ctx.self_velocity, ctx.self_max_speed,
			ctx.self_max_accel, ctx.self_lateral_grip)
	# CEILING PRUNES (exact): with dest_score ≤ 1 and cost ≥ 0, each partial
	# product of the ≤ 1 factors is a hard upper bound, checked in cost order —
	# decay alone before the opponent projection, × lane before the safety read,
	# × safety before the arrival-shot / strip machinery. Under pressure SAFETY
	# is the killer, so a swarmed carrier doesn't pay full price for doomed spots.
	var decay: float = AIActionScoring.delay_discount(local_time)
	if decay <= best_so_far:
		return -INF
	_field.project_opponents(local_time, _scratch_opponents_path)
	var lane: float = AICarrySpace.carry_lane_clearance(
			self_pos, candidate, local_time, _field.opponents, _field.opponent_vels,
			ctx.self_max_speed)
	if lane <= 0.0:
		return -INF
	if lane * decay <= best_so_far:
		return -INF
	var cand_puck_pos: Vector3 = AICarrierField.puck_pos_at(candidate, ctx.attacking_goal_pos)
	var cur_puck_pos: Vector3 = AICarrierField.puck_pos_at(self_pos, ctx.attacking_goal_pos)
	# apply_escape: a defender the carrier out-skates on this drive can't sustain
	# the strip, so driving PAST a man reads as winnable, not as a wall.
	var safety: float = AICarrySpace.carry_safety(
			cur_puck_pos, cand_puck_pos, local_time,
			_field.opponents, _field.opponent_vels, _field.opponent_caps,
			true)
	if lane * decay * safety <= best_so_far:
		return -INF
	# The candidate's shot is taken ARRIVING AT PACE (carry steps are skated at
	# speed; the arrival brake skips carry waypoints), so it is the same
	# moving-release wrister the shoot-now eval prices. Two-phase keeper:
	#   1. TRACK: he follows the whole carry to the candidate's arc-square
	#      (generous to him: he never falls behind en route).
	#   2. FINAL RACE: from that square he races the wind-up + flight against a
	#      release still sliding at the arrival speed — the race a hard lateral
	#      cut in tight genuinely wins.
	# Phase 2 is what gives a STANDSTILL 1v1 a gradient toward building the
	# lateral speed that opens the window; a static release would score every
	# one-step spot against a set keeper ~0. Because he is SQUARE at every
	# candidate before the final race, a further cut never prices more than the
	# last-quarter-second window, so the cut cannot recede forever.
	#
	# The arrival UNSETTLE is read from the TRACKED keeper over the FINAL window
	# only: the carry never catches him, only the re-square the release demands
	# can. Never measure it from his CURRENT position over the whole carry — that
	# charges him for a swing his tracking already covers and makes every
	# doorstep drive a phantom caught-moving goalie.
	var to_cand: Vector3 = candidate - self_pos
	to_cand.y = 0.0
	var cand_dist: float = to_cand.length()
	var arrive_vel: Vector3 = Vector3.ZERO
	if cand_dist > 0.001 and local_time > 0.001:
		# Arrival pace consistent with time_to_arrive's constant-effective-speed
		# travel model, capped at this bot's real top end.
		var arrive_speed: float = minf(cand_dist / local_time, ctx.self_max_speed)
		arrive_vel = to_cand * (arrive_speed / cand_dist)
	# The shot on arrival is held as the shoot-now sweep would hold it
	# (arrival_hold_wait): at that hold's pace and keep odds, with any pull the
	# carry is too short for waited out in the wind-up the keeper races.
	var cand_wait: float = 0.0
	var cand_share: float = 1.0
	var cand_keep: float = 1.0
	if AICarrierField.shot_reads(ctx, self_pos,
			candidate + arrive_vel * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S):
		cand_wait = _field.arrival_hold_wait(ctx, candidate, arrive_vel, local_time)
		cand_share = _field.holds.arrival_share
		cand_keep = _field.holds.arrival_keep
	var cand_speed: float = ctx.self_wrister_shot_speed * cand_share
	var cand_windup: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + cand_wait
	# The keeper backs in as the carry closes on him (the planning depth model).
	# Closing is the rate this carry shortens the puck's distance to the goal.
	var carry_closing: float = (self_pos.distance_to(ctx.attacking_goal_pos)
			- candidate.distance_to(ctx.attacking_goal_pos)) / maxf(local_time, 0.001)
	var tracked_goalie: Vector3 = AIGoalieModel.predict_goalie_pos(
			AICarrierField.goalie_now(ctx), ctx.attacking_goal_pos, local_time, candidate,
			carry_closing)
	var cand_release: Vector3 = AIGoalieModel.release_ahead_of_goalie(
			candidate + arrive_vel * cand_windup,
			ctx.attacking_goal_pos, tracked_goalie)
	var cand_flight: float = cand_release.distance_to(ctx.attacking_goal_pos) \
			/ maxf(cand_speed, 1.0)
	# Same expected-lateness budget as the shoot-now sweep (timing error × 0.5),
	# and the keeper still backing in over the wind-up + flight at the arrival
	# pace.
	var release_closing: float = AIGoalieModel.closing_toward(
			candidate, arrive_vel, ctx.attacking_goal_pos)
	var cand_goalie: Vector3 = AIGoalieModel.predict_goalie_pos(
			tracked_goalie, ctx.attacking_goal_pos,
			cand_windup + cand_flight + ctx.shot_timing_error_s * 0.5,
			cand_release, release_closing)
	var cand_unsettled: float = 0.0
	if ctx.reads_goalie_motion:
		cand_unsettled = AIGoalieModel.goalie_unsettled(
				tracked_goalie, ctx.attacking_goal_pos,
				cand_windup + cand_flight + ctx.shot_timing_error_s * 0.5,
				cand_release, release_closing)
	# Displacement at the release: from where he is NOW over everything the play
	# gives him — carry, wind-up and flight. Measured at the DESTINATION, never as
	# a max over route samples: the ~30 Hz re-decide already re-prices the shot
	# at every point on the route, and a max over samples is optimistically
	# biased against the shoot and pass legs, which get one estimate each.
	var release_t: float = local_time + cand_windup + cand_flight \
			+ ctx.shot_timing_error_s * 0.5
	var cand_displacement: float = AIShotValue.displacement_deficit_m(
			AICarrierField.goalie_now(ctx), ctx.attacking_goal_pos, cand_release, release_t)
	var dest_score: float = _field.value_at(ctx, cand_release, self_pos,
			_scratch_opponents_path, cand_goalie,
			cand_speed, cand_unsettled, ctx.self_aim_spread_rad,
			cand_displacement, ctx.self_loft_tans.z, cand_keep)
	# ENTRY CONTINUATION: from outside the zone an in-zone candidate is worth what
	# a carrier there does next — the drive-in from it, priced in the in-zone
	# regime and starting when we arrive — which its own shot xG badly
	# understates just inside the line.
	if AIActionScoring.in_offensive_zone(candidate, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos):
		dest_score = maxf(dest_score, AICarrierField.entry_value(_field.receiver_drive_in_value(
				ctx, candidate, ctx.self_wrister_shot_speed,
				ctx.caps_by_peer.get(ctx.peer_id), arrive_vel, candidate, local_time, true)))
	var keep_prob: float = safety
	var cost: float = 0.0
	# A fully safe route (the common open-ice case) skips localizing a strip
	# that cannot happen.
	if keep_prob < 1.0:
		var strip_point: Vector3 = AICarrySpace.carry_strip_point(
				cur_puck_pos, cand_puck_pos, local_time,
				_field.opponents, _field.opponent_vels, _field.opponent_caps, true)
		cost = _field.turnover_cost(ctx, strip_point,
			1.0 - keep_prob, our_goalie)
		# Transition exposure (5v5): the carrier's recovery race starts from the
		# CANDIDATE, the spot this carry commits him to.
		cost += _field.counter_exposure_cost(ctx, strip_point, 1.0 - keep_prob,
				candidate, our_goalie)
	var total: float = dest_score * lane * decay * safety - cost
	# Beam row: this candidate's final value unless pass 2 upgrades it.
	_beam_pos.append(candidate)
	_beam_total.append(total)
	_beam_dest.append(dest_score)
	_beam_lane.append(lane)
	_beam_decay.append(decay)
	_beam_safety.append(safety)
	_beam_cost.append(cost)
	return total


# TWO-PLY pass of the beam (see CARRY_BEAM_WIDTH): completes beam row `i` with
# the pass OPTION the spot opens (pass_option_from), credited as the
# IMPROVEMENT over the same read at the current spot — a lane already open from
# here is the live pass's to take, so holding a cashable option is never a
# reason to keep carrying. CEILING PRUNE (exact): the credit can't exceed
# _field.pass_option_ceiling − _field.pass_option_at_self, so when that can't raise
# dest_score the per-receiver lane loop is skipped.
func _upgrade_candidate_two_ply(ctx: RoleContext, i: int) -> float:
	var candidate: Vector3 = _beam_pos[i]
	var dest_score: float = _beam_dest[i]
	var lane: float = _beam_lane[i]
	var decay: float = _beam_decay[i]
	var safety: float = _beam_safety[i]
	if _field.pass_option_ceiling - _field.pass_option_at_self > dest_score:
		dest_score = maxf(dest_score, maxf(
				0.0, _field.pass_option_from(ctx, candidate,
						dest_score + _field.pass_option_at_self) - _field.pass_option_at_self))
	return dest_score * lane * decay * safety - _beam_cost[i]


# FULL eval of a single candidate — base + two-ply upgrade in one call, for the
# single-candidate consumers (unit tests, the ai_micro bench); the compete runs
# the two-pass beam form. Leaves the candidate's row in the beam scratch, which
# the next search clears.
func _score_move_candidate(ctx: RoleContext, candidate: Vector3,
		our_goalie: Vector3, is_post_walkout: bool = false,
		best_so_far: float = -INF) -> float:
	var rows_before: int = _beam_total.size()
	var base: float = _score_move_candidate_base(
			ctx, candidate, our_goalie, is_post_walkout, best_so_far)
	if _beam_total.size() == rows_before:
		return base   # ceiling-pruned — no row to upgrade
	return _upgrade_candidate_two_ply(ctx, _beam_total.size() - 1)


# EV of a WHEEL candidate (see WHEEL_*): the two-leg carry self → the behind-net
# apex → the far half-wall exit. The same pricing pieces as
# _score_move_candidate_base, applied PER LEG with the defense projected through
# leg one, because a straight-line read for this route would sample the inside
# of the cage. The escape gate (apply_escape) makes a committed same-side chaser
# read as beaten, while a body already waiting on the far side kills leg two.
func _score_wheel_candidate(ctx: RoleContext, dest: Vector3,
		our_goalie: Vector3, best_so_far: float) -> float:
	var self_pos: Vector3 = ctx.self_pos
	var apex := Vector3(0.0, 0.0, ctx.own_goal_dir
			* (GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH + WHEEL_APEX_CLEARANCE_M))
	var t1: float = AIArrival.time_to_arrive(
			self_pos, apex, ctx.self_velocity, ctx.self_max_speed,
			ctx.self_max_accel, ctx.self_lateral_grip)
	# Carry pace through the apex, consistent with the arrival model.
	var to_dest: Vector3 = dest - apex
	to_dest.y = 0.0
	var apex_speed: float = minf(
			self_pos.distance_to(apex) / maxf(t1, 0.001), ctx.self_max_speed)
	var v_apex: Vector3 = to_dest.normalized() * apex_speed \
			if to_dest.length_squared() > 0.0001 else Vector3.ZERO
	var t2: float = AIArrival.time_to_arrive(
			apex, dest, v_apex, ctx.self_max_speed, ctx.self_max_accel, ctx.self_lateral_grip)
	# The same exact ceiling ladder as _score_move_candidate_base, per leg.
	var decay: float = AIActionScoring.delay_discount(t1 + t2)
	if decay <= best_so_far:
		return -INF
	var lane1: float = AICarrySpace.carry_lane_clearance(
			self_pos, apex, t1, _field.opponents, _field.opponent_vels,
			ctx.self_max_speed)
	if lane1 <= 0.0 or lane1 * decay <= best_so_far:
		return -INF
	var cur_puck: Vector3 = AICarrierField.puck_pos_at(self_pos, ctx.attacking_goal_pos)
	var apex_puck: Vector3 = AICarrierField.puck_pos_at(apex, ctx.attacking_goal_pos)
	var dest_puck: Vector3 = AICarrierField.puck_pos_at(dest, ctx.attacking_goal_pos)
	var safety1: float = AICarrySpace.carry_safety(
			cur_puck, apex_puck, t1, _field.opponents,
			_field.opponent_vels, _field.opponent_caps, true)
	if lane1 * decay * safety1 <= best_so_far:
		return -INF
	# Leg two starts where the defense has skated to during leg one.
	_field.project_opponents(t1, _scratch_opponents_cont)
	var lane2: float = AICarrySpace.carry_lane_clearance(
			apex, dest, t2, _scratch_opponents_cont, _field.opponent_vels,
			ctx.self_max_speed)
	if lane2 <= 0.0:
		return -INF
	var safety2: float = AICarrySpace.carry_safety(
			apex_puck, dest_puck, t2, _scratch_opponents_cont,
			_field.opponent_vels, _field.opponent_caps, true)
	var keep: float = safety1 * safety2
	var ceiling: float = lane1 * lane2 * decay * keep
	if ceiling <= best_so_far:
		return -INF
	_field.project_opponents(t1 + t2, _scratch_opponents_cont)
	var dest_score: float = _field.value_at(ctx, dest, self_pos,
			_scratch_opponents_cont, AICarrierField.goalie_now(ctx),
			ctx.self_wrister_shot_speed, 0.0, ctx.self_aim_spread_rad, 0.0,
			ctx.self_loft_tans.z)
	var benefit: float = dest_score * ceiling
	if keep >= 1.0:
		return benefit
	# The strip is priced on whichever leg is the unsafe one.
	var strip_point: Vector3
	if safety1 <= safety2:
		strip_point = AICarrySpace.carry_strip_point(
				cur_puck, apex_puck, t1, _field.opponents,
				_field.opponent_vels, _field.opponent_caps, true)
	else:
		_field.project_opponents(t1, _scratch_opponents_cont)
		strip_point = AICarrySpace.carry_strip_point(
				apex_puck, dest_puck, t2, _scratch_opponents_cont,
				_field.opponent_vels, _field.opponent_caps, true)
	var cost: float = _field.turnover_cost(ctx, strip_point,
			1.0 - keep, our_goalie)
	cost += _field.counter_exposure_cost(ctx, strip_point, 1.0 - keep, dest, our_goalie)
	return benefit - cost


# How much room the carrier has to OPERATE toward the attacking objective —
# the controlled fraction of the forward cone over AICarrierField.FORWARD_PRESSURE_HORIZON_M
# (AICarrySpace.controlled_space), 1.0 when the ice ahead is his. Feeds the
# carry's pass-first discount (see FORWARD_PRESSURE_*) and, as a by-product,
# _scratch_bearing_control.
func forward_space(ctx: RoleContext) -> float:
	# Size once, then reuse: controlled_space refills every entry each call.
	if _scratch_bearing_control.size() != AICarrySpace.SPACE_SAMPLE_ANGLES.size():
		_scratch_bearing_control.resize(
				AICarrySpace.SPACE_SAMPLE_ANGLES.size())
	return AICarrySpace.controlled_space(
			ctx.self_pos, ctx.self_velocity, ctx.caps_by_peer.get(ctx.peer_id),
			ctx.attacking_goal_pos, AICarrierField.FORWARD_PRESSURE_HORIZON_M,
			_field.opponents, _field.opponent_vels, _field.opponent_caps,
			_scratch_bearing_control)
