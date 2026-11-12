class_name PenaltyTracker
extends RefCounted

# The referee, the penalty box and the penalty shot (docs/penalties-plan.md).
# On the host it judges each contact between opponents (PenaltyRules), holds
# the call until the offending team has the puck, runs the minors and judges a
# penalty shot; on every peer it seats the boxed skaters and sidelines the ones
# watching a shot from the ledger, which a client receives whole whenever it
# changes.

# Host: a foul was judged and the delayed call is up.
signal foul_called(peer_id: int, foul: int)
# Host: the team a call is pending against has the puck, so play is to stop.
signal possession_whistle(offending_team_id: int)
# Host: the ledger changed and peers need it.
signal ledger_changed
# Host: a call was paid for, by a minor or by giving up a penalty shot.
signal penalty_assessed(peer_id: int)
# Every peer: a skater went into the box, or came out of it.
signal skater_boxed(peer_id: int)
signal skater_released(peer_id: int)
# Every peer: a penalty shot was set up for `shooter_peer_id`, or is over.
signal shot_staged(shooter_peer_id: int)
signal shot_over
# Host: the shot on is over without a goal.
signal shot_missed

# A boxed skater is hidden once he is this close to his door.
const _BOX_HIDE_DIST_SQ: float = 0.75 * 0.75
# How long a shooter has to collect the puck laid for him.
const _SHOT_COLLECT_S: float = GameRules.FACEOFF_TIMEOUT

var ledger := PenaltyLedger.new()
# What the last call was judged on, for the F3 overlay.
var last_call_facts: String = ""

var _registry: PlayerRegistry = null
var _state_buffer: StateBufferManager = null
var _puck_getter: Callable = Callable()
var _rewind_scratch := WorldSnapshot.new()
# The penalty shot on, as the host judges it, and who this peer last knew to
# be taking one (-1 for none).
var _shot := PenaltyShotAttempt.new()
var _staged_shooter: int = -1
# The goalie has the puck: the shot on is over at the next tick_shot.
var _shot_saved: bool = false
# Host: the men who have fought in the stoppage under way.
var _fighters: Array[int] = []


func setup(registry: PlayerRegistry, state_buffer: StateBufferManager,
		puck_getter: Callable) -> void:
	_registry = registry
	_state_buffer = state_buffer
	_puck_getter = puck_getter


func clear() -> void:
	ledger.clear()
	_fighters.clear()
	apply_box_state()


# ── Host: the call ───────────────────────────────────────────────────────────

# HitTracker.opposing_contact. Sustained contact re-fires this every tick, so
# the gates PenaltyRules.judge would fail anyway come first.
func on_opposing_contact(hitter_peer_id: int, victim_peer_id: int, force: float,
		hit_dir: Vector3, attacker_has_puck: bool, victim_is_carrier: bool,
		seconds_since_victim_lost_puck: float, attacker_committed: bool) -> void:
	if not attacker_committed or attacker_has_puck \
			or force < HitRules.FULL_CHECK_IMPULSE:
		return
	var hitter: PlayerRecord = _registry.get_record(hitter_peer_id)
	var victim: PlayerRecord = _registry.get_record(victim_peer_id)
	if hitter == null or victim == null or hitter.skater == null or victim.skater == null:
		return
	if hitter.skater.is_ghost or victim.skater.is_ghost:
		return
	var victim_pos: Vector3 = victim.skater.global_position
	var puck: Puck = _puck_getter.call() as Puck
	var puck_loose: bool = puck != null and puck.carrier == null
	var puck_dist: float = INF
	if puck != null:
		puck_dist = Vector2(puck.global_position.x - victim_pos.x,
				puck.global_position.z - victim_pos.z).length()
	var eligible: bool = PenaltyRules.is_eligible_to_be_hit(victim_is_carrier,
			seconds_since_victim_lost_puck, puck_loose, puck_dist)
	var drive := Vector2(hit_dir.x, hit_dir.z)
	var wall_out: Vector2 = BoardWallRules.wall_normal(victim_pos,
			victim.skater.collision_radius(), PenaltyRules.BOARDING_ZONE_M)
	var facing_before: Vector2 = _facing_before_contact(victim)
	var into_boards: bool = PenaltyRules.is_driven_into_boards(drive, wall_out)
	var from_behind: bool = PenaltyRules.is_hit_from_behind(facing_before, drive)
	var foul: PenaltyRules.Foul = PenaltyRules.judge(force, attacker_committed,
			attacker_has_puck, eligible, into_boards, from_behind)
	if foul == PenaltyRules.Foul.NONE:
		return
	if not ledger.call_foul(hitter_peer_id, hitter.team.team_id, foul, victim_peer_id):
		return
	last_call_facts = "%s  force %.1f  into boards %s  from behind %s (facing·drive %.2f)" \
			% [PenaltyRules.Foul.keys()[foul], force, into_boards, from_behind,
				facing_before.dot(drive)] \
			+ "  eligible %s (carrier %s, lost puck %.2fs ago, puck %.1fm, loose %s)" \
			% [eligible, victim_is_carrier, seconds_since_victim_lost_puck, puck_dist, puck_loose]
	foul_called.emit(hitter_peer_id, foul)
	ledger_changed.emit()


# Host: two men have dropped the gloves.
func note_fight(a_peer_id: int, b_peer_id: int) -> void:
	_fighters.append(a_peer_id)
	_fighters.append(b_peer_id)


# Host: the fights are over, and each man who fought is called for it. The
# faceoff placed next assesses the calls and tells the other peers, so the
# ledger is not announced from here.
func call_fighters() -> void:
	for peer_id: int in _fighters:
		var fighter: PlayerRecord = _registry.get_record(peer_id)
		if fighter != null and fighter.team != null and ledger.call_foul(
				peer_id, fighter.team.team_id, PenaltyRules.Foul.FIGHTING):
			foul_called.emit(peer_id, PenaltyRules.Foul.FIGHTING)
	_fighters.clear()


func on_possession_established(team_id: int) -> void:
	if ledger.has_pending_against(team_id):
		possession_whistle.emit(team_id)


# A goal against the shorter team ends its soonest minor; one against a team
# at even strength with a call pending washes that call out.
func on_goal(scoring_team_id: int, team_size: int) -> void:
	var released: int = ledger.release_for_goal(scoring_team_id, team_size,
			PenaltyRules.max_serving(team_size))
	if released == -1 and ledger.waive_one_against(1 - scoring_team_id) == -1:
		return
	apply_box_state()
	ledger_changed.emit()


# Every pending call is paid for: a minor each, or one penalty shot where a
# foul is a shot (PenaltyRules.awards_penalty_shot). Called as a faceoff is
# placed, so that placement skates the boxed to their doors, or sets the shot
# up in the faceoff's place.
func assess_pending(period_duration: float, team_size: int) -> void:
	if not ledger.has_pending():
		return
	if PenaltyRules.awards_penalty_shot(team_size):
		_stage_shot()
	else:
		for peer_id: int in ledger.assess(PenaltyRules.minor_seconds(period_duration),
				PenaltyRules.max_serving(team_size)):
			penalty_assessed.emit(peer_id)
	apply_box_state()
	ledger_changed.emit()


func _stage_shot() -> void:
	var shooter: PlayerRecord = _registry.get_record(ledger.stage_shot())
	if shooter == null or shooter.skater == null or shooter.team == null:
		ledger.end_shot()  # the man fouled has left: nobody takes it
		return
	var attack_dir_z: float = -PlayerRules.own_goal_dir(shooter.team.team_id)
	_shot.max_wait_s = _SHOT_COLLECT_S
	_shot.ends_when_shot_dies = true
	_shot.begin(attack_dir_z, attack_dir_z * GameRules.GOAL_LINE_Z, GameRules.NET_HALF_WIDTH)
	_shot_saved = false
	penalty_assessed.emit(ledger.shot_offender_peer_id())


func is_shot_on() -> bool:
	return ledger.shooter_peer_id() != -1


# Host: steps the shot on; call each tick the puck is live. Emits shot_missed
# when it is over without a goal. A goal is the goal line's to call.
func tick_shot(delta: float) -> void:
	var shooter: PlayerRecord = _registry.get_record(ledger.shooter_peer_id())
	var puck: Puck = _puck_getter.call() as Puck
	if shooter == null or shooter.skater == null or puck == null or _shot_saved:
		shot_missed.emit()
		return
	if _shot.step(delta, shooter.skater.global_position.z, puck.carrier == shooter.skater,
			puck.get_puck_position(), puck.get_puck_velocity().z) \
			== PenaltyShotRules.Outcome.MISS:
		shot_missed.emit()


# Host: the goalie smothered or caught the puck. Noted, not acted on: the
# cover is reported from inside the puck's own tick.
func note_shot_saved() -> void:
	_shot_saved = true


# Host: the shot is over, whichever way it went.
func end_shot() -> void:
	if not is_shot_on():
		return
	ledger.end_shot()
	apply_box_state()
	ledger_changed.emit()


# Runs the minors' clocks; call only while the game clock runs.
func tick(delta: float, team_size: int) -> void:
	if ledger.is_empty():
		return
	if ledger.tick(delta, PenaltyRules.max_serving(team_size)).is_empty():
		return
	apply_box_state()
	ledger_changed.emit()


# The team with fewer skaters on the ice, -1 at even strength.
func short_handed_team(team_size: int) -> int:
	var home: int = ledger.strength(0, team_size)
	var away: int = ledger.strength(1, team_size)
	if home == away:
		return -1
	return 0 if home < away else 1


# ── Every peer: the box ──────────────────────────────────────────────────────

func apply_remote(wire: Array) -> void:
	ledger.from_wire(wire)
	apply_box_state()


# Seats, sidelines and releases skaters to match the ledger. A released
# skater stands at his door facing the ice; on a client only the host's
# snapshots move a remote one, and the local one is put there by its next
# reconcile.
func apply_box_state() -> void:
	if _registry == null:
		return
	var shooter: int = ledger.shooter_peer_id()
	for peer_id: int in _registry.all():
		var record: PlayerRecord = _registry.get_record(peer_id)
		if record == null or record.skater == null:
			continue
		record.skater.takes_penalty_shot = peer_id == shooter
		record.skater.sidelined = shooter != -1 and peer_id != shooter
		var boxed: bool = ledger.is_boxed(peer_id)
		if record.skater.in_box == boxed:
			continue
		record.skater.in_box = boxed
		if boxed:
			skater_boxed.emit(peer_id)
			continue
		record.skater.visible = true
		if record.controller != null and record.team != null:
			record.controller.teleport_to(
					PlayerRules.penalty_box_position(record.team.team_id),
					PlayerRules.penalty_box_facing())
		skater_released.emit(peer_id)
	if shooter == _staged_shooter:
		return
	_staged_shooter = shooter
	if shooter == -1:
		shot_over.emit()
	else:
		shot_staged.emit(shooter)


# Hides a boxed skater once he has reached his door, or once play is back on.
# A released one is shown by apply_box_state.
func update_visibility(in_faceoff_prep: bool) -> void:
	if ledger.is_empty() or _registry == null:
		return
	for peer_id: int in _registry.all():
		var record: PlayerRecord = _registry.get_record(peer_id)
		if record == null or record.skater == null or not record.skater.in_box \
				or not record.skater.visible:
			continue
		var door: Vector3 = PlayerRules.penalty_box_position(record.team.team_id)
		var dx: float = record.skater.global_position.x - door.x
		var dz: float = record.skater.global_position.z - door.z
		if not in_faceoff_prep or dx * dx + dz * dz < _BOX_HIDE_DIST_SQ:
			record.skater.visible = false


func _facing_before_contact(victim: PlayerRecord) -> Vector2:
	if _state_buffer != null and _state_buffer.is_ready():
		_state_buffer.get_state_at(_state_buffer.newest_host_timestamp()
				- PenaltyRules.BOARDING_TURN_GRACE_S, _rewind_scratch)
		var before: SkaterNetworkState = _rewind_scratch.get_skater_state(victim.peer_id)
		if before != null:
			return before.facing
	return victim.skater.get_facing()
