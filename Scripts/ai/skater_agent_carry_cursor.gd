class_name SkaterAgentCarryCursor
extends RefCounted

# Where a carrier's blade cursor goes while he deliberates: the carry aim (the
# presented puck, faced to the route or squared to the net, shifted off the
# nearest blade and blended toward the shield seam), or the hold of the release
# he is close to — the live shot look's, or the leading pass's when nothing
# forces him to evade. Resting the puck in that hold means the press finds it
# loaded. The state machine steps the cursor toward the target and reads `mode`
# for how to step it; it never writes these fields.
#
# The hold this aims at during the carry is the one the press aims at once the
# intent commits (the carrier's shoot_now_hold / pass_now_hold are what it locks
# as shot_hold_offset / pass_hold_offset): if the two differed the target would
# jump at commit and the motion-limited cursor could blow past the pre-aim wait.

# Behind-the-net cradle. A full CARRY_BLADE_AIM_FORWARD_M reach from behind the
# attacking cage chords the blade into the mesh, and stick-on-net contact strips
# the carried puck. The forward reach shortens toward CARRY_BEHIND_NET_CRADLE_M as
# the body enters the net's work zone (the frame's lateral span plus a margin,
# ramping in over CARRY_BEHIND_NET_BAND_M across the goal line). This is the SOFT
# layer; the puck pin's net collision (SkaterController) is the hard backstop.
# A hold overrides carry aim, so a net-front shot is never blunted. Feel
# constants.
const CARRY_BEHIND_NET_CRADLE_M: float = 0.6
const CARRY_BEHIND_NET_BAND_M: float = 0.6      # ramp band around the goal line
const CARRY_BEHIND_NET_LATERAL_M: float = 1.0   # lateral reach past the frame side still cradled


# Stickhandling: shift the carrier's mouse perpendicular to the attacking-goal
# aim, AWAY from the nearest opposing blade, measured blade-tip to puck (as the
# poke is). Full offset inside STICKHANDLE_FULL_OFFSET_RADIUS_M, tapering to zero
# at STICKHANDLE_THREAT_RADIUS_M. Not gated on closing velocity: a still defender
# with his stick out is as much a poke threat as one skating in.
#
# QUIET HANDS: body facing chases the carry cursor, so a sustained offset becomes
# body rotation — 0.33 m on the 1.3 m ring is ~±14° of wag; wider turns a threat
# crossing the line into a twitchy ~44° swing. The big threats belong to the
# deliberate answers (protect blend, the rolled carry). Ring metres —
# rescale with CARRY_BLADE_AIM_FORWARD_M.
const STICKHANDLE_THREAT_RADIUS_M: float = 3.0
const STICKHANDLE_FULL_OFFSET_RADIUS_M: float = 1.5
const STICKHANDLE_OFFSET_MAX_M: float = 0.33

# Face-the-route gates (the FACE THE ROUTE block in carry_aim).
# ROUTE_MIN_DIST: below this the anchor is underfoot, so face the play.
# RETREAT_ADVANCE: the route's advance component along the attack axis below
# which it is a genuine retreat (face the play and back out); −0.3 keeps lateral
# and shallow-back routes faced. Feel choices.
const CARRY_FACE_ROUTE_MIN_DIST_M: float = 1.0
const CARRY_FACE_RETREAT_ADVANCE: float = -0.3

# "Man to beat" bar (has_man_to_beat / the O-ZONE SQUARE block in carry_aim):
# the carrier still has a man to beat while the presented-forward puck has less
# than this much room (AIRoleCarrier.forward_puck_clearance) from the nearest
# un-beaten stick; in the offensive zone with nobody to beat, the body squares
# to the net. A blade of real air — the same bar every other "is this puck safe"
# read uses, so the facing and the shield cannot disagree. Tier-agnostic: it
# needs no protect read.
const CARRY_MAN_TO_BEAT_CLEAR_M: float = AICarrySpace.EVADE_SAFE_CLEAR_MIN_M
# Once a man is engaged the bar rises by this, so a defender riding the boundary
# doesn't flip the carry-aim forward direction every re-eval. Debounce.
const CARRY_MAN_TO_BEAT_HYSTERESIS_M: float = 0.5 * GameRules.DEFAULT_BLADE_LENGTH_M

# How far off the play line the protect aim may swing the body. Facing chases
# the carry cursor, so aiming straight at a seam on the far hip spins the carrier
# out of the play; capped at side-on, the body turns just enough to interpose and
# the blade's ~157° reach cone extends to the seam from there. Feel tunable.
const CARRY_PROTECT_MAX_TURN_DEG: float = 90.0
# Rate (1/s) the shield blend eases toward the carrier mirror's raw protect_gain /
# protect_offset (~125 ms time constant), so a defender crossing the screen filter
# (a hard on/off) ramps the blade instead of snapping it. Feel tunable.
const CARRY_PROTECT_SMOOTH_RATE: float = 8.0

# A shot look is tracked once it is worth this much and leads the pass.
const FIRE_AIM_THRESHOLD: float = 0.05
# Debounce band for every mode flip. ABSOLUTE, not the proportional
# AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC: it filters wobble around a fixed
# bar, and a fraction of a near-zero score would be a near-zero band.
const FIRE_AIM_HYSTERESIS_BAND: float = 0.05
# The shield is "barely on" under this (the smoothed protect gain, the safety it
# buys): above it the blade belongs on the seam, not in a release's pocket.
# Feel tunable.
const PASS_LOAD_MAX_SHIELD: float = 0.1

enum Mode { CARRY, SHOT, PASS }

# What the last target() aimed at, sticky across close scores.
var mode: Mode = Mode.CARRY

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
# The shield, low-passed toward the carrier's raw protect_gain / protect_offset
# at CARRY_PROTECT_SMOOTH_RATE.
var _protect_gain_smooth: float = 0.0
var _protect_offset_smooth: Vector3 = Vector3.ZERO
# Latched side of the man-to-beat contest (has_man_to_beat).
var _has_man: bool = false
var _scratch_opp_ids: Array[int] = []


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer


# A fresh carry: no hold tracked, no shield, no man engaged.
func reset() -> void:
	mode = Mode.CARRY
	_protect_gain_smooth = 0.0
	_protect_offset_smooth = Vector3.ZERO
	_has_man = false


# Whether the last target() was a release's hold rather than the carry aim.
func holds_puck() -> bool:
	return mode != Mode.CARRY


# The cursor's target while carrying (world): the live shot look's hold while
# it is clearly past FIRE_AIM_THRESHOLD and leads the pass; else the leading
# pass's hold while it is worth loading (_should_load_pass); else the carry aim.
func target(snapshot: WorldSnapshot, self_pos: Vector3, carrier: AIRoleCarrier,
		attacking_goal: Vector3, own_goal_dir: float, blade_reach: float,
		protects_the_puck: bool, delta: float) -> Vector3:
	var band: float = FIRE_AIM_HYSTERESIS_BAND if mode == Mode.SHOT else -FIRE_AIM_HYSTERESIS_BAND
	var shot: float = carrier.debug_shoot_score
	if carrier.shoot_now_hold != Vector3.ZERO and shot >= FIRE_AIM_THRESHOLD - band \
			and shot >= carrier.debug_pass_score - band:
		mode = Mode.SHOT
		return self_pos + carrier.shoot_now_hold
	# The carry aim runs first: it advances the shield's low-pass the pass's
	# gate reads.
	var carry: Vector3 = carry_aim(snapshot, self_pos, carrier, attacking_goal, own_goal_dir,
			blade_reach, protects_the_puck, delta)
	if _should_load_pass(carrier):
		mode = Mode.PASS
		return self_pos + carrier.pass_now_hold
	mode = Mode.CARRY
	return carry


# Rest the puck in the leading pass's pocket while the pass is near the lead (or
# the carrier is holding for a feed still developing) and nothing forces him to
# evade: no man to beat, the shield barely on, and the puck kept there as surely
# as carried as it is (AIShotHolds.keep_for reads a puck in the pocket as
# unshielded). The pocket rides the pass's aim, so a new receiver on the same
# side moves it little; a near tie is held by the same absolute band as the shot.
func _should_load_pass(carrier: AIRoleCarrier) -> bool:
	if carrier.pass_now_hold == Vector3.ZERO or carrier.debug_pass_score <= 0.0:
		return false
	if has_man_to_beat(carrier) or _protect_gain_smooth >= PASS_LOAD_MAX_SHIELD \
			or carrier.pass_now_keep < carrier.carry_keep:
		return false
	if carrier.holding_for_feed:
		return true
	var band: float = FIRE_AIM_HYSTERESIS_BAND if mode == Mode.PASS else 0.0
	return carrier.debug_pass_score >= carrier.lead_score \
			* (1.0 - AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC) - band


# Forward carry reach, cradled tight when the body is behind/beside EITHER net
# (see CARRY_BEHIND_NET_CRADLE_M). Returns the full reach everywhere else.
static func reach_behind_net(self_pos: Vector3, attacking_goal: Vector3,
		own_goal_dir: float) -> float:
	# Wide of the cage laterally: full reach (the wall margin and
	# net_safe_blade_target own that side).
	if absf(self_pos.x) > GameRules.NET_BACK_HALF_WIDTH + CARRY_BEHIND_NET_LATERAL_M:
		return AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M
	# Signed distance PAST a goal line toward its end boards (>0 = behind that
	# net). BOTH nets cradle: behind our own, a puck popped loose by the cage is
	# loose in our crease.
	var past_att: float = (self_pos.z - attacking_goal.z) * (-own_goal_dir)
	var past_own: float = (self_pos.z - own_goal_dir * GameRules.GOAL_LINE_Z) * own_goal_dir
	var past: float = maxf(past_att, past_own)
	# Ramp: full reach until a band's width in front of the line, tight cradle at
	# or behind it.
	var t: float = clampf((past + CARRY_BEHIND_NET_BAND_M) / CARRY_BEHIND_NET_BAND_M, 0.0, 1.0)
	return lerpf(AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, CARRY_BEHIND_NET_CRADLE_M, t)


# The carry aim (world): the presented puck, shifted off the nearest blade and
# blended toward the shield seam, kept off the goal line, the boards and the nets.
func carry_aim(snapshot: WorldSnapshot, self_pos: Vector3, carrier: AIRoleCarrier,
		attacking_goal: Vector3, own_goal_dir: float, blade_reach: float,
		protects_the_puck: bool, delta: float) -> Vector3:
	# Goalie cradle: within blade_reach of EITHER goalie, the forward aim would
	# drive the blade into his gear, which only holds it off (GoalieGearCollision).
	# Parking the cursor on the body holds the blade tight with zero extension;
	# facing is held (zero direction), so the bot backs out facing the play.
	var goalie_pos: Vector3 = _goalie(snapshot, 1 - _team_id, attacking_goal)
	if self_pos.distance_to(goalie_pos) < blade_reach:
		return self_pos
	var own_goalie_pos: Vector3 = _goalie(snapshot, _team_id, Vector3.INF)
	if own_goalie_pos.is_finite() and self_pos.distance_to(own_goalie_pos) < blade_reach:
		return self_pos

	var to_goal: Vector3 = attacking_goal - self_pos
	to_goal.y = 0.0
	var forward_dir: Vector3
	# Attacking direction is -own_goal_dir along z. Fall back to it past the
	# attacking goal line, where `to_goal` points back down the rink.
	var attacking_z: float = -own_goal_dir
	if to_goal.length_squared() > 0.0001 and to_goal.z * attacking_z > 0.0:
		forward_dir = to_goal.normalized()
	else:
		forward_dir = Vector3(0.0, 0.0, attacking_z)
	# O-ZONE SQUARE: in the offensive zone with no man to beat, face the GOALIE —
	# square to the net, every shot/pass option open. Owns the facing outright.
	#
	# FACE THE ROUTE otherwise: while driving somewhere, face the carry anchor, not
	# the goal — speed classes are facing-relative (forward > crossover >
	# backward), so goal-facing down a lateral route skates it in the slow
	# crossover class. The goal-facing default keeps a route too short to define a
	# direction and a genuine RETREAT (below CARRY_FACE_RETREAT_ADVANCE), which
	# backs out facing the play. A hold overrides all of this.
	var squared_to_net: bool = false
	if AIActionScoring.in_offensive_zone(self_pos, attacking_goal) \
			and not has_man_to_beat(carrier):
		var to_goalie: Vector3 = goalie_pos - self_pos
		to_goalie.y = 0.0
		if to_goalie.length_squared() > 0.0001:
			forward_dir = to_goalie.normalized()
			squared_to_net = true
	var route: Vector3 = carrier.last_carry_anchor - self_pos
	route.y = 0.0
	if not squared_to_net \
			and route.length_squared() >= CARRY_FACE_ROUTE_MIN_DIST_M * CARRY_FACE_ROUTE_MIN_DIST_M:
		var route_dir: Vector3 = route.normalized()
		if route_dir.z * attacking_z >= CARRY_FACE_RETREAT_ADVANCE:
			forward_dir = route_dir
	# Cradled tight behind/beside a net (reach_behind_net).
	var reach: float = reach_behind_net(self_pos, attacking_goal, own_goal_dir)
	var base: Vector3 = self_pos + forward_dir * reach
	# Stickhandling offset is raw; the slew-limited cursor step smooths it. Folded
	# in BEFORE the protect blend, so a blade pinned to the protect seam isn't
	# pulled back into the checker's reach.
	var target_pos: Vector3 = base + _stickhandle_offset(snapshot, self_pos, forward_dir)
	# Puck protection: blend the blade from the presented-forward carry toward
	# the carrier's protect seam, weighted by its protect_gain (the safety the
	# shield buys — see Scripts/domain/ai/CLAUDE.md → Carry safety). The seam
	# direction is re-based on the LIVE body and projected out to the carry
	# reach. The low-pass runs every tick, raw zero included, so a disengaging
	# shield decays smoothly.
	var raw_gain: float = carrier.protect_gain if protects_the_puck else 0.0
	var raw_offset: Vector3 = carrier.protect_offset if protects_the_puck else Vector3.ZERO
	var smooth_t: float = clampf(CARRY_PROTECT_SMOOTH_RATE * delta, 0.0, 1.0)
	_protect_gain_smooth = lerpf(_protect_gain_smooth, raw_gain, smooth_t)
	_protect_offset_smooth = _protect_offset_smooth.lerp(raw_offset, smooth_t)
	var protect_w: float = _protect_gain_smooth
	if protects_the_puck and protect_w > 0.0:
		var protect_dir: Vector3 = _protect_offset_smooth
		protect_dir.y = 0.0
		if protect_dir.length_squared() > 0.0025:
			# Shield with REACH, not a spin: clamp how far the protect aim swings off
			# the play line (CARRY_PROTECT_MAX_TURN_DEG). The body turns only to
			# side-on to interpose; the blade ROM covers the rest of the seam.
			var prot2 := Vector2(protect_dir.x, protect_dir.z).normalized()
			var fwd2 := Vector2(forward_dir.x, forward_dir.z)
			if fwd2.length_squared() > 0.0001:
				fwd2 = fwd2.normalized()
				var turn: float = fwd2.angle_to(prot2)
				var max_turn: float = deg_to_rad(CARRY_PROTECT_MAX_TURN_DEG)
				if absf(turn) > max_turn:
					prot2 = fwd2.rotated(signf(turn) * max_turn)
			var protect_target: Vector3 = self_pos \
					+ Vector3(prot2.x, 0.0, prot2.y) * reach
			target_pos = target_pos.lerp(protect_target, minf(protect_w, 1.0))
	# Keep the target on the rink side of the attacking goal line, or the blade
	# punches through the net.
	var goal_line_z: float = attacking_goal.z
	var max_forward_z: float = goal_line_z + AIStationSearch.GOAL_LINE_BUFFER_M * own_goal_dir
	if (target_pos.z - max_forward_z) * own_goal_dir < 0.0:
		target_pos.z = max_forward_z
	# ...and inside the boards (CARRY_BLADE_WALL_MARGIN_M), clamped after every
	# offset above, none of which is wall-aware.
	var on_ice: Vector2 = GameRules.clamp_to_rink_inner(
			Vector2(target_pos.x, target_pos.z), AIBotMechanics.CARRY_BLADE_WALL_MARGIN_M)
	target_pos.x = on_ice.x
	target_pos.z = on_ice.y
	# ...and never THROUGH a net frame: the chord swings around the nearer post.
	return AINetObstacle.net_safe_blade_target(self_pos, target_pos)


# True while the presented-forward puck is inside somebody's reach — there is
# still a man to beat. Reads AIRoleCarrier.forward_puck_clearance, the
# reachable-set clearance against every un-beaten defender's momentum-projected
# stick, which is the SAME read the shield's necessity half runs, so body and
# stick never disagree about whether the man is beaten. Reach answers "have I
# beaten him?" as a closing-rate question: a chaser losing ground can't get
# there, and a defender abreast and wide can't reach the puck in time.
func has_man_to_beat(carrier: AIRoleCarrier) -> bool:
	# Sticky: an engaged man must open the bar plus the hysteresis to be beaten.
	var bar: float = CARRY_MAN_TO_BEAT_CLEAR_M
	if _has_man:
		bar += CARRY_MAN_TO_BEAT_HYSTERESIS_M
	_has_man = carrier.forward_puck_clearance < bar
	return _has_man


# The stickhandling offset: perpendicular to `forward_dir`, away from the summed
# signed-lateral pull of every opposing blade within STICKHANDLE_THREAT_RADIUS_M of
# our puck, clamped to STICKHANDLE_OFFSET_MAX_M. A sum rather than the nearest
# threat, which can swap per tick and snap the offset side to side: opposite
# threats cancel (blade holds central) and threats dead ahead contribute ~0.
#
# `blade_contact_world` is host-only, which is safe because bots only run on the
# host; ZERO (before SkaterController populates it) falls back to the body.
func _stickhandle_offset(snapshot: WorldSnapshot, self_pos: Vector3, forward_dir: Vector3) -> Vector3:
	var right_axis: Vector3 = Vector3(forward_dir.z, 0.0, -forward_dir.x)
	# Threat distance is measured from the carried puck, not the body.
	var carry_pos: Vector3 = self_pos + forward_dir * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M
	# Positive = pull toward +right_axis (away from a threat on the left).
	var lateral_force: float = 0.0
	for peer_id: int in _opponent_ids(snapshot):
		var opp_state: SkaterNetworkState = snapshot.skater_states[peer_id]
		var threat_pos: Vector3 = opp_state.blade_contact_world
		if threat_pos == Vector3.ZERO:
			threat_pos = opp_state.position
		var to_threat: Vector3 = threat_pos - carry_pos
		to_threat.y = 0.0
		var dist: float = to_threat.length()
		if dist > STICKHANDLE_THREAT_RADIUS_M or dist < 0.001:
			continue
		var ramp: float = clampf(inverse_lerp(
				STICKHANDLE_THREAT_RADIUS_M,
				STICKHANDLE_FULL_OFFSET_RADIUS_M,
				dist), 0.0, 1.0)
		# Lateral component of the unit direction toward the threat, in [-1, 1].
		var lateral_unit: float = right_axis.dot(to_threat) / dist
		lateral_force -= lateral_unit * ramp
	var magnitude: float = clampf(lateral_force, -1.0, 1.0) * STICKHANDLE_OFFSET_MAX_M
	return right_axis * magnitude


# Opponent peer ids from the per-frame roster cache (GameManager
# ._enrich_snapshot_for_ai), or a live partition into a reused buffer when it is
# empty (unit tests).
func _opponent_ids(snapshot: WorldSnapshot) -> Array:
	var opp_team: int = 1 - _team_id
	if snapshot.teammate_ids_by_team.has(opp_team):
		return snapshot.teammate_ids_by_team[opp_team]
	_scratch_opp_ids.clear()
	for pid: int in snapshot.skater_states:
		if pid != _peer_id and _team_id_by_peer.get(pid, -1) != _team_id:
			_scratch_opp_ids.append(pid)
	return _scratch_opp_ids


# Team `team`'s goalie where he is now, or `fallback` before his state is buffered.
static func _goalie(snapshot: WorldSnapshot, team: int, fallback: Vector3) -> Vector3:
	var g: GoalieNetworkState = snapshot.goalie_states.get(team)
	if g == null:
		return fallback
	return Vector3(g.position_x, 0.0, g.position_z)
