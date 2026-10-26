class_name SkaterAgentStickPlay
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# Long enough for the blade to sweep through the puck, short enough to read as a
# discrete poke.
const POKE_JAB_ACTIVE_TICKS: int = _PhysicsConstants.PHYSICS_TICK / 12   # ~80 ms
# Cooldown so the bot returns to gap control between jabs.
const POKE_JAB_COOLDOWN_TICKS: int = _PhysicsConstants.PHYSICS_TICK * 3 / 8   # ~375 ms
# A lift chosen over the jab (AIStickLiftRead) holds the button through the rise
# and then hooks for as long as a jab sweeps, so it reads as the same reach-in.
# Ends well inside StickCheckRules.HOOK_MAX_S, so the blade takes the fast drop.
const STICK_LIFT_HOLD_TICKS: int = ceili(
		StickCheckRules.RISE_S * _PhysicsConstants.PHYSICS_TICK) + POKE_JAB_ACTIVE_TICKS

# One bot's stick play: the pressurer's reach-in (a jab, or a lift when the
# carrier's body shields the puck), the coverer's tie on his man, a tied
# attacker's pull or hold, and the stick-check button that carries them every
# tick. Owns the windows and the tie it holds; the role, the tier's gates and the
# bot's reaches come in per call.

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
# The jab window and cooldown.
var _poke_jab_active_ticks: int = 0
var _poke_jab_cooldown_ticks: int = 0
# Physics ticks left holding the stick-check button for a lift, and whether its
# press edge is still to send. Counted per physics tick in apply_button,
# since the button must be held on the throttled ticks too.
var _stick_lift_hold_ticks: int = 0
var _stick_lift_press_pending: bool = false
# A tie held on the covered man (AIStickTieRead): the button stays down while the
# dispatch keeps the read alive, and the press re-sends whenever the stick is idle.
var _stick_tie_holding: bool = false
var _stick_tie_press_pending: bool = false
# A tied attacker who is not the feed's target holds on, keeping the defender's
# stick tied up and out of the play (no press: the tie is already made).
var _stick_tie_holding_on: bool = false
# Where a tying defender's blade follows the man's stick: his stick as the bot
# reads it, lagged by the network budget a human holder plays under
# (StickCheckRules.TIE_LAG_BUDGET_S), so a bot holding a tie is beaten by the
# same pulls a human would be. INF until a tie reach starts.
var _tie_follow: Vector3 = Vector3.INF
# The bodies for the tie's lane read and each one's stick reach (his blade span
# and the buffer, as the chase reads every racer), refilled per full dispatch.
var _tie_defender_scratch: Array[Vector3] = []
var _tie_reach_scratch: Array[float] = []
var _caps_by_peer: Dictionary = {}


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary = {}) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer


# A fresh carry: no reach-in window, cooldown or lift hold.
func reset_reach_in() -> void:
	_poke_jab_active_ticks = 0
	_poke_jab_cooldown_ticks = 0
	_stick_lift_hold_ticks = 0
	_stick_lift_press_pending = false


# Let go of the tie this bot is holding on its man.
func drop_tie() -> void:
	_stick_tie_holding = false


# Defensive poke jab (or stick lift): the reach-in aim while one is active, else
# INF. Runs the jab lifecycle — active, then cooldown, then a fresh trigger when
# within reach of an opposing carrier's puck. Only the puck-pressurer slots jab,
# so the team doesn't collapse two bots onto the puck.
# `is_pressurer` is whether our role owns the carrier this beat; the reaches are
# this bot's own; the window counts down by `dispatch_period_ticks`.
func jab_aim(snapshot: WorldSnapshot, self_pos: Vector3, is_pressurer: bool,
		lifts_sticks: bool, stick_lift_reach: float, jab_reach: float,
		dispatch_period_ticks: int) -> Vector3:
	if _poke_jab_active_ticks > 0:
		# Dispatch-span decrement: the window is in physics ticks.
		_poke_jab_active_ticks -= dispatch_period_ticks
		if _poke_jab_active_ticks <= 0:
			_poke_jab_active_ticks = 0
			_poke_jab_cooldown_ticks = POKE_JAB_COOLDOWN_TICKS
		return jab_target(snapshot)
	if _poke_jab_cooldown_ticks > 0:
		_poke_jab_cooldown_ticks = maxi(0, _poke_jab_cooldown_ticks - dispatch_period_ticks)
		return Vector3.INF
	if not is_pressurer:
		return Vector3.INF
	if snapshot.puck_state == null:
		return Vector3.INF
	# Must be an opposing carrier (not loose, not a teammate carrying).
	var carrier_pid: int = snapshot.puck_state.carrier_peer_id
	if carrier_pid == -1 or _team_id_by_peer.get(carrier_pid, -1) == _team_id:
		return Vector3.INF
	var puck_pos: Vector3 = snapshot.puck_state.position
	var carrier_state: SkaterNetworkState = snapshot.skater_states.get(carrier_pid)
	# Read before the jab's reach: the shaft runs back toward a carrier's hands, so
	# from behind it is in reach while the puck out front is not. The body
	# half-width that blocks the jab is the skater collision disc
	# (GameRules.OFFSIDE_LINE_SLACK, the canonical half-width).
	if lifts_sticks and carrier_state != null and AIStickLiftRead.prefers_lift(
			self_pos, carrier_state.position, puck_pos,
			carrier_state.top_hand_world, carrier_state.blade_contact_world,
			stick_lift_reach, GameRules.OFFSIDE_LINE_SLACK):
		_stick_lift_hold_ticks = STICK_LIFT_HOLD_TICKS
		_stick_lift_press_pending = true
		_poke_jab_active_ticks = STICK_LIFT_HOLD_TICKS
		return jab_target(snapshot)
	var dx: float = puck_pos.x - self_pos.x
	var dz: float = puck_pos.z - self_pos.z
	if dx * dx + dz * dz > jab_reach * jab_reach:
		return Vector3.INF
	_poke_jab_active_ticks = POKE_JAB_ACTIVE_TICKS
	return puck_pos


# Where the reach-in aims: under the carrier's shaft while a lift is held, then
# the puck — the dropping blade comes down onto it, which is the take.
func jab_target(snapshot: WorldSnapshot) -> Vector3:
	if _stick_lift_hold_ticks > 0 and snapshot.puck_state != null:
		var cs: SkaterNetworkState = snapshot.skater_states.get(
				snapshot.puck_state.carrier_peer_id)
		if cs != null:
			return AIStickLiftRead.shaft_lift_point(cs.top_hand_world, cs.blade_contact_world)
	if snapshot.puck_state == null or snapshot.puck_state.carrier_peer_id == -1:
		return Vector3.INF
	return snapshot.puck_state.position


# Ties the covered man's stick when the puck is coming to him and nothing else
# would stop it (AIStickTieRead). Returns where the blade goes — onto his shaft —
# or INF, and keeps the tie hold in step for the per-tick button.
func tie_aim(snapshot: WorldSnapshot, self_pos: Vector3,
		self_state: SkaterNetworkState, decision: RoleDecision, ties_sticks: bool,
		stick_lift_reach: float, blade_reach: float) -> Vector3:
	var man: SkaterNetworkState = null
	if ties_sticks and decision != null and decision.locked_man_pid != -1:
		man = snapshot.skater_states.get(decision.locked_man_pid)
	# A man tied up by someone else is already out of the play; one tied with US
	# is the tie this read keeps alive.
	var self_tied: bool = self_state != null and self_state.stick_tied
	if man == null or (man.stick_tied and not self_tied) \
			or not _man_is_a_live_target(snapshot, self_pos, decision.locked_man_pid, man,
					blade_reach, self_tied) \
			or not AIStickTieRead.shaft_in_reach(self_pos, man.top_hand_world,
					man.blade_contact_world, stick_lift_reach):
		_stick_tie_holding = false
		_tie_follow = Vector3.INF
		return Vector3.INF
	_stick_tie_holding = true
	_stick_tie_press_pending = not self_tied and (self_state == null \
			or self_state.stick_check_phase == StickCheckRules.Phase.IDLE)
	return step_tie_follow(man)


# One physics tick of the lagged follow onto the man's stick (see `_tie_follow`).
func step_tie_follow(man: SkaterNetworkState) -> Vector3:
	var stick_mid: Vector3 = man.top_hand_world.lerp(man.blade_contact_world, 0.5)
	if not _tie_follow.is_finite():
		_tie_follow = stick_mid
		return _tie_follow
	var k: float = 1.0 - exp(-1.0 / (float(_PhysicsConstants.PHYSICS_TICK)
			* StickCheckRules.TIE_LAG_BUDGET_S))
	_tie_follow += (stick_mid - _tie_follow) * k
	return _tie_follow


# The puck is coming to him — a loose puck whose path reaches his blade, or his
# carrier with an open lane — and we could not have got a stick on it ourselves.
# A tie is only STARTED on a puck still on its way: one already at his blade is
# his, loose for a tick under his own stickhandle or a contested pickup. A tie
# already made (`self_tied`) holds through the arrival, which is the reception it
# exists to deny.
func _man_is_a_live_target(snapshot: WorldSnapshot, self_pos: Vector3, man_pid: int,
		man: SkaterNetworkState, blade_reach: float, self_tied: bool) -> bool:
	var puck: PuckNetworkState = snapshot.puck_state
	var carrier_pid: int = puck.carrier_peer_id
	if carrier_pid == man_pid:
		return false
	if carrier_pid == -1:
		var receive_reach: float = PuckController.PICKUP_RADIUS + AIStickTieRead.RECEIVER_STEP_M
		if not self_tied and AIStickTieRead.puck_within(puck.position,
				man.blade_contact_world, receive_reach):
			return false
		return AIStickTieRead.path_passes_within(puck.position, puck.velocity,
				man.blade_contact_world, receive_reach) \
				and not AIStickTieRead.path_passes_within(puck.position, puck.velocity,
						self_pos, blade_reach)
	if _team_id_by_peer.get(carrier_pid, -1) == _team_id:
		return false
	var carrier: SkaterNetworkState = snapshot.skater_states.get(carrier_pid)
	if carrier == null:
		return false
	_fill_lane_sticks(snapshot, true)
	return AIStickTieRead.lane_open(carrier.position, man.position,
			_tie_defender_scratch, _tie_reach_scratch)


# Our stick is tied while our team has the puck or it is loose. If the feed is
# coming to us, pull the stick away from the one holding it; otherwise hold on,
# keeping that defender's stick out of the play (_stick_tie_holding_on). INF when
# there is nothing to pull free from, or when holding on.
func tie_yank_aim(snapshot: WorldSnapshot, self_pos: Vector3,
		self_state: SkaterNetworkState, ties_sticks: bool, blade_reach: float) -> Vector3:
	_stick_tie_holding_on = false
	if not ties_sticks or self_state == null or not self_state.stick_tied:
		return Vector3.INF
	var carrier_pid: int = snapshot.puck_state.carrier_peer_id
	if carrier_pid != -1 and _team_id_by_peer.get(carrier_pid, -1) != _team_id:
		return Vector3.INF
	# The partner is the tied opponent whose stick is nearest ours.
	var tier: SkaterNetworkState = null
	var best_d: float = INF
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var opp: SkaterNetworkState = snapshot.skater_states[pid]
		if not opp.stick_tied:
			continue
		var d: float = StickCheckRules.stick_gap(self_state.top_hand_world,
				self_state.blade_contact_world, opp.top_hand_world, opp.blade_contact_world)
		if d < best_d:
			best_d = d
			tier = opp
	if tier == null:
		return Vector3.INF
	if not _feed_is_coming_to(snapshot, self_state):
		_stick_tie_holding_on = true
		return Vector3.INF
	return AIStickTieRead.yank_aim(self_pos, self_state.blade_contact_world,
			tier.blade_contact_world, blade_reach)


# The puck is on its way to us: a loose puck whose path reaches our blade, or a
# teammate carrying with an open lane to us past the opponents' sticks.
func _feed_is_coming_to(snapshot: WorldSnapshot, self_state: SkaterNetworkState) -> bool:
	var puck: PuckNetworkState = snapshot.puck_state
	if puck.carrier_peer_id == -1:
		return AIStickTieRead.path_passes_within(puck.position, puck.velocity,
				self_state.blade_contact_world,
				PuckController.PICKUP_RADIUS + AIStickTieRead.RECEIVER_STEP_M)
	var carrier: SkaterNetworkState = snapshot.skater_states.get(puck.carrier_peer_id)
	if carrier == null or puck.carrier_peer_id == _peer_id:
		return false
	_fill_lane_sticks(snapshot, false)
	return AIStickTieRead.lane_open(carrier.position, self_state.position,
			_tie_defender_scratch, _tie_reach_scratch)


# One side's bodies and their reaches into the lane scratch: ours when `ours`.
func _fill_lane_sticks(snapshot: WorldSnapshot, ours: bool) -> void:
	_tie_defender_scratch.clear()
	_tie_reach_scratch.clear()
	for pid: int in snapshot.skater_states:
		if (_team_id_by_peer.get(pid, -1) == _team_id) != ours:
			continue
		_tie_defender_scratch.append(snapshot.skater_states[pid].position)
		_tie_reach_scratch.append(AILoosePuckChase.race_reach(_caps_by_peer.get(pid)))


# Holds the stick-check button for a lift or a tie the dispatch started. Runs
# every physics tick after dispatch, throttled or not, so the hold is continuous.
# `off_puck` is whether the bot is in OFF_PUCK, where a held-on tie keeps holding.
func apply_button(input: InputState, off_puck: bool) -> void:
	if _stick_tie_holding_on and off_puck:
		input.stick_check_held = true
		return
	if _stick_tie_holding and _stick_lift_hold_ticks <= 0:
		input.stick_check_held = true
		input.stick_check_pressed = _stick_tie_press_pending
		_stick_tie_press_pending = false
		return
	if _stick_lift_hold_ticks <= 0:
		return
	input.stick_check_held = true
	input.stick_check_pressed = _stick_lift_press_pending
	_stick_lift_press_pending = false
	_stick_lift_hold_ticks -= 1
