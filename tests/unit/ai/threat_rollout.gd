extends RefCounted

# One possession played on from a staged state, for the threat truth table
# (docs/xt-plan.md, Step 1). The duel harness's real bots play it, with the live
# keeper in each net, until somebody scores, a keeper holds the puck, or the
# horizon runs out. No class_name (test infra stays out of the global namespace).
#
# The harness's puck is flat and its keepers are positions in the snapshot. A
# shot in flight, and a loose puck near either net, are marched here instead: in
# three dimensions, through the frame step, against the keeper's gear
# (GoalieSaveRules.resolve_contact), as real_goalie_shot_harness.gd's
# fire_tracking_rebound does. While it is marched here the harness still sees it
# and its sticks still play it; once a stick has it, or it is a loose puck away
# from both nets, the harness carries it again.
#
# Team 0 attacks -Z. A rollout's value is +e^(−t/τ) for a goal by team 0 at t,
# −e^(−t/τ) for one by team 1, and 0 for a held puck or the horizon.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const RADIUS: float = GameRules.PUCK_COLLISION_RADIUS
# A loose puck this near a net's centre is marched against its keeper: inside
# it a puck can reach his gear or his goal line before a pass of the harness's
# flat integration could notice.
const NEAR_NET_M: float = 4.0
# On the ice: no higher off it than a stick plays; and slow enough there to be
# a stick's to play rather than still a shot.
const ON_ICE_M: float = 0.12
const PLAYABLE_M_S: float = 8.0
# Ticks the keepers are given on the staged puck before play starts: set on it.
const SETTLE_TICKS: int = 120

enum End { HORIZON, GOAL, HELD }


class Result:
	var value: float = 0.0
	var end: int = End.HORIZON
	var t: float = 0.0
	var scorer_team: int = -1
	var shots: PackedInt32Array = PackedInt32Array([0, 0])


# One net: its keeper, the puck node he reads, and a stand-in carrier he sees
# holding it.
class Net:
	var goalie: Goalie
	var puck: Puck
	var ctrl: KeeperController
	var proxy: Skater
	var proxy_team: int = 0
	var goal_z: float
	var team: int
	var part_origins := PackedVector3Array()
	var part_vels := PackedVector3Array()


var nets: Array[Net] = []

var _managed: bool = false
var _flight: bool = false
var _touched: bool = false
var _net: Net = null
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _frame := PuckGeometryCollision.Result.new()
var _step := PuckAuthorityRules.TickResult.new()
var _scratch := SweptDiscOBB.Result.new()
var _contact := GoalieContactDetector.Contact.new()
var _save := GoalieSaveRules.ContactResult.new()


# Builds a keeper for each net under `host` (a test node that frees them).
func _init(host: Node) -> void:
	for team: int in [1, 0]:
		var n := Net.new()
		n.team = team
		n.goal_z = (-1.0 if team == 1 else 1.0) * GameRules.GOAL_LINE_Z
		n.goalie = load("res://Scenes/Goalie.tscn").instantiate() as Goalie
		n.puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
		n.proxy = load("res://Scenes/Skater.tscn").instantiate() as Skater
		n.ctrl = KeeperController.new()
		for node: Node in [n.goalie, n.puck, n.proxy, n.ctrl]:
			host.add_child(node)
		n.proxy.set_physics_process(false)
		n.proxy.set_process(false)
		n.puck.set_physics_process(false)
		var net: Net = n
		n.proxy.set_team_id_resolver(func() -> int: return net.proxy_team)
		n.ctrl.team_id = team
		n.ctrl.set_skater_getter(func() -> Array: return [])
		n.ctrl.setup(n.goalie, n.puck, n.goal_z, true)
		nets.append(n)


# The net team `team` defends.
func net_of(team: int) -> Net:
	return nets[0] if team == 1 else nets[1]


# Plays `duel` (built and started, carrier given) for up to `horizon_s`,
# discounting by `tau_s`.
func run(duel: RefCounted, horizon_s: float, tau_s: float) -> Result:
	var out := Result.new()
	_begin(duel)
	var t: float = 0.0
	while t < horizon_s:
		var end: int = _tick(duel, out.shots)
		t += DT
		if end == End.HORIZON:
			continue
		out.end = end
		out.t = t
		if end == End.GOAL:
			out.scorer_team = 1 - _net.team
			out.value = (1.0 if out.scorer_team == 0 else -1.0) * exp(-t / tau_s)
		return out
	out.t = t
	return out


# How a macro event ended (docs/xt-plan.md §3.2).
enum Macro { MOVED, TURNED_OVER, GOAL, HELD, TIMED_OUT }


class MacroResult:
	var end: int = Macro.TIMED_OUT
	var t: float = 0.0
	var scorer_team: int = -1
	# Who has the puck at the end, where, and every skater then (peer → pos).
	var team: int = -1
	var puck := Vector3.ZERO
	var positions: Dictionary = {}


# Plays `duel` to its next macro event for team 0's possession: a pass of ours
# caught, our carrier still on it `move_s` on, their pickup, a goal, or a held
# puck; a shot plays on through its rebound to whoever settles it. Gives up at
# `cap_s`.
func run_macro(duel: RefCounted, move_s: float, cap_s: float) -> MacroResult:
	var out := MacroResult.new()
	var shots := PackedInt32Array([0, 0])
	_begin(duel)
	var t: float = 0.0
	var holder: int = duel.carrier_id
	while t < cap_s:
		var end: int = _tick(duel, shots)
		t += DT
		out.t = t
		if end == End.GOAL:
			out.end = Macro.GOAL
			out.scorer_team = 1 - _net.team
			return out
		if end == End.HELD:
			out.end = Macro.HELD
			return out
		var c: int = duel.carrier_id
		if c == -1:
			continue
		var team: int = duel.team_map[c]
		var caught: bool = c != holder and holder != -1 and team == 0 \
				and duel.team_map[holder] == 0
		holder = c
		if team == 1:
			out.end = Macro.TURNED_OVER
		elif caught or t >= move_s or shots[0] + shots[1] > 0:
			out.end = Macro.MOVED
		else:
			continue
		out.team = team
		out.puck = duel.puck_pos
		for p: int in duel.team_map:
			out.positions[p] = duel.skater_pos(p)
		return out
	return out


func _begin(duel: RefCounted) -> void:
	_managed = false
	_flight = false
	_net = null
	for n: Net in nets:
		n.puck.pickup_locked = false
		n.puck.motion_pinned = false
		n.ctrl.reset_to_crease()
	duel.goalie_provider = func(team_id: int, _puck_pos: Vector3) -> Variant:
		return net_of(team_id).goalie.global_position
	for _i: int in SETTLE_TICKS:
		_feed_keepers(duel)


# One tick of play: the harness, the release it fired, who marches the puck,
# the keepers, and the marched puck. Returns End.GOAL, End.HELD, or End.HORIZON
# to play on; `shots` counts each side's shots.
func _tick(duel: RefCounted, shots: PackedInt32Array) -> int:
	var before: int = duel.releases.size()
	if _managed:
		_hand_to_harness(duel)
	duel.step()
	var shot_team: int = -1
	if duel.releases.size() > before:
		var rec: Dictionary = duel.releases[-1]
		var d: String = rec.get("decision", "")
		if d == "SHOOT" or d == "ONE_TIMER":
			shot_team = rec["team"]
	if shot_team >= 0:
		shots[shot_team] += 1
		_start_flight(duel, net_of(1 - shot_team))
	elif duel.carrier_id != -1:
		_managed = false
		_flight = false
	elif not _managed:
		var near: Net = _near_net(duel.puck_pos)
		if near != null:
			_start_managed(duel, near)
	_feed_keepers(duel)
	if not _managed:
		return End.HORIZON
	return _march(duel)


func _near_net(p: Vector3) -> Net:
	for n: Net in nets:
		if Vector2(p.x, p.z - n.goal_z).length() <= NEAR_NET_M:
			return n
	return null


func _start_flight(duel: RefCounted, n: Net) -> void:
	_net = n
	_managed = true
	_flight = true
	_touched = false
	_pos = Vector3(duel.puck_pos.x, n.puck.ice_height, duel.puck_pos.z)
	_vel = duel.last_launch_velocity
	n.puck.clear_carrier()
	n.puck.global_position = _pos
	n.puck.apply_release_velocity(_vel)
	n.puck.puck_released.emit()


func _start_managed(duel: RefCounted, n: Net) -> void:
	_net = n
	_managed = true
	_flight = false
	_touched = false
	_pos = Vector3(duel.puck_pos.x, n.puck.ice_height, duel.puck_pos.z)
	_vel = Vector3(duel.puck_vel.x, 0.0, duel.puck_vel.z)


# The marched puck, as the harness's flat one: in the air no stick plays it.
func _hand_to_harness(duel: RefCounted) -> void:
	duel.puck_pos = Vector3(_pos.x, 0.0, _pos.z)
	duel.puck_vel = Vector3(_vel.x, 0.0, _vel.z)
	duel.airborne_ticks = 1 if _pos.y > GameRules.PUCK_AIRBORNE_HEIGHT_M else 0


# Each keeper's puck node as he should see it, and his tick. The net the marched
# puck is in sees it in three dimensions; the other sees the harness's.
func _feed_keepers(duel: RefCounted) -> void:
	for n: Net in nets:
		if _managed and n == _net:
			n.puck.clear_carrier()
			n.puck.global_position = _pos
			n.puck.linear_velocity = _vel
		else:
			var held: bool = duel.carrier_id != -1
			if held:
				n.proxy_team = duel.team_map[duel.carrier_id]
				n.proxy.global_position = duel.skater_pos(duel.carrier_id)
				if n.puck.get_carrier() != n.proxy:
					n.puck.set_carrier(n.proxy)
			elif n.puck.get_carrier() != null:
				n.puck.clear_carrier()
			n.puck.global_position = Vector3(duel.puck_pos.x, n.puck.ice_height, duel.puck_pos.z)
			n.puck.linear_velocity = Vector3(duel.puck_vel.x, 0.0, duel.puck_vel.z)
		_tick_keeper(n)


func _tick_keeper(n: Net) -> void:
	var parts: Array[CollisionShape3D] = n.goalie.get_collision_parts()
	n.part_origins.resize(parts.size())
	for i: int in parts.size():
		n.part_origins[i] = parts[i].global_transform.origin
	n.ctrl._physics_process(DT)
	n.part_vels.resize(parts.size())
	for i: int in parts.size():
		n.part_vels[i] = (parts[i].global_transform.origin - n.part_origins[i]) / DT


# One tick of the marched puck after its keeper's: what he did to it, the frame
# step, his gear, his goal line. Returns End.GOAL, End.HELD, or End.HORIZON to
# play on.
func _march(duel: RefCounted) -> int:
	var n: Net = _net
	if n.puck.motion_pinned:
		return End.HELD
	if n.puck.linear_velocity.distance_to(_vel) > 0.01:
		_vel = n.puck.linear_velocity
	var prev: Vector3 = _pos
	_step.touched_post = false
	_step.touched_net = false
	PuckAuthorityRules.step_frame_substep(_pos, _vel, DT, RADIUS, n.puck.max_speed,
			n.puck.ice_height, n.puck.max_height, _frame, _step)
	_pos = _step.position
	_vel = _step.velocity
	if GoalieContactDetector.nearest([n.goalie], prev, _pos, RADIUS, _scratch, _contact):
		_touched = true
		_flight = false
		var fwd: Vector3 = -n.goalie.global_transform.basis.z
		GoalieSaveRules.resolve_contact(_vel, _classify(_contact.part as Node3D),
				_contact.normal, _save, fwd, _struck_part_velocity(n))
		if _save.caught:
			return End.HELD
		_vel = _save.velocity
		if _save.trapped:
			_pos = Vector3(_contact.point.x, n.puck.ice_height, _contact.point.z)
		else:
			_pos = _contact.point + _contact.normal * _contact.depth
	elif _crossed_in(prev, _pos, n):
		return End.GOAL
	elif (_pos.z - n.goal_z) * signf(n.goal_z) >= 0.0 and _flight:
		# Wide or over: the flight is over, the puck plays on behind the line.
		_flight = false
	var on_ice: bool = _pos.y <= ON_ICE_M
	if _flight and on_ice and Vector2(_vel.x, _vel.z).length() < PLAYABLE_M_S:
		# A shot that died on the ice short of him: a loose puck like any other.
		_flight = false
	if not _flight and on_ice and _near_net(_pos) == null:
		_managed = false
	_hand_to_harness(duel)
	return End.HORIZON


func _crossed_in(prev: Vector3, pos: Vector3, n: Net) -> bool:
	var facing: float = signf(n.goal_z)
	return GoalDetectionRules.crossed_into_net(prev, pos, n.goal_z, facing,
			GameRules.NET_HALF_WIDTH, GameRules.NET_HEIGHT, GameRules.NET_POST_RADIUS,
			RADIUS, GameRules.PUCK_COLLISION_HALF_HEIGHT, GameRules.NET_DEPTH)


static func _classify(part_body: Node3D) -> int:
	if part_body == null:
		return GoalieSaveRules.SavePart.PAD
	match part_body.name:
		"Glove":
			return GoalieSaveRules.SavePart.GLOVE
		"Body":
			return GoalieSaveRules.SavePart.CHEST
		"Head":
			return GoalieSaveRules.SavePart.MASK
		"Blocker":
			return GoalieSaveRules.SavePart.BLOCKER
		"Stick":
			return GoalieSaveRules.SavePart.STICK
	return GoalieSaveRules.SavePart.PAD


# The velocity of the gear part the puck struck: its body's shape nearest the
# contact, over his last tick.
func _struck_part_velocity(n: Net) -> Vector3:
	var parts: Array[CollisionShape3D] = n.goalie.get_collision_parts()
	var bodies: Array[Node] = n.goalie.get_collision_part_bodies()
	var best: int = -1
	var best_d2: float = INF
	for i: int in mini(parts.size(), n.part_vels.size()):
		if bodies[i] != _contact.part:
			continue
		var d2: float = parts[i].global_transform.origin.distance_squared_to(_contact.point)
		if d2 < best_d2:
			best_d2 = d2
			best = i
	return n.part_vels[best] if best >= 0 else Vector3.ZERO
