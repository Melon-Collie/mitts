class_name SkaterAgentBoardPlay
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# Board play: how hard a pinner keeps driving into the wall against how hard he
# slides (unit-free weights of one move vector), how fast he closes an along-wall
# offset on top of matching the man's slide, the along-wall speed error at which
# his slide input is full, how close a checker holding his stick out has to be
# before a carrier answers him, and the least time between a pinned bot's
# reversals (one must land before the next).
const PIN_MIRROR_DRIVE: float = 0.7
const PIN_MIRROR_CLOSE_S: float = 0.25
const PIN_MIRROR_SPEED_GAIN_M_S: float = 0.3
const PIN_THREAT_RANGE_M: float = 2.5
const PIN_REVERSAL_MIN_TICKS: int = _PhysicsConstants.PHYSICS_TICK * 3 / 20   # ~150 ms
# A pin is reached for this long before contact: the stick held out past the hook
# (StickCheckRules.RISE_S + HOOK_MAX_S) when the bodies meet, plus a tick of slack.
const PIN_REACH_S: float = StickCheckRules.RISE_S + StickCheckRules.HOOK_MAX_S \
		+ 1.0 / _PhysicsConstants.PHYSICS_TICK

static var _balance_cfg := BodyBalanceRules.Config.new()

# One bot's board play, every physics tick after dispatch. Owns only its pin
# state; the tier's knobs and the bot's state come in per call.

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
var _caps_by_peer: Dictionary = {}
# As the pinner, where the man is read to be and how fast he is going
# (lagged like a human's read, INF when not pinning). As the pinned, which way we
# slide along the wall (0 when not pinned) and the ticks until we may reverse.
var _pin_follow: Vector3 = Vector3.INF
var _pin_follow_vel: Vector3 = Vector3.ZERO
var _pin_slide_sign: float = 0.0
var _pin_flip_ticks: int = 0


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		caps_by_peer: Dictionary) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer


# The boards, every physics tick after dispatch (BoardPinRules).
# - Locked as the pinner: hold the stick button only while the pin is worth it
#   (_pin_worth_holding), driving into the wall and mirroring the victim's slide
#   through the same network lag a human pinner reads it with.
# - Locked as the pinned: slide along the wall, and reverse when the pinner commits
#   to following — the juke that gets a body past his.
# - Driving a check into a man at the wall that will not knock him down, where a
#   pin is worth it: reach for the pin instead (_reach_for_pin).
# - Carrying at the wall with a checker coming square, stick out: get out of his
#   line along the wall if that beats him there, else brace (hold the commit),
#   which cannot be pinned (AIPinThreatRead).
# `check_aggression` is the tier's PACE physicality knob (0 never holds a pin);
# `answers_pin_threats` is a carrier with the protects_the_puck gate open;
# `max_accel` this bot's own.
func apply(input: InputState, snapshot: WorldSnapshot, own_goal_dir: float,
		check_aggression: float, answers_pin_threats: bool, max_accel: float) -> void:
	if snapshot == null or snapshot.puck_state == null:
		return
	var me: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if me == null:
		return
	match me.pin_role:
		BoardPinRules.Role.PINNED:
			input.move_vector = _pinned_slide(snapshot, me)
			return
		BoardPinRules.Role.PINNER:
			var man_pid: int = _my_pinned_man(snapshot, me)
			if man_pid == -1 or check_aggression <= 0.0 \
					or not _pin_worth_holding(snapshot, me, man_pid, own_goal_dir):
				# Let go: the dispatch may still be holding the button for a tie.
				input.stick_check_held = false
				input.stick_check_pressed = false
				_pin_follow = Vector3.INF
				return
			input.stick_check_held = true
			input.stick_check_pressed = false
			input.move_vector = _pinner_mirror(snapshot.skater_states[man_pid], me)
			return
	_pin_follow = Vector3.INF
	_pin_slide_sign = 0.0
	if check_aggression > 0.0 and input.hit_held:
		_reach_for_pin(input, snapshot, me, own_goal_dir)
	if answers_pin_threats:
		_answer_pin_threat(input, snapshot, me, max_accel)


# The dispatch is driving a check: when its man is against the boards in front of
# us, about to be touched, unbraced, and the hit will not knock him down (the
# collision's own victim_kick against his balance, as the host reads it — the
# boards add to the stagger, not the knockdown), reach for the
# pin instead where one is worth holding. The stick goes out on the button, so the
# commit lets go: the check and the pin are two buttons.
func _reach_for_pin(input: InputState, snapshot: WorldSnapshot, me: SkaterNetworkState,
		own_goal_dir: float) -> void:
	var caps: AISkaterCaps = _caps_by_peer.get(_peer_id)
	var transfer: float = caps.body_check_transfer if caps != null else 0.65
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var man: SkaterNetworkState = snapshot.skater_states[pid]
		if man.hit_committed or man.pin_role != BoardPinRules.Role.NONE:
			continue
		var out: Vector2 = BoardPinRules.wall_normal(man.position, GameRules.OFFSIDE_LINE_SLACK,
				BoardPinRules.PIN_WALL_MARGIN_M)
		if out == Vector2.ZERO:
			continue
		var to_man := Vector2(man.position.x - me.position.x, man.position.z - me.position.z)
		var dist: float = to_man.length()
		if dist < 1e-4 or (to_man / dist).dot(out) < BoardPinRules.BACKSTOP_MIN_INTO_WALL:
			continue
		if AIPinThreatRead.time_to_contact(man.position, man.velocity, me.position,
				me.velocity) > PIN_REACH_S:
			continue
		var closing: float = maxf(Vector2(me.velocity.x - man.velocity.x,
				me.velocity.z - man.velocity.z).dot(to_man / dist), 0.0)
		var man_caps: AISkaterCaps = _caps_by_peer.get(pid)
		var kick: float = SkaterCollisionRules.victim_kick(closing,
				caps.weight if caps != null else 1.0,
				man_caps.weight if man_caps != null else 1.0, transfer)
		var posture: BodyBalanceRules.Posture = BodyBalanceRules.posture_of(man.stance_active,
				SkaterStateMachine.state_off_balance(man.shot_state))
		if BodyBalanceRules.overshoot(to_man / dist * kick, man.facing, posture,
				man_caps.height_mult if man_caps != null else 1.0, _balance_cfg) > 1.0 \
				or not _pin_worth_holding(snapshot, me, pid, own_goal_dir):
			return
		input.hit_held = false
		input.stick_check_held = true
		input.stick_check_pressed = me.stick_check_phase == StickCheckRules.Phase.IDLE
		return


# The pinned man: the PINNED opponent nearest us, or -1.
func _my_pinned_man(snapshot: WorldSnapshot, me: SkaterNetworkState) -> int:
	var best: int = -1
	var best_d: float = INF
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var opp: SkaterNetworkState = snapshot.skater_states[pid]
		if opp.pin_role != BoardPinRules.Role.PINNED:
			continue
		var d: float = opp.position.distance_to(me.position)
		if d < best_d:
			best_d = d
			best = pid
	return best


# What is taught: pin while our support beats theirs to the puck, or in our own
# end to kill the play; never as the last skater back outside our own end.
func _pin_worth_holding(snapshot: WorldSnapshot, me: SkaterNetworkState, man_pid: int,
		own_goal_dir: float) -> bool:
	var own_end: bool = own_goal_dir * me.position.z > GameRules.BLUE_LINE_Z
	if not own_end and _last_back(snapshot, me, own_goal_dir):
		return false
	var puck_pos: Vector3 = snapshot.puck_state.position
	var ours: float = _team_arrival_s(snapshot, puck_pos, _team_id, man_pid)
	var theirs: float = _team_arrival_s(snapshot, puck_pos,
			_team_id_by_peer.get(man_pid, -1), man_pid)
	return ours <= theirs or own_end


# No teammate stands between us and our own net.
func _last_back(snapshot: WorldSnapshot, me: SkaterNetworkState, own_goal_dir: float) -> bool:
	var net := Vector3(0.0, 0.0, own_goal_dir * GameRules.GOAL_LINE_Z)
	var mine: float = me.position.distance_to(net)
	for pid: int in snapshot.skater_states:
		if pid == _peer_id or _team_id_by_peer.get(pid, -1) != _team_id:
			continue
		if snapshot.skater_states[pid].position.distance_to(net) < mine:
			return false
	return true


# The soonest a skater of `team` (not us, not the locked man) reaches `at` at top
# speed — the momentum-blind bound, the same for both sides.
func _team_arrival_s(snapshot: WorldSnapshot, at: Vector3, team: int, man_pid: int) -> float:
	var best: float = INF
	for pid: int in snapshot.skater_states:
		if pid == _peer_id or pid == man_pid or _team_id_by_peer.get(pid, -1) != team:
			continue
		var caps: AISkaterCaps = _caps_by_peer.get(pid)
		var top: float = caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
		best = minf(best, snapshot.skater_states[pid].position.distance_to(at) / maxf(top, 0.1))
	return best


# Drive into the wall, and slide with the man as he is read: his body and his
# slide followed through a lag of BoardPinRules.PIN_LAG_BUDGET_S, so a bot pinner
# is beaten by the same reversals a human pinner would be. Matching his slide is
# what keeps up with a steady one; the offset is closed on top of it.
func _pinner_mirror(man: SkaterNetworkState, me: SkaterNetworkState) -> Vector2:
	if not _pin_follow.is_finite():
		_pin_follow = man.position
		_pin_follow_vel = man.velocity
	else:
		var k: float = 1.0 - exp(-1.0 / (float(_PhysicsConstants.PHYSICS_TICK)
				* BoardPinRules.PIN_LAG_BUDGET_S))
		_pin_follow += (man.position - _pin_follow) * k
		_pin_follow_vel += (man.velocity - _pin_follow_vel) * k
	var out: Vector2 = BoardPinRules.wall_normal(man.position, GameRules.OFFSIDE_LINE_SLACK,
			BoardPinRules.PIN_WALL_RELEASE_M)
	if out == Vector2.ZERO:
		return Vector2.ZERO
	var along := Vector2(-out.y, out.x)
	var offset: float = BoardPinRules.along_wall_offset(_pin_follow, me.position, out)
	var want: float = Vector2(_pin_follow_vel.x, _pin_follow_vel.z).dot(along) \
			+ offset / PIN_MIRROR_CLOSE_S
	var have: float = Vector2(me.velocity.x, me.velocity.z).dot(along)
	return (out * PIN_MIRROR_DRIVE + along * clampf((want - have) / PIN_MIRROR_SPEED_GAIN_M_S,
			-1.0, 1.0)).normalized()


# Slide along the wall, reversing whenever the pinner has committed to following
# the slide (his along-wall speed our way, past half our cap) and the last
# reversal has had time to land.
func _pinned_slide(snapshot: WorldSnapshot, me: SkaterNetworkState) -> Vector2:
	var out: Vector2 = BoardPinRules.wall_normal(me.position, GameRules.OFFSIDE_LINE_SLACK,
			BoardPinRules.PIN_WALL_RELEASE_M)
	if out == Vector2.ZERO:
		return Vector2.ZERO
	var along := Vector2(-out.y, out.x)
	var pinner: SkaterNetworkState = _nearest_opponent_state(snapshot, me)
	if _pin_slide_sign == 0.0:
		var rel := Vector2.ZERO if pinner == null else Vector2(
				pinner.position.x - me.position.x, pinner.position.z - me.position.z)
		_pin_slide_sign = -1.0 if rel.dot(along) > 0.0 else 1.0
		_pin_flip_ticks = 0
	_pin_flip_ticks = maxi(_pin_flip_ticks - 1, 0)
	if pinner != null and _pin_flip_ticks == 0:
		var pv: float = Vector2(pinner.velocity.x, pinner.velocity.z).dot(along)
		var cap: float = BoardPinRules.slide_cap(BoardPinRules.Role.PINNED, me.pin_strength)
		if signf(pv) == _pin_slide_sign and absf(pv) >= 0.5 * cap:
			_pin_slide_sign = -_pin_slide_sign
			_pin_flip_ticks = PIN_REVERSAL_MIN_TICKS
	return along * _pin_slide_sign


func _nearest_opponent_state(snapshot: WorldSnapshot, me: SkaterNetworkState) -> SkaterNetworkState:
	var best: SkaterNetworkState = null
	var best_d: float = INF
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var opp: SkaterNetworkState = snapshot.skater_states[pid]
		var d: float = opp.position.distance_to(me.position)
		if d < best_d:
			best_d = d
			best = opp
	return best


# The most urgent opponent coming square into the boards we are against with his
# stick held out (the pin's button), answered: skate out of his line along the
# wall if that is done before he arrives, else brace. Nothing when there is none.
func _answer_pin_threat(input: InputState, snapshot: WorldSnapshot,
		me: SkaterNetworkState, max_accel: float) -> void:
	var out: Vector2 = BoardPinRules.wall_normal(me.position, GameRules.OFFSIDE_LINE_SLACK,
			BoardPinRules.PIN_WALL_RELEASE_M)
	if out == Vector2.ZERO:
		return
	var threat: SkaterNetworkState = null
	var ttc: float = INF
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == _team_id:
			continue
		var opp: SkaterNetworkState = snapshot.skater_states[pid]
		if not StickCheckRules.is_stick_busy(opp.stick_check_phase):
			continue
		var to_me := Vector2(me.position.x - opp.position.x, me.position.z - opp.position.z)
		var dist: float = to_me.length()
		if dist > PIN_THREAT_RANGE_M or dist < 1e-4 \
				or (to_me / dist).dot(out) < BoardPinRules.BACKSTOP_MIN_INTO_WALL:
			continue
		var t: float = AIPinThreatRead.time_to_contact(me.position, me.velocity,
				opp.position, opp.velocity)
		if threat == null or t < ttc:
			threat = opp
			ttc = t
	if threat == null:
		return
	var along := Vector2(-out.y, out.x)
	var offset: float = BoardPinRules.along_wall_offset(me.position, threat.position, out)
	var along_vel: float = Vector2(me.velocity.x, me.velocity.z).dot(along)
	var dir_sign: float = AIPinThreatRead.escape_sign(offset, along_vel)
	var escape_s: float = AIPinThreatRead.escape_time(offset, along_vel, max_accel,
			dir_sign)
	if AIPinThreatRead.answer(ttc, escape_s) == AIPinThreatRead.Answer.ESCAPE:
		input.move_vector = along * dir_sign
	else:
		input.hit_held = true
