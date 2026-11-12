class_name PenaltyTracker
extends RefCounted

# The referee and the penalty box (docs/penalties-plan.md). On the host it
# judges each contact between opponents (PenaltyRules), holds the call until
# the offending team has the puck, and runs the minors; on every peer it seats
# the boxed skaters from the ledger, which a client receives whole whenever it
# changes.

# Host: a foul was judged and the delayed call is up.
signal foul_called(peer_id: int, foul: int)
# Host: the team a call is pending against has the puck, so play is to stop.
signal possession_whistle(offending_team_id: int)
# Host: the ledger changed and peers need it.
signal ledger_changed
# Every peer: a skater went into the box, or came out of it.
signal skater_boxed(peer_id: int)
signal skater_released(peer_id: int)

# A boxed skater is hidden once he is this close to his door.
const _BOX_HIDE_DIST_SQ: float = 0.75 * 0.75

var ledger := PenaltyLedger.new()
# What the last call was judged on, for the F3 overlay.
var last_call_facts: String = ""

var _registry: PlayerRegistry = null
var _state_buffer: StateBufferManager = null
var _puck_getter: Callable = Callable()
var _rewind_scratch := WorldSnapshot.new()


func setup(registry: PlayerRegistry, state_buffer: StateBufferManager,
		puck_getter: Callable) -> void:
	_registry = registry
	_state_buffer = state_buffer
	_puck_getter = puck_getter


func clear() -> void:
	ledger.clear()
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
	if not ledger.call_foul(hitter_peer_id, hitter.team.team_id, foul):
		return
	last_call_facts = "%s  force %.1f  into boards %s  from behind %s (facing·drive %.2f)" \
			% [PenaltyRules.Foul.keys()[foul], force, into_boards, from_behind,
				facing_before.dot(drive)] \
			+ "  eligible %s (carrier %s, lost puck %.2fs ago, puck %.1fm, loose %s)" \
			% [eligible, victim_is_carrier, seconds_since_victim_lost_puck, puck_dist, puck_loose]
	foul_called.emit(hitter_peer_id, foul)
	ledger_changed.emit()


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


# Every pending call becomes a minor. Called as a faceoff is placed, so the
# men it boxes skate to their doors rather than to a spot.
func assess_pending(period_duration: float, team_size: int) -> void:
	if not ledger.has_pending():
		return
	ledger.assess(PenaltyRules.minor_seconds(period_duration),
			PenaltyRules.max_serving(team_size))
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


# Seats and releases skaters to match the ledger. A released skater stands at
# his door facing the ice; on a client only the host's snapshots move a remote
# one, and the local one is put there by its next reconcile.
func apply_box_state() -> void:
	if _registry == null:
		return
	for peer_id: int in _registry.all():
		var record: PlayerRecord = _registry.get_record(peer_id)
		if record == null or record.skater == null:
			continue
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
