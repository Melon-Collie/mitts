class_name TurnoverTracker extends RefCounted
## Host-only attribution of takeaways / giveaways / interceptions / faceoff
## wins from possession changes. GameManager feeds it the authoritative hooks —
## a possession gain (puck picked up), an ESTABLISHED possession (see
## PossessionTracker), a strip (puck_stripped_from, carrying the defender who
## made the play), a shot attempt, and a non-shot release read as a pass or a
## dump — and it mutates the affected players' PlayerStats. The pure decision
## lives in TurnoverRules; this holds the short-lived context (last established
## owner + recent strip/shot/pass/dump) needed to classify each gain. A takeaway
## credits the STRIPPER (the defender who caused the loss), not whoever recovers
## the loose puck; recovering a shot (saved or missed) is neither a takeaway nor
## a giveaway.
##
## An interception is the other side of a giveaway on a pass: the opponent whose
## pickup FIRST ended the pass's flight is credited when the giveaway lands, as
## the stripper is when a takeaway lands. Takeaways stay strips only — picking
## off a pass is its own stat, not a takeaway.
##
## Crediting is deferred to ESTABLISHMENT: a pickup computes the candidate
## classification (against the last ESTABLISHED owner, with the open strip and
## the shot/dump/pass windows read at pickup time, when the context is
## freshest), but the stat
## lands only when that carrier establishes possession. A scramble of
## momentary touches — contested draws, board battles — therefore mints
## nothing until someone actually comes out of the pile with the puck.
##
## Faceoff wins follow the NHL definition: the draw is won by the team that
## FIRST ESTABLISHES possession after the drop (credited to that team's
## centre), not by the first blade to graze it. The win pends from the
## faceoff pickup until an establishment; resolve_pending_faceoff() is the
## terminal fallback (goal / whistle before anyone establishes) so every
## draw still gets a winner. While a draw is pending, no turnover is
## classified — the NHL never charges a giveaway/takeaway on the draw.
##
## Only ever constructed/called on the host (like HitTracker), so the stats
## it writes are authoritative and ride the normal stats broadcast.

# A recovery within a shot / dump window counts as a deliberate surrender (no
# turnover). The dump window covers the chase to a dumped puck. A strip has no
# window: it stays live until the next establishment consumes it, so a poked
# puck that skitters loose for a while before the stripper's side corrals it is
# still their takeaway, never the victim's giveaway.
const SHOT_WINDOW_S: float = 2.0
const DUMP_WINDOW_S: float = 3.0
# An opponent's pickup this soon after a pass picked it off; later, the pass has
# gone astray and the pickup is a loose-puck recovery. The farthest a pass can
# be aimed (TurnoverRules' corridor reach) covered at the softest feed.
const PASS_WINDOW_S: float = TurnoverRules.RECEIVER_MAX_DIST_M / AIPuckLane.SOFTEST_FEED_M_S

var _registry: PlayerRegistry = null
# () -> float seconds; wall clock unless a test injects one.
var _clock: Callable = Callable()
# Last ESTABLISHED possession — the "previous owner" a new gain classifies
# against. Unestablished touches never advance this.
var _last_established_peer: int = -1
var _last_established_team: int = -1
var _strip_open: bool = false
var _strip_victim_team: int = -1
# The defender who made the strip (poke / stick-lift / body-check). A takeaway
# is credited to THEM, not whoever recovers the loose puck. -1 for a goalie
# strip (no player takeaway).
var _strip_stripper_peer: int = -1
var _shot_time: float = -INF
var _shot_team: int = -1
var _dump_time: float = -INF
var _dump_team: int = -1
var _pass_time: float = -INF
var _pass_team: int = -1
# The opponent whose pickup first ended the last pass's flight, credited an
# interception if the giveaway it caused lands. -1 when none is pending.
var _interceptor_peer: int = -1
# Contested-loss veto: while a loose puck is unowned, we track whether the
# opponent of the last-established team has touched it, and — only after such an
# opponent touch — whether the last-established (losing) team has fought it back
# with a touch of its own. A giveaway that lands out of that back-and-forth is a
# lost board battle, not a clean cough-up, so it is vetoed at establishment. Both
# reset the moment anyone establishes possession.
var _loose_touched_by_opponent: bool = false
var _loser_recontacted: bool = false
# Candidate turnover computed at pickup, credited when the carrier establishes.
# Overwritten by the next pickup, so it always describes the current carrier.
var _candidate_type: String = TurnoverRules.NONE
var _candidate_carrier_peer: int = -1
var _candidate_credit_peer: int = -1
# Draw winner pending since the faceoff pickup, awaiting first establishment.
var _faceoff_pending: bool = false


func setup(registry: PlayerRegistry) -> void:
	_registry = registry


func set_clock(clock: Callable) -> void:
	_clock = clock


# Possession gained by `peer_id`. `was_faceoff` = this pickup ended a faceoff
# (first touch after the drop). Computes the turnover candidate; nothing is
# credited until on_possession_established.
func on_carrier_gained(peer_id: int, was_faceoff: bool) -> void:
	if _registry == null:
		return
	var rec: PlayerRecord = _registry.get_record(peer_id)
	if rec == null or rec.team == null:
		return
	var new_team: int = rec.team.team_id
	if was_faceoff:
		# The draw is live — winner pends until the first establishment. A
		# faceoff is a fresh start, so clear stale turnover context too.
		_faceoff_pending = true
		_clear_candidate()
		_strip_open = false
		_shot_time = -INF
		_pass_time = -INF
		_interceptor_peer = -1
		return
	if _faceoff_pending:
		# Draw scramble — no turnovers until the draw resolves.
		_clear_candidate()
		return
	# Track the loose-puck battle so a contested loss can be vetoed at
	# establishment (see the flag docs). A touch by the opponent of the losing
	# team opens the battle; a touch back BY the losing team after that is the
	# contest that voids the giveaway.
	if new_team != _last_established_team:
		_loose_touched_by_opponent = true
	elif _loose_touched_by_opponent:
		_loser_recontacted = true
	var now: float = _now()
	# The pass's flight ends at its first pickup: a teammate's is a completion,
	# an opponent's is the interception.
	if _pass_time + PASS_WINDOW_S > now and _pass_team == _last_established_team:
		if new_team != _pass_team:
			_interceptor_peer = peer_id
		_pass_time = -INF
	var recent_strip: bool = _strip_open \
			and _strip_victim_team == _last_established_team
	var recent_shot: bool = _shot_time + SHOT_WINDOW_S > now \
			and _shot_team == _last_established_team
	var recent_dump: bool = _dump_time + DUMP_WINDOW_S > now \
			and _dump_team == _last_established_team
	_candidate_type = TurnoverRules.classify(
			_last_established_team, new_team, recent_strip, recent_shot, recent_dump)
	_candidate_carrier_peer = peer_id
	match _candidate_type:
		TurnoverRules.TAKEAWAY:
			# The stripper, not this recoverer (-1 on a goalie strip credits none).
			_candidate_credit_peer = _strip_stripper_peer
		TurnoverRules.GIVEAWAY:
			_candidate_credit_peer = _last_established_peer
		_:
			_candidate_credit_peer = -1


# `peer_id` ESTABLISHED possession (held it, or made a deliberate play).
# Lands the pending faceoff win or turnover candidate and advances the
# last-established owner. Returns true when a stat was credited, so the
# caller knows to broadcast the stats now rather than on the next event.
func on_possession_established(peer_id: int) -> bool:
	if _registry == null:
		return false
	var rec: PlayerRecord = _registry.get_record(peer_id)
	if rec == null or rec.team == null:
		return false
	var credited: bool = false
	if _faceoff_pending:
		_faceoff_pending = false
		credited = _credit_faceoff_win(rec.team.team_id)
	elif _candidate_carrier_peer == peer_id:
		match _candidate_type:
			TurnoverRules.TAKEAWAY:
				# The stripper, who may be this recoverer or a teammate they fed.
				var taker: PlayerRecord = _registry.get_record(_candidate_credit_peer)
				if taker != null and taker.stats != null:
					taker.stats.takeaways += 1
					credited = true
			TurnoverRules.GIVEAWAY:
				# Veto a giveaway the losing team fought back for and still lost —
				# a contested board battle is not a clean cough-up (see the flag
				# docs). A clean interception/fumble (no recontact) still charges it.
				if not _loser_recontacted:
					var prev: PlayerRecord = _registry.get_record(_candidate_credit_peer)
					if prev != null and prev.stats != null:
						prev.stats.giveaways += 1
						credited = true
					if _credit_interception(rec.team.team_id):
						credited = true
	_clear_candidate()
	# Establishment resolves the loose-puck phase: consume the strip so the wide
	# window can't credit a stale takeaway on a later pickup, and clear the
	# contested-battle flags for the next possession.
	_strip_open = false
	_strip_stripper_peer = -1
	_strip_victim_team = -1
	_interceptor_peer = -1
	_loose_touched_by_opponent = false
	_loser_recontacted = false
	_last_established_peer = peer_id
	_last_established_team = rec.team.team_id
	return credited


# Terminal fallback so every draw has a winner: play stopped (goal, whistle)
# before anyone established, so the draw goes to `team_id` — the team of the
# last toucher at the stoppage (the scoring team on a goal). Returns true
# when a stat was credited.
func resolve_pending_faceoff(team_id: int) -> bool:
	if not _faceoff_pending:
		return false
	_faceoff_pending = false
	if team_id < 0:
		return false
	return _credit_faceoff_win(team_id)


func has_pending_faceoff() -> bool:
	return _faceoff_pending


# A defender stripped the puck from `victim_peer_id` (poke / stick-lift /
# body-check). `stripper_peer_id` is the defender who made the play — a takeaway
# credits THEM, not whoever recovers the loose puck. -1 (goalie strip) = no
# player takeaway.
func note_strip(victim_peer_id: int, stripper_peer_id: int) -> void:
	_strip_open = true
	_strip_victim_team = _team_of(victim_peer_id)
	_strip_stripper_peer = stripper_peer_id


# `shooter_peer_id` put the puck at the net (any shot attempt — saved, missed,
# or blocked). Opens the window in which recovering the loose puck reads as a
# rebound, not a turnover. Fed from every shot release, and refreshed at a
# confirmed shot-on-goal so a save's rebound stays covered past the shot flight.
func note_shot(shooter_peer_id: int) -> void:
	_shot_time = _now()
	_shot_team = _team_of(shooter_peer_id)


# `dumper_peer_id` deliberately surrendered the puck to open ice (a dump-and-chase,
# a zone clear, or a rim) — no receiver. Opens the window in which recovering the
# loose puck reads as a concession, not a giveaway. Fed from a non-shot release
# the geometry (TurnoverRules.is_dump_release) classifies as a dump, not a pass.
func note_dump(dumper_peer_id: int) -> void:
	_dump_time = _now()
	_dump_team = _team_of(dumper_peer_id)


# `passer_peer_id` released the puck at a teammate (a non-shot release that
# TurnoverRules.is_dump_release did not read as a dump). Opens the window in
# which an opponent's first pickup is an interception.
func note_pass(passer_peer_id: int) -> void:
	_pass_time = _now()
	_pass_team = _team_of(passer_peer_id)


# Clear all context (new game / rematch reset).
func reset() -> void:
	_last_established_peer = -1
	_last_established_team = -1
	_strip_open = false
	_strip_victim_team = -1
	_strip_stripper_peer = -1
	_shot_time = -INF
	_shot_team = -1
	_dump_time = -INF
	_dump_team = -1
	_pass_time = -INF
	_pass_team = -1
	_interceptor_peer = -1
	_loose_touched_by_opponent = false
	_loser_recontacted = false
	_clear_candidate()
	_faceoff_pending = false


func _clear_candidate() -> void:
	_candidate_type = TurnoverRules.NONE
	_candidate_carrier_peer = -1
	_candidate_credit_peer = -1


# The pending interceptor, if the giveaway just landed for their team.
func _credit_interception(establishing_team: int) -> bool:
	var interceptor: PlayerRecord = _registry.get_record(_interceptor_peer)
	if interceptor == null or interceptor.stats == null or interceptor.team == null \
			or interceptor.team.team_id != establishing_team:
		return false
	interceptor.stats.interceptions += 1
	return true


func _credit_faceoff_win(winning_team: int) -> bool:
	# The centre (team_slot 0) takes the draw, so the win/loss is theirs
	# regardless of which linemate actually corralled the loose puck. The
	# opposing centre is charged a loss so faceoff % has a real denominator.
	var credited: bool = false
	for pid: int in _registry.all():
		var r: PlayerRecord = _registry.get_record(pid)
		if r == null or r.team == null or r.team_slot != 0 or r.stats == null:
			continue
		if r.team.team_id == winning_team:
			r.stats.faceoff_wins += 1
			credited = true
		else:
			r.stats.faceoff_losses += 1
	return credited


func _team_of(peer_id: int) -> int:
	if _registry == null:
		return -1
	var r: PlayerRecord = _registry.get_record(peer_id)
	return r.team.team_id if r != null and r.team != null else -1


func _now() -> float:
	if _clock.is_valid():
		return float(_clock.call())
	return Time.get_ticks_msec() / 1000.0
