class_name PenaltyLedger
extends RefCounted

# Who has been called for what, and who is sitting for it. A foul is PENDING
# from the call until the next stoppage assesses it; then it is SERVING, its
# clock running with the game clock, or QUEUED behind a team's other minors
# when one more would put it below PenaltyRules.MIN_SKATERS. A QUEUED man sits
# in the box all the same.

enum State { PENDING, SERVING, QUEUED }

# One entry on the wire: peer id, team id, foul, state, time left in ms.
const WIRE_STRIDE: int = 5


class Entry:
	var peer_id: int = -1
	var team_id: int = -1
	var foul: int = PenaltyRules.Foul.NONE
	var state: int = State.PENDING
	var remaining: float = 0.0


# Oldest first: the order minors start, and the order the queue is promoted in.
var entries: Array[Entry] = []
var _released_scratch: Array[int] = []


func clear() -> void:
	entries.clear()


func is_empty() -> bool:
	return entries.is_empty()


# Records a call against `peer_id`. A man already called or already sitting
# is not called again.
func call_foul(peer_id: int, team_id: int, foul: int) -> bool:
	if _find(peer_id) != null:
		return false
	var entry := Entry.new()
	entry.peer_id = peer_id
	entry.team_id = team_id
	entry.foul = foul
	entries.append(entry)
	return true


func has_pending() -> bool:
	for entry: Entry in entries:
		if entry.state == State.PENDING:
			return true
	return false


func has_pending_against(team_id: int) -> bool:
	for entry: Entry in entries:
		if entry.state == State.PENDING and entry.team_id == team_id:
			return true
	return false


# The fouled team scored before the whistle: the oldest call against
# `team_id` is washed out. Returns the man let off, -1 for none.
func waive_one_against(team_id: int) -> int:
	for i: int in entries.size():
		var entry: Entry = entries[i]
		if entry.state == State.PENDING and entry.team_id == team_id:
			entries.remove_at(i)
			return entry.peer_id
	return -1


# Turns every pending call into a minor of `minor_s`. Returns the men sent to
# the box.
func assess(minor_s: float, max_serving: int) -> Array[int]:
	var assessed: Array[int] = []
	for entry: Entry in entries:
		if entry.state != State.PENDING:
			continue
		entry.remaining = minor_s
		entry.state = State.SERVING if _serving_count(entry.team_id) < max_serving \
				else State.QUEUED
		assessed.append(entry.peer_id)
	return assessed


# Runs the serving minors' clocks. Returns the men whose time is up, in a
# scratch array valid until the next call.
func tick(delta: float, max_serving: int) -> Array[int]:
	_released_scratch.clear()
	if entries.is_empty():
		return _released_scratch
	for i: int in range(entries.size() - 1, -1, -1):
		var entry: Entry = entries[i]
		if entry.state != State.SERVING:
			continue
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			_released_scratch.append(entry.peer_id)
			entries.remove_at(i)
	if not _released_scratch.is_empty():
		_promote_queued(max_serving)
	return _released_scratch


# The display clock on a peer that only mirrors the ledger: it runs the time
# down and waits to be told who came out.
func tick_mirror(delta: float) -> void:
	for entry: Entry in entries:
		if entry.state == State.SERVING:
			entry.remaining = maxf(entry.remaining - delta, 0.0)


# A goal against a team with fewer skaters ends the minor of theirs nearest
# its end. Returns the man released, -1 when the teams were even or the
# scoring team was the one short.
func release_for_goal(scoring_team_id: int, team_size: int, max_serving: int) -> int:
	var conceding_team_id: int = 1 - scoring_team_id
	if strength(conceding_team_id, team_size) >= strength(scoring_team_id, team_size):
		return -1
	var soonest: int = -1
	for i: int in entries.size():
		var entry: Entry = entries[i]
		if entry.state != State.SERVING or entry.team_id != conceding_team_id:
			continue
		if soonest == -1 or entry.remaining < entries[soonest].remaining:
			soonest = i
	if soonest == -1:
		return -1
	var released: int = entries[soonest].peer_id
	entries.remove_at(soonest)
	_promote_queued(max_serving)
	return released


# Skaters `team_id` has on the ice.
func strength(team_id: int, team_size: int) -> int:
	return team_size - _serving_count(team_id)


# In the box: serving, or waiting to.
func is_boxed(peer_id: int) -> bool:
	var entry: Entry = _find(peer_id)
	return entry != null and entry.state != State.PENDING


# Time left on the minor of `team_id`'s that ends first; -1 with none running.
func soonest_remaining(team_id: int) -> float:
	var soonest: float = -1.0
	for entry: Entry in entries:
		if entry.state == State.SERVING and entry.team_id == team_id \
				and (soonest < 0.0 or entry.remaining < soonest):
			soonest = entry.remaining
	return soonest


func remaining_for(peer_id: int) -> float:
	var entry: Entry = _find(peer_id)
	return entry.remaining if entry != null else 0.0


func foul_of(peer_id: int) -> int:
	var entry: Entry = _find(peer_id)
	return entry.foul if entry != null else PenaltyRules.Foul.NONE


# A player who rejoins mid-penalty comes back under a new peer id.
func rebind(old_peer_id: int, new_peer_id: int) -> void:
	var entry: Entry = _find(old_peer_id)
	if entry != null:
		entry.peer_id = new_peer_id


func to_wire() -> Array:
	var wire: Array = []
	for entry: Entry in entries:
		wire.append_array([entry.peer_id, entry.team_id, entry.foul, entry.state,
				roundi(entry.remaining * 1000.0)])
	return wire


func from_wire(wire: Array) -> void:
	entries.clear()
	for at: int in range(0, wire.size() - WIRE_STRIDE + 1, WIRE_STRIDE):
		var entry := Entry.new()
		entry.peer_id = int(wire[at])
		entry.team_id = int(wire[at + 1])
		entry.foul = int(wire[at + 2])
		entry.state = int(wire[at + 3])
		entry.remaining = int(wire[at + 4]) / 1000.0
		entries.append(entry)


func _find(peer_id: int) -> Entry:
	for entry: Entry in entries:
		if entry.peer_id == peer_id:
			return entry
	return null


func _serving_count(team_id: int) -> int:
	var count: int = 0
	for entry: Entry in entries:
		if entry.state == State.SERVING and entry.team_id == team_id:
			count += 1
	return count


func _promote_queued(max_serving: int) -> void:
	for entry: Entry in entries:
		if entry.state == State.QUEUED and _serving_count(entry.team_id) < max_serving:
			entry.state = State.SERVING
