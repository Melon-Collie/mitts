class_name AIDefencePairing
extends RefCounted

# Who of a defence is on which attacker, for a possession read
# (AIPossessionValue): the puck's holder is always covered while there is a
# defender, the others only level with or ahead of the puck, and a man covered
# rides his man, a stick goal-side of him. Reads only the leaves.

# pair()'s column for the puck's holder.
const HOLDER: int = -2

# ride_at's other result: the riding defender's velocity.
static var ride_vel: Vector3 = Vector3.ZERO

# The side's skaters other than the holder, index-matched velocities, and per
# paired defender the attacker index he rides, or -1.
var attackers: Array[Vector3] = []
var attacker_vels: Array[Vector3] = []
var ride: Array[int] = []
# Where the puck's holder is (INF: nobody holds it).
var holder: Vector3 = Vector3.INF
var _goal: Vector3 = Vector3.ZERO
var _defenders: Array[Vector3] = []
var _defender_vels: Array[Vector3] = []
var _defender_caps: Array = []
# pair()'s scratch: its columns (attacker index, HOLDER for the holder), each
# column's cover time per defender, and the search's best and current picks.
var _pair_cols: Array[int] = []
var _pair_rows: Array[int] = []
var _pair_cost: Array[float] = []
var _pair_pick: Array[int] = []
var _pair_best: Array[int] = []
var _pair_used: Array[bool] = []
var _pair_best_cost: float = INF


# The skaters of `attack_team` a read pairs its defence to (fill's `attackers`,
# velocities into `out_vels`): all of them but the puck's holder — the team's
# carrier, else its skater nearest the puck — whose spot is returned (INF when
# the team has nobody on the ice).
static func collect_attack(snapshot: WorldSnapshot, team_id_by_peer: Dictionary,
		attack_team: int, out_pos: Array[Vector3], out_vels: Array[Vector3]) -> Vector3:
	out_pos.clear()
	out_vels.clear()
	if snapshot == null:
		return Vector3.INF
	var holder_pid: int = -1
	var puck: Vector3 = Vector3.INF
	if snapshot.puck_state != null:
		puck = snapshot.puck_state.position
		var c: int = snapshot.puck_state.carrier_peer_id
		if c != -1 and team_id_by_peer.get(c, -1) == attack_team:
			holder_pid = c
	if holder_pid == -1 and puck.is_finite():
		var best_d: float = INF
		for pid: int in snapshot.skater_states:
			if team_id_by_peer.get(pid, -1) != attack_team:
				continue
			var d: float = snapshot.skater_states[pid].position.distance_squared_to(puck)
			if d < best_d or (d == best_d and pid < holder_pid):
				best_d = d
				holder_pid = pid
	var holder_pos: Vector3 = Vector3.INF
	for pid: int in snapshot.skater_states:
		if team_id_by_peer.get(pid, -1) != attack_team:
			continue
		var st: SkaterNetworkState = snapshot.skater_states[pid]
		if pid == holder_pid:
			holder_pos = st.position
			continue
		out_pos.append(st.position)
		out_vels.append(st.velocity)
	return holder_pos


# Pairs each of `defenders` (velocities and caps index-matched) with the attacker
# he gets goal-side of soonest (_cover_point, on his own build's arrival clock),
# into `ride`; `p_attackers` are the side's skaters other than the holder, at
# `p_holder` (INF: nobody holds the puck). The arrays are read, not copied. The
# holder is always covered while there is a defender; the others count only level
# with or ahead of the puck (all of them with nobody holding it). The pairing covers as many men as there are defenders,
# at the least total time; ties go to the earlier column and row in (x, z) order,
# which no peer's registration moves.
func pair(goal: Vector3, defenders: Array[Vector3], defender_vels: Array[Vector3],
		defender_caps: Array, pattackers: Array[Vector3], pattacker_vels: Array[Vector3],
		p_holder: Vector3) -> void:
	holder = p_holder
	_goal = goal
	_defenders = defenders
	_defender_vels = defender_vels
	_defender_caps = defender_caps
	attackers = pattackers
	attacker_vels = pattacker_vels
	ride.resize(_defenders.size())
	ride.fill(-1)
	if _defenders.is_empty() or attackers.is_empty():
		return
	_pair_cols.clear()
	if holder.is_finite():
		_pair_cols.append(HOLDER)
	var sign_z: float = signf(_goal.z)
	for j: int in attackers.size():
		if not holder.is_finite() or (attackers[j].z - holder.z) * sign_z >= 0.0:
			_pair_cols.append(j)
	if _pair_cols.size() == (1 if holder.is_finite() else 0):
		return
	_sort_by_place(_pair_cols)
	_pair_rows.clear()
	for k: int in _defenders.size():
		_pair_rows.append(k)
	_sort_by_place(_pair_rows, true)
	var n_rows: int = _pair_rows.size()
	_pair_cost.resize(_pair_cols.size() * n_rows)
	for c: int in _pair_cols.size():
		var man: Vector3 = holder if _pair_cols[c] == HOLDER else attackers[_pair_cols[c]]
		var cover: Vector3 = _cover_point(man)
		for r: int in n_rows:
			var k: int = _pair_rows[r]
			_pair_cost[c * n_rows + r] = AIArrival.time_to_arrive_caps(_defenders[k], cover,
					_defender_vels[k], _caps_of(k))
	_pair_pick.resize(_pair_cols.size())
	_pair_best.resize(_pair_cols.size())
	_pair_used.resize(n_rows)
	_pair_used.fill(false)
	_pair_best_cost = INF
	_pair_search(0, maxi(0, _pair_cols.size() - n_rows), 0.0)
	for c: int in _pair_cols.size():
		if _pair_cols[c] != HOLDER and _pair_best[c] != -1:
			ride[_pair_rows[_pair_best[c]]] = _pair_cols[c]


# Column `c` on: row picks for the columns left, with `skips` columns still
# allowed to go uncovered (the holder never), at `cost` so far.
func _pair_search(c: int, skips: int, cost: float) -> void:
	if cost >= _pair_best_cost:
		return
	if c == _pair_cols.size():
		_pair_best_cost = cost
		_pair_best.assign(_pair_pick)
		return
	var n_rows: int = _pair_rows.size()
	for r: int in n_rows:
		if _pair_used[r]:
			continue
		_pair_used[r] = true
		_pair_pick[c] = r
		_pair_search(c + 1, skips, cost + _pair_cost[c * n_rows + r])
		_pair_used[r] = false
	if skips > 0 and _pair_cols[c] != HOLDER:
		_pair_pick[c] = -1
		_pair_search(c + 1, skips - 1, cost)


# Orders `idx` (attacker indices and HOLDER, or defender indices) by place, x
# then z.
func _sort_by_place(idx: Array[int], defenders: bool = false) -> void:
	for a: int in range(1, idx.size()):
		var key: int = idx[a]
		var kp: Vector3 = _place_of(key, defenders)
		var b: int = a - 1
		while b >= 0:
			var bp: Vector3 = _place_of(idx[b], defenders)
			if bp.x < kp.x or (bp.x == kp.x and bp.z <= kp.z):
				break
			idx[b + 1] = idx[b]
			b -= 1
		idx[b + 1] = key


func _place_of(i: int, defenders: bool) -> Vector3:
	if defenders:
		return _defenders[i]
	return holder if i == HOLDER else attackers[i]


# Goal-side of a man at `man`: a stick off him on his line to the net.
func _cover_point(man: Vector3) -> Vector3:
	var to_net := Vector3(_goal.x - man.x, 0.0, _goal.z - man.z)
	var d: float = to_net.length()
	if d < AIBotMechanics.BLADE_REACH_M:
		return Vector3(_goal.x, 0.0, _goal.z)
	return man + to_net * (AIBotMechanics.BLADE_REACH_M / d)


# True when defender `k` rides a man (an index past the paired defence — a body
# pushed onto a read later — plays the puck).
func rides(k: int) -> bool:
	return k < ride.size() and ride[k] != -1


# Defender `k`, riding his man, `t` from now: on the man's cover point as the man
# carries on, once his skate gets him there, part way along until then. His
# velocity then is left in ride_vel.
func ride_at(k: int, t: float) -> Vector3:
	if t <= 0.0:
		ride_vel = _defender_vels[k]
		return _defenders[k]
	var j: int = ride[k]
	var man: Vector3 = AITrajectory.predict_at(attackers[j], attacker_vels[j], t)
	var cover: Vector3 = _cover_point(man)
	var p: Vector3 = _defenders[k]
	var t_cover: float = AIArrival.time_to_arrive_caps(p, cover, _defender_vels[k], _caps_of(k))
	if t_cover <= t:
		ride_vel = attacker_vels[j]
		return cover
	ride_vel = (cover - p) / t_cover
	return p.lerp(cover, t / t_cover)


func _caps_of(k: int) -> AISkaterCaps:
	return _defender_caps[k] if _defender_caps.size() == _defenders.size() else null
