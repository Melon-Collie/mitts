class_name SkaterAgentReception
extends RefCounted

# One bot's reads of an incoming feed (Scripts/ai/CLAUDE.md → Reception
# doctrine): whether a fast loose puck is a pass to it, where the blade parks to
# meet it, where the body stands to catch it square (in stride, or against the
# boards as a wall kill), and whether it is a shot reception — one-time it or
# catch it facing the net. Reads only: the state machine steers, aims and changes
# state on the results. Owns nothing but its result fields and scratch.

# Pass-receive setup: stand to the SIDE of a fast puck's path so the blade face
# is square to the incoming line, maximizing PuckReceptionRules' alignment bonus
# (up to +8 m/s head-on), which lifts the catch ceiling and shortens the settle.
# The trigger is what reads as a pass at all: under the softest feed a bot
# fires (pass_launch_speed floors the arrival at the min wrister, 10 m/s), less
# a margin for the pace it sheds on the way.
const RECEIVE_TRIGGER_PUCK_SPEED_M_S: float = 9.0
# Farther than this off the puck's line where our skating takes us, the pass
# isn't ours; sized generously to cover any pass that would realistically end up
# at this bot.
const RECEIVE_TRIGGER_LATERAL_M: float = 5.0
# Sideways stand-off from the path: stick + blade reach less this inset, so the
# IK isn't at the ROM clamp.
const RECEIVE_BODY_INSET_M: float = 0.2
# Bot must reach the body anchor within this fraction of the puck's flight time,
# else the plain lead-intercept (faster, at a worse angle) wins.
const RECEIVE_TIMING_MARGIN: float = 0.9
# Body-centre inset from the boards for any stance built off a boards-hugging
# puck line — a skater's collision radius, so the shoulder rather than the anchor
# stops at the glass.
const BODY_WALL_MARGIN_M: float = 0.5
# Walk for AITrajectory.solve_reception_gate (the puck's real path, caroms and
# all). The horizon covers a full corner wrap at rim pace; the walk tests each
# step as a segment, so 20 steps suffice.
const RECEIVE_PATH_HORIZON_S: float = 2.0
const RECEIVE_PATH_STEPS: int = 20
# A reception gate within this of the boards is played as a wall kill (blade on
# the glass, body rink-side); outside it the ordinary side-stand runs.
const WALL_KILL_BAND_M: float = 1.0
# "Give with the puck" ceiling on an incoming feed's RECEIVER-FRAME speed
# (gives_with). It is the bobble line at the blade's middle on a poorly angled
# blade (AIFeedReception.BOBBLE_LOAD of the any-angle ceiling's load,
# test_bot_mirrors.gd), so a receiver never skates a feed the passer priced as a
# catch into one that bobbles.
const RECEIVE_GIVE_CEILING_M_S: float = 18.0

# ── Shot-aware reception (read_shot) ─────────────────────────────────────────
# When a pass is incoming and a shot from the reception area is on, the bot
# either ONE-TIMES it (Mode A) or catches it facing the net (Mode B), instead of
# the default chase that turns the body to the puck and then back to shoot.
# Both aim at a net-forward catch point and stand so the puck arrives there.
#
# Engages when the puck is a real pass to us and the shot off it from the
# reception point scores >= SHOT_RECEPTION_SCORE_GATE (score_pass_value, the
# better of one-timing and catching), so this also means "in range with a real
# look".
#
# Mode A needs a LATERAL forehand-side cross-pass, far enough out that skating in
# buys nothing, with the bot not already driving net-ward, and squared up (the
# state machine's check, ONE_TIME_MAX_SQUARE_UP_RAD). Lateral is mechanical: the
# puck must still be RECEIVED for the fire to trigger, and a net-aimed blade is
# only square to it (alignment ≈ sin(redirect angle)) when it arrives across the
# body. Mode B otherwise: catch facing the net and let CARRY shoot.
const SHOT_RECEPTION_SCORE_GATE: float = 0.30
# Redirect angle = turn from puck-travel direction to net direction at the
# catch point. The band brackets "lateral enough that a net-aimed blade catches
# it" — at the 50° edge, alignment = sin(50°) = 0.77 → deflect threshold
# 14 + 8·0.77 ≈ 20 m/s, comfortably above the charged-pass speed (~19), so a
# one-timer across the whole band actually receives before it fires; peak is a
# square cross-seam at 90°.
const ONE_TIME_MIN_REDIRECT_RAD: float = 0.873      # deg_to_rad(50)
const ONE_TIME_MAX_REDIRECT_RAD: float = 2.269      # deg_to_rad(130)
const ONE_TIME_MIN_NET_DIST_M: float = 6.0
# Net-ward closing speed above which we're committed to driving in (Mode B)
# rather than stopping to redirect (Mode A).
const ONE_TIME_MAX_DRIVE_SPEED_M_S: float = 4.0
# Squared-up cone for committing a Mode A redirect. The one-time press locks the
# slapper direction from the cursor almost at once (the controller's
# locked_slapper_dir), so the body must ALREADY face near the net line; beyond
# this cone the bot catches the feed (Mode B) instead. Generous, since a
# cross-seam catch is naturally ~net-ward already.
const ONE_TIME_MAX_SQUARE_UP_RAD: float = 0.960     # deg_to_rad(55)

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
var _caps_by_peer: Dictionary = {}
var _is_left_handed: bool = false

# ── Result of read_pass ──────────────────────────────────────────────────────
# Where the body stands, whether skating on as we are would carry the blade past
# the meet (so steer with the arrival brake), whether the feed is hot enough to
# give with, and where the blade parks.
var pass_body_anchor: Vector3 = Vector3.ZERO
var pass_overruns: bool = false
var pass_give: bool = false
var pass_blade_aim: Vector3 = Vector3.ZERO

# ── Result of read_shot ──────────────────────────────────────────────────────
# The net-forward stand, whether the feed's geometry allows a one-time (Mode A,
# before the squared-up check), and our velocity for the Mode B blade gate.
var shot_anchor: Vector3 = Vector3.ZERO
var shot_one_time_geometry: bool = false
var shot_self_vel: Vector3 = Vector3.ZERO

# Opponent scratch for read_shot's score, caps index-matched (null for unwired
# peers).
var _shot_opponents: Array[Vector3] = []
var _shot_opponent_caps: Array[AISkaterCaps] = []


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary, is_left_handed: bool) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer
	_is_left_handed = is_left_handed


# Comfortable blade extension for a parked reception: the blade span (`blade_reach`
# less its outward buffer) minus the side-stand inset, off the IK ROM clamp.
static func gate_reach(blade_reach: float) -> float:
	return maxf(blade_reach - AIBotMechanics.BLADE_REACH_BUFFER_M - RECEIVE_BODY_INSET_M, 0.4)


# Pass-receive stance (the RECEIVE_TRIGGER_* read) into the pass_* results. False
# when the puck is too slow, going away, too far off its line, or the stance
# can't be reached in time.
func read_pass(snapshot: WorldSnapshot, self_pos: Vector3, blade_reach: float,
		body_offset: float, max_speed: float) -> bool:
	if snapshot.puck_state.carrier_peer_id != -1:
		return false
	var puck_vel: Vector3 = snapshot.puck_state.velocity
	var puck_speed_sq: float = puck_vel.x * puck_vel.x + puck_vel.z * puck_vel.z
	if puck_speed_sq < RECEIVE_TRIGGER_PUCK_SPEED_M_S * RECEIVE_TRIGGER_PUCK_SPEED_M_S:
		return false
	var puck_pos: Vector3 = snapshot.puck_state.position
	var self_vel: Vector3 = Vector3.ZERO
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state != null:
		self_vel = self_state.velocity
	# The crossing point, its time, and the puck's direction then all come off
	# the puck's real path. Solved as a RENDEZVOUS — the reach circle rides our own
	# velocity — so the meet is a fixed point both bodies travel toward.
	var meets: bool = AITrajectory.solve_reception_gate(puck_pos, puck_vel, self_pos,
			gate_reach(blade_reach), RECEIVE_PATH_HORIZON_S, RECEIVE_PATH_STEPS,
			self_vel, AICarrierPassSearch.PASS_LEAD_MAX_S)
	# Path-based, not a dot product against the current velocity: a rim running
	# away down the far wall can still be coming to us around a corner.
	if not AITrajectory.gate_closes:
		return false
	var perp_foot: Vector3 = AITrajectory.gate_point
	var gate_vel: Vector3 = AITrajectory.gate_velocity
	var gate_speed: float = sqrt(gate_vel.x * gate_vel.x + gate_vel.z * gate_vel.z)
	if gate_speed < 0.001:
		return false
	var puck_dir: Vector3 = Vector3(gate_vel.x / gate_speed, 0.0, gate_vel.z / gate_speed)
	# A gate at t≈0 means the puck is already on the blade: nothing to set up.
	var puck_eta: float = AITrajectory.gate_time_s
	if puck_eta <= 0.0:
		return false
	# A meet the rendezvous solved is where our skating takes the body; a feed
	# that never enters our moving reach must be close enough to step to.
	if not meets and Vector2(self_pos.x - perp_foot.x, self_pos.z - perp_foot.z).length() \
			> RECEIVE_TRIGGER_LATERAL_M:
		return false
	# Where our own skating puts the body at the meet: the rendezvous solved the
	# meet in the body's frame (AITrajectory.gate_offset), so the body is that far
	# off it. Standing still, that is where we stand. A puck that never enters
	# our moving reach has no such meet, and the stance is set from here.
	var blade_offset: Vector3 = AITrajectory.gate_offset
	var meet_body: Vector3 = self_pos
	if meets:
		meet_body = Vector3(perp_foot.x - blade_offset.x, 0.0, perp_foot.z - blade_offset.z)
	# The face is square across the shaft, so the catch is square where the
	# puck's path in OUR frame passes the body a stance off it, crossing the
	# shaft: the stance is measured off that relative line through the meet, at
	# its foot from where our skating takes the body. A stance we stop to hold
	# sees the puck's own line.
	var rel_dir: Vector3 = puck_dir
	if meets:
		var rel := Vector3(gate_vel.x - self_vel.x, 0.0, gate_vel.z - self_vel.z)
		if rel.length_squared() > 0.0001:
			rel_dir = rel.normalized()
	var to_body: Vector3 = meet_body - perp_foot
	var rel_foot: Vector3 = perp_foot + rel_dir * to_body.dot(rel_dir)
	var perp_off: Vector3 = meet_body - rel_foot
	var perp_dist: float = perp_off.length()
	# Stand on the side of the path our skating takes us to (least skating); on
	# the path, either side.
	var lateral: Vector3
	if perp_dist > 0.001:
		lateral = perp_off / perp_dist
	else:
		lateral = Vector3(-rel_dir.z, 0.0, rel_dir.x)
	# WALL KILL (WALL_KILL_BAND_M): against the boards the stance side is forced
	# inward. The blade's half of the meet takes the same wall push.
	var board: Vector3 = board_normal_and_gap(Vector2(perp_foot.x, perp_foot.z))
	if board.y <= WALL_KILL_BAND_M:
		var push := Vector3(-board.x * board.y, 0.0, -board.z * board.y)
		lateral = Vector3(board.x, 0.0, board.z)
		perp_foot += push
		rel_foot += push
		blade_offset += push
	var body_anchor: Vector3 = rel_foot + lateral * body_offset
	# The side-stand offset from a boards-hugging line can land in the wall.
	var anchor_xz: Vector2 = GameRules.clamp_to_rink_inner(
			Vector2(body_anchor.x, body_anchor.z), BODY_WALL_MARGIN_M)
	body_anchor = Vector3(anchor_xz.x, 0.0, anchor_xz.y)
	# Timing gate (RECEIVE_TIMING_MARGIN). Skating into the meet, the drift is
	# the rendezvous itself, so only the stance's correction off it needs the
	# time: what the stride covers from rest in the margin of the flight. A puck
	# that never enters our moving reach is a stance to get to.
	if meets:
		var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
		var accel: float = caps.max_accel if caps != null else GameRules.DEFAULT_SKATER_THRUST_M_S2
		var drift_at: Vector3 = self_pos + self_vel * puck_eta
		if Vector2(body_anchor.x - drift_at.x, body_anchor.z - drift_at.z).length() \
				> AIStrideRamp.distance_in(0.0, puck_eta * RECEIVE_TIMING_MARGIN, max_speed, accel):
			return false
	elif AIArrival.time_to_arrive(self_pos, body_anchor, self_vel, max_speed) \
			> puck_eta * RECEIVE_TIMING_MARGIN:
		return false
	# Receive IN STRIDE; brake only when skating on as we are would carry the
	# blade past the meet before the puck gets there. Judged on the unbounded
	# drift at puck_eta, not on the meet solve, whose ride on our velocity is
	# bounded (PASS_LEAD_MAX_S) and so can report a meet the body skates past.
	# A meet the rendezvous solved sits AT the reach, so it is past only by
	# more than half a blade.
	var drift: Vector3 = self_pos + self_vel * puck_eta
	pass_overruns = Vector2(drift.x - perp_foot.x, drift.z - perp_foot.z) \
			.length() > gate_reach(blade_reach) + GameRules.DEFAULT_BLADE_LENGTH_M * 0.5
	pass_body_anchor = body_anchor
	pass_give = gives_with(puck_vel, self_vel)
	# PARK the blade at the gate, held in the body's frame (see blade_gate).
	pass_blade_aim = self_pos + blade_offset
	return true


# GIVE WITH THE PUCK: brake when our own skating is what carries the feed past
# RECEIVE_GIVE_CEILING_M_S — stopping would bring it back under. A feed already
# past it on its own bobbles however we skate, so it is taken in stride.
static func gives_with(puck_vel: Vector3, self_vel: Vector3) -> bool:
	var ceiling_sq: float = RECEIVE_GIVE_CEILING_M_S * RECEIVE_GIVE_CEILING_M_S
	var rel_x: float = puck_vel.x - self_vel.x
	var rel_z: float = puck_vel.z - self_vel.z
	return rel_x * rel_x + rel_z * rel_z > ceiling_sq \
			and puck_vel.x * puck_vel.x + puck_vel.z * puck_vel.z <= ceiling_sq


# The GATE: where the blade waits for an incoming loose puck — the earliest point
# on the puck's travel line the blade can touch (where the line enters a
# comfortable-extension circle around the body). Parking there beats tracking the
# puck's position: the cursor slews at the build's blade speed (~10 m/s baseline) while
# a pass sweeps past at ~20 m/s, so a blade CHASING the puck lags behind it
# through the reach envelope and the pass transits untouched. Solved as a
# rendezvous against our own moving reach, the gate is a fixed world point both
# bodies are travelling toward, so the cursor holds it at rest and the puck
# arrives INTO the waiting blade. Falls back to the puck's own position when the
# puck has already passed our level (chase from behind) or is (near-)stationary.
static func blade_gate(self_pos: Vector3, self_vel: Vector3,
		puck_pos: Vector3, puck_vel: Vector3, blade_reach: float) -> Vector3:
	var speed_sq: float = puck_vel.x * puck_vel.x + puck_vel.z * puck_vel.z
	if speed_sq < 0.0001:
		return puck_pos
	# On the puck's real path, against our own MOVING reach.
	if not AITrajectory.solve_reception_gate(puck_pos, puck_vel, self_pos,
			gate_reach(blade_reach), RECEIVE_PATH_HORIZON_S, RECEIVE_PATH_STEPS,
			self_vel, AICarrierPassSearch.PASS_LEAD_MAX_S):
		# No touchable point on the path. A puck moving AWAY is chased from
		# behind; otherwise hold the blade toward the path's closest approach
		# until the entry point appears.
		var to_self_x: float = self_pos.x - puck_pos.x
		var to_self_z: float = self_pos.z - puck_pos.z
		if puck_vel.x * to_self_x + puck_vel.z * to_self_z <= 0.0:
			return puck_pos
	# Held in the body's frame (AITrajectory.gate_offset), so the cursor is a spot
	# the arm can be at while the body closes. The wall kill is judged at the meet
	# and carried across as the same displacement.
	var meet: Vector3 = AITrajectory.gate_point
	var push: Vector3 = wall_kill_aim(meet) - meet
	return self_pos + AITrajectory.gate_offset + push


# The boards at `xz`: the unit INWARD normal packed in x/z, and the gap to the
# wall in y (negative off the surface). INF.y when the point is deeper in than
# the probe reaches — i.e. open ice, no wall to play.
#
# Via the rink clamp, so the ROUNDED CORNERS come for free: clamping with a margin
# wider than the band projects the point onto the shrunk surface, and that
# displacement is the inward normal with length (margin − gap). Packed into a
# Vector3 to avoid allocating on the per-tick reception path.
static func board_normal_and_gap(xz: Vector2) -> Vector3:
	var probe_margin: float = WALL_KILL_BAND_M + 0.5
	var inward: Vector2 = GameRules.clamp_to_rink_inner(xz, probe_margin) - xz
	var inset: float = inward.length()
	if inset < 0.000001:
		return Vector3(0.0, INF, 0.0)
	return Vector3(inward.x / inset, probe_margin - inset, inward.y / inset)


# Pushes a boards-hugging aim point out ONTO the inner wall surface, so the
# blade seals against the glass instead of leaving the puck a gap behind it.
# Returns `point` untouched when it isn't inside WALL_KILL_BAND_M.
static func wall_kill_aim(point: Vector3) -> Vector3:
	var xz := Vector2(point.x, point.z)
	var board: Vector3 = board_normal_and_gap(xz)
	if board.y > WALL_KILL_BAND_M:
		return point
	# Off the surface entirely (a phantom sample) → gap < 0 → this pulls the aim
	# back onto the wall, which is exactly where the blade belongs anyway.
	var on_wall: Vector2 = xz - Vector2(board.x, board.z) * board.y
	return Vector3(on_wall.x, 0.0, on_wall.y)


# Is a fast loose puck (a pass) heading toward us right now — fast, loose, we're
# AHEAD of it and within the receive lateral of its line? Enters (and holds) CHASE
# the instant a pass is released our way, so the squared reception has time to
# set up.
func incoming_pass(snapshot: WorldSnapshot, self_pos: Vector3) -> bool:
	if snapshot == null or snapshot.puck_state == null \
			or snapshot.puck_state.carrier_peer_id != -1:
		return false
	var pv: Vector3 = snapshot.puck_state.velocity
	var speed_sq: float = pv.x * pv.x + pv.z * pv.z
	if speed_sq < RECEIVE_TRIGGER_PUCK_SPEED_M_S * RECEIVE_TRIGGER_PUCK_SPEED_M_S:
		return false
	var speed: float = sqrt(speed_sq)
	var dir := Vector3(pv.x / speed, 0.0, pv.z / speed)
	var puck_pos: Vector3 = snapshot.puck_state.position
	if (self_pos.x - puck_pos.x) * dir.x + (self_pos.z - puck_pos.z) * dir.z <= 0.0:
		return false
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	var self_vel: Vector3 = self_state.velocity if self_state != null else Vector3.ZERO
	var me: Vector3 = skating_point(self_pos, self_vel, puck_pos, dir, speed)
	var along: float = (me.x - puck_pos.x) * dir.x + (me.z - puck_pos.z) * dir.z
	var perp_foot: Vector3 = puck_pos + dir * along
	var my_d2: float = (me.x - perp_foot.x) * (me.x - perp_foot.x) \
			+ (me.z - perp_foot.z) * (me.z - perp_foot.z)
	if my_d2 > RECEIVE_TRIGGER_LATERAL_M * RECEIVE_TRIGGER_LATERAL_M:
		return false
	# Only the teammate nearest where the puck crosses our level anticipates, or
	# a fast puck would pull every bot in its lateral band out of position. Each
	# is read where his own skating takes him.
	for pid: int in snapshot.skater_states:
		if pid == _peer_id or _team_id_by_peer.get(pid, -1) != _team_id:
			continue
		var tm: SkaterNetworkState = snapshot.skater_states[pid]
		var tp: Vector3 = skating_point(tm.position, tm.velocity, puck_pos, dir, speed)
		var dx: float = tp.x - perp_foot.x
		var dz: float = tp.z - perp_foot.z
		if dx * dx + dz * dz < my_d2:
			return false
	return true


# Where a skater's own skating puts him when the puck (`dir` from `puck_pos` at
# `speed`) reaches his level, the drift capped at the longest lead a pass is
# thrown on.
static func skating_point(pos: Vector3, vel: Vector3, puck_pos: Vector3,
		dir: Vector3, speed: float) -> Vector3:
	var along: float = (pos.x - puck_pos.x) * dir.x + (pos.z - puck_pos.z) * dir.z
	var drift_s: float = clampf(along / speed, 0.0, AICarrierPassSearch.PASS_LEAD_MAX_S)
	return Vector3(pos.x + vel.x * drift_s, 0.0, pos.z + vel.z * drift_s)


# Shot-aware reception read (the shot-aware block above) into the shot_*
# results. False when this feed is not a shot reception (the caller runs the
# normal catch); true with the net-forward stand and whether its geometry allows
# a one-time.
func read_shot(snapshot: WorldSnapshot, self_pos: Vector3, blade_reach: float,
		attacking_goal: Vector3) -> bool:
	var puck_state: PuckNetworkState = snapshot.puck_state
	# Only loose pucks are receivable; held pucks aren't a pass to catch.
	if puck_state.carrier_peer_id != -1:
		return false
	var puck_vel: Vector3 = puck_state.velocity
	var puck_speed_sq: float = puck_vel.x * puck_vel.x + puck_vel.z * puck_vel.z
	if puck_speed_sq < RECEIVE_TRIGGER_PUCK_SPEED_M_S * RECEIVE_TRIGGER_PUCK_SPEED_M_S:
		return false
	var puck_speed: float = sqrt(puck_speed_sq)
	var puck_dir: Vector3 = Vector3(puck_vel.x / puck_speed, 0.0, puck_vel.z / puck_speed)
	var puck_pos: Vector3 = puck_state.position
	# Foot of perpendicular from self onto the puck's path; t <= 0 means it is
	# already past us.
	var to_self: Vector3 = self_pos - puck_pos
	to_self.y = 0.0
	var t: float = to_self.dot(puck_dir)
	if t <= 0.0:
		return false
	var perp_foot: Vector3 = puck_pos + puck_dir * t
	var perp_off: Vector3 = self_pos - perp_foot
	perp_off.y = 0.0
	if perp_off.length() > RECEIVE_TRIGGER_LATERAL_M:
		return false
	# The feed as it stands: the puck where it is now, the keeper square on it as
	# he is now, one-timed or caught, whichever is the better shot. Its lane is
	# handed in clear — whether the puck gets here is the reception's own read.
	_gather_opponents(snapshot)
	var keeper: Vector3 = _goalie_now(snapshot, attacking_goal)
	var shot_score: float = maxf(
			AIActionScoring.score_pass_value(puck_pos, perp_foot, attacking_goal, keeper,
					_shot_opponents, puck_speed, _shot_opponent_caps, true, 1.0),
			AIActionScoring.score_pass_value(puck_pos, perp_foot, attacking_goal, keeper,
					_shot_opponents, puck_speed, _shot_opponent_caps, false, 1.0))
	if shot_score < SHOT_RECEPTION_SCORE_GATE:
		return false
	# Net-forward geometry. Anchor = the catch point pulled back one blade-reach
	# AWAY from the net, so when the bot stands there its net-pointing blade
	# meets the puck at perp_foot and the puck arrives net-FORWARD of the body
	# (aiming there keeps facing net-ward, never turning to grab).
	var to_net: Vector3 = attacking_goal - perp_foot
	to_net.y = 0.0
	var net_len: float = to_net.length()
	if net_len < 0.001:
		return false
	var net_dir: Vector3 = to_net / net_len
	shot_anchor = perp_foot - net_dir * blade_reach
	# Mode A (one-time) eligibility: lateral redirect (in the band), forehand
	# side, far enough out, and not already driving hard at the net.
	var redirect_angle: float = acos(clampf(puck_dir.dot(net_dir), -1.0, 1.0))
	# Left of the net direction (up × net_dir); RH forehand = -left_dir, LH =
	# +left_dir (the convention the state machine's handedness also follows).
	var left_dir: Vector3 = Vector3(net_dir.z, 0.0, -net_dir.x)
	var forehand_dir: Vector3 = left_dir if _is_left_handed else -left_dir
	var from_forehand: bool = (puck_pos - self_pos).dot(forehand_dir) > 0.0
	shot_self_vel = Vector3.ZERO
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state != null:
		shot_self_vel = self_state.velocity
	var net_ward_speed: float = shot_self_vel.dot(net_dir)
	shot_one_time_geometry = (redirect_angle >= ONE_TIME_MIN_REDIRECT_RAD
			and redirect_angle <= ONE_TIME_MAX_REDIRECT_RAD
			and from_forehand
			and net_len >= ONE_TIME_MIN_NET_DIST_M
			and net_ward_speed <= ONE_TIME_MAX_DRIVE_SPEED_M_S)
	if shot_one_time_geometry:
		return true
	# The net-forward catch stands the body behind the catch point, so it is
	# only a catch when the body gets there first (RECEIVE_TIMING_MARGIN, as the
	# pass stance's): one driving past it on its own skating takes the feed in
	# stride instead (read_pass), never steering back up the ice for it.
	var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
	var max_speed: float = caps.max_speed if caps != null \
			else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	return AIArrival.time_to_arrive(self_pos, shot_anchor, shot_self_vel, max_speed) \
			<= t / puck_speed * RECEIVE_TIMING_MARGIN


func _gather_opponents(snapshot: WorldSnapshot) -> void:
	_shot_opponents.clear()
	_shot_opponent_caps.clear()
	for pid: int in snapshot.skater_states:
		if pid == _peer_id:
			continue
		if _team_id_by_peer.get(pid, -1) != _team_id:
			_shot_opponents.append(snapshot.skater_states[pid].position)
			_shot_opponent_caps.append(_caps_by_peer.get(pid))


func _goalie_now(snapshot: WorldSnapshot, attacking_goal: Vector3) -> Vector3:
	var opp_goalie: GoalieNetworkState = snapshot.goalie_states.get(1 - _team_id)
	if opp_goalie == null:
		return attacking_goal
	return Vector3(opp_goalie.position_x, 0.0, opp_goalie.position_z)
