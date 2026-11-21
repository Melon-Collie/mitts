extends "res://tools/own_goal_hunt_runner.gd"

# The work behind tools/own_goal_stage.gd: in an all-bot match, a loose puck is
# staged again and again behind and beside one team's net, with that team's
# defenseman coming to it from a spot round the zone (in 3v3, one of its bots),
# its goalie set in his crease, and either nobody near or a forechecker coming
# from the slot. Every trial runs until a goal, a whistle, the puck leaving the
# net's surroundings or the trial's time, and an own goal prints its trace.

const TRIAL_S: float = 6.0
# The puck is out of trouble once it is this far from the net.
const CLEARED_M: float = 12.0
# The puck behind and beside the net: across from the middle, and behind the
# goal line (the end boards are 3.35 m back).
const PUCK_X: Array[float] = [1.3, 1.8, 2.5]
const PUCK_BEHIND: Array[float] = [0.2, 0.8, 1.5]
# Where the defenseman comes from (across the ice on the puck's side, metres
# out from the goal line; negative is behind it) and his speed at the puck.
const D_STARTS: Array[Vector2] = [Vector2(0.0, 6.0), Vector2(1.0, 2.5),
		Vector2(5.0, 3.0), Vector2(-3.0, -1.5)]
const D_SPEEDS: Array[float] = [0.0, 5.0]
# The forechecker, when there is one: the top of the slot, coming at the puck.
const FORECHECK_FROM := Vector2(-1.0, 8.0)
const FORECHECK_SPEED: float = 4.0

# A staged puck moving faster than this a tick later did not stay staged.
const STAGED_REST_M_S: float = 0.1

var _team_size: int = 5
var _trial_own_goal: bool = false
var _trial_goal_against: bool = false


# `only`: run just the trials whose label contains it ("" for all).
func begin_staged(team_size: int, sides: Array[float], only: String = "") -> void:
	_team_size = team_size
	_ring.resize(_RING_TICKS)
	_ring.fill("")
	await _start_match(team_size)
	GameManager.goal_scored.connect(_on_goal)
	process_physics_priority = 1_000_000_000
	var tally: Dictionary = {}
	var carried: int = 0
	var first_touch: Dictionary = {}
	var trials: int = 0
	var index: int = -1
	var failures: Array[String] = []
	for side: float in sides:
		for px: float in PUCK_X:
			for behind: float in PUCK_BEHIND:
				for start: Vector2 in D_STARTS:
					for speed: float in D_SPEEDS:
						for pressure: bool in [false, true]:
							# Each pair, alone and forechecked, at one team's net, the
							# next pair at the other's.
							index += 1
							var defending: int = (index / 2) % 2
							var label: String = "team %d puck (%.1f, %.1f behind) D from (%.1f, %.1f) at %.0f m/s %s" % [
									defending, side * px, behind, side * start.x, start.y, speed,
									"forechecked" if pressure else "alone"]
							if only != "" and not label.contains(only):
								continue
							await _wait_for_live_play()
							var d_peer: int = _stage(defending, side, px, behind, start, speed, pressure)
							if d_peer == -1:
								print("[own-goal-stage] no defenseman for team %d" % defending)
								continue
							var r: Array = await _watch(defending, d_peer)
							trials += 1
							tally[r[0]] = int(tally.get(r[0], 0)) + 1
							if r[1]:
								carried += 1
							first_touch[r[2]] = int(first_touch.get(r[2], 0)) + 1
							if r[0] == "own_goal":
								failures.append(label)
							print("[own-goal-stage] %s -> %s, first touch %s%s" % [label, r[0],
									r[2], ", D carried it" if r[1] else ""])
	print("[own-goal-stage] SUMMARY %s" % JSON.stringify({
		"team_size": team_size, "trials": trials, "outcomes": tally,
		"defenseman_carried_it": carried, "first_touch": first_touch,
		"own_goals": failures}))
	get_tree().quit()


func _on_goal(scoring_team: Team, scorer: String, a1: String, a2: String) -> void:
	var own_before: int = _own_goals
	super._on_goal(scoring_team, scorer, a1, a2)
	if _own_goals > own_before:
		_trial_own_goal = true
	else:
		_trial_goal_against = true


func _wait_for_live_play() -> void:
	var settled: int = 0
	while settled < 30:
		await get_tree().physics_frame
		var puck: Puck = GameManager.puck
		var live: bool = puck != null and not GameManager.is_movement_locked() \
				and not puck.pickup_locked
		settled = settled + 1 if live else 0


# Stages one trial; returns the defenseman's peer id, or -1 without one.
func _stage(defending: int, side: float, px: float, behind: float, start: Vector2,
		speed: float, pressure: bool) -> int:
	var reg: PlayerRegistry = GameManager.get("_registry")
	var own: float = 1.0 if defending == 0 else -1.0
	var puck_at: Vector3 = _at(own, side * px, -behind)
	var d_peer: int = -1
	var mates: Array[PlayerRecord] = []
	var opps: Array[PlayerRecord] = []
	for rec: PlayerRecord in reg.all().values():
		if rec.skater == null or rec.controller == null or rec.team == null:
			continue
		if rec.team.team_id == defending:
			if d_peer == -1 and (_team_size < 5 or PlayerRules.is_defense_slot(rec.team_slot)):
				d_peer = rec.peer_id
			else:
				mates.append(rec)
		else:
			opps.append(rec)
	if d_peer == -1:
		return -1
	_trial_own_goal = false
	_trial_goal_against = false
	# Through the puck's controller, which restarts its swept contact tests where
	# the puck lands: parked with Puck.stage_at alone, the next tick sweeps the
	# whole jump and every blade along it plays the puck.
	GameManager.puck_controller.stage_scripted(
			Vector3(puck_at.x, GameManager.puck.ice_height, puck_at.z))
	for gc: GoalieController in GameManager.goalie_controllers:
		gc.reset_to_crease()
	_place(reg.get_record(d_peer), _at(own, side * start.x, start.y), puck_at, speed)
	for i: int in mates.size():
		_place(mates[i], _at(own, _spread(i, mates.size()), 19.0), puck_at, 0.0)
	for i: int in opps.size():
		if pressure and i == 0:
			_place(opps[i], _at(own, side * FORECHECK_FROM.x, FORECHECK_FROM.y), puck_at,
					FORECHECK_SPEED)
		else:
			_place(opps[i], Vector3(_spread(i, opps.size()), 0.0, 0.0), puck_at, 0.0)
	return d_peer


# The `i`th of `n` bodies across the ice, 4 m apart about the middle.
static func _spread(i: int, n: int) -> float:
	return (float(i) - 0.5 * float(n - 1)) * 4.0


# A spot `out` metres out from the goal line `own` defends (negative behind it).
static func _at(own: float, x: float, out: float) -> Vector3:
	return Vector3(x, 0.0, own * (GameRules.GOAL_LINE_Z - out))


static func _place(rec: PlayerRecord, at: Vector3, toward: Vector3, speed: float) -> void:
	var dir := Vector3(toward.x - at.x, 0.0, toward.z - at.z).normalized()
	rec.controller.teleport_to(at, Vector2(dir.x, dir.z))
	rec.skater.velocity = dir * speed


# [outcome, whether the defenseman carried the puck, who touched it first:
# "D", "mate", "opponent", or "nobody" (the keepers alone played it)].
func _watch(defending: int, d_peer: int) -> Array:
	var reg: PlayerRegistry = GameManager.get("_registry")
	var tracker: ShotOnGoalTracker = GameManager.get("_shot_tracker")
	var net := Vector3(0.0, 0.0, (1.0 if defending == 0 else -1.0) * GameRules.GOAL_LINE_Z)
	var played: bool = false
	var first: String = "nobody"
	var staged_toucher: int = tracker.get_last_toucher() if tracker != null else -1
	for i: int in int(TRIAL_S * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		var carrier: Skater = GameManager.get_puck_carrier()
		# Nobody is set within a tick of the puck, so one played already was
		# played by the staging.
		if i == 0 and (carrier != null
				or GameManager.puck.linear_velocity.length() > STAGED_REST_M_S):
			return ["staging_fault", false, "nobody"]
		if carrier != null and reg.resolve_peer_id(carrier) == d_peer:
			played = true
		var toucher: int = tracker.get_last_toucher() if tracker != null else -1
		if first == "nobody" and (toucher != staged_toucher or carrier != null):
			var who: int = reg.resolve_peer_id(carrier) if carrier != null else toucher
			if who == d_peer:
				first = "D"
			elif who != -1:
				first = "mate" if reg.resolve_team_id_for_peer(who) == defending else "opponent"
		if _trial_own_goal:
			return ["own_goal", played, first]
		if _trial_goal_against:
			return ["goal_against", played, first]
		if GameManager.is_movement_locked():
			return ["whistle", played, first]
		var p: Vector3 = GameManager.puck.global_position
		if Vector2(p.x - net.x, p.z - net.z).length() > CLEARED_M:
			return ["cleared", played, first]
	return ["timeout", played, first]
