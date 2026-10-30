extends GutTest

# Whether a slow loose puck at his feet ever ends up in his own net through
# something he does. The live keeper (KeeperController on the Goalie node) and
# the real puck's own tick (Puck._host_tick: the frame, the posts and his
# gear's boxes moving as he moves), stepped as the game steps them: him, then
# the puck, then its contact events. He is set on a puck in each of four
# places (square out front, at an angle, at a sharp angle on the near post,
# below the goal line in the RVH), and the puck is laid loose at a spot around
# him (in front,
# beside, between his legs, behind him) moving slowly, every way; then whatever
# he does plays out for a few seconds: covers it, skates, goes down, and, with
# no whistle here, sets a covered puck down and sweeps it out (the Off rules).
#
# Per speed, how each trial ended: covered (held, then played out), gone (out
# of his reach), still (at rest near him), and in: untouched (it slid in past
# him on its own) or off him (something he did), with what last touched it and
# what he was doing. Prints every goal off him.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const GOAL_SCENE: PackedScene = preload("res://Scenes/Goalie.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SECONDS: float = 4.0
# Across his line, and in front of (−) and behind (+) him toward his net, from
# where he stands.
const ACROSS: Array[float] = [-0.9, -0.6, -0.3, 0.0, 0.3, 0.6, 0.9]
const DEPTH: Array[float] = [-0.8, -0.5, -0.25, 0.0, 0.25, 0.5]
const SPEEDS: Array[float] = [0.0, 0.6, 1.5, 2.5]
const HEADINGS: int = 8
# Where the puck he is set on lies, net frame: out front, at an angle, at a
# sharp angle (the near post), below the goal line (the RVH).
const SET_ON: Array = [["square", Vector2(0.0, -6.0)], ["angle", Vector2(-4.0, -4.0)],
		["post", Vector2(-3.0, -1.2)], ["rvh", Vector2(2.4, 0.6)]]

var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null
var _touched: String = "-"
var _covered: bool = false
var _set_on := Vector2(0.0, -6.0)


func _build() -> void:
	_goalie = GOAL_SCENE.instantiate() as Goalie
	_puck = PUCK_SCENE.instantiate() as Puck
	_keeper = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_keeper)
	_puck.set_server_mode(true)
	_puck.set_goalie_provider(func() -> Array: return [_goalie])
	_keeper.setup(_goalie, _puck, GameRules.GOAL_LINE_Z, true)
	_puck.puck_touched_goalie.connect(func(_g: Goalie) -> void:
			var part: Node = _puck._goalie_contact.part
			_touched = String(part.name) if part != null else "goalie")
	_keeper.puck_covered.connect(func(_team: int) -> void: _covered = true)


# From the net's frame (x across, z back into the net) into the rink.
func _rink(v: Vector3) -> Vector3:
	return _keeper._net * v


func test_report() -> void:
	_build()
	var lines: PackedStringArray = ["set on  speed | in off him / in untouched / covered / gone / still"]
	var goals: PackedStringArray = []
	for set_on: Array in SET_ON:
		_set_on = set_on[1]
		_report_set(set_on[0], lines, goals)
	gut.p("\n" + "\n".join(lines) + "\nGOALS OFF HIM\n" + "\n".join(goals))
	assert_true(true)


func _report_set(where: String, lines: PackedStringArray, goals: PackedStringArray) -> void:
	for speed: float in SPEEDS:
		var tally: Dictionary = {"in": 0, "untouched": 0, "covered": 0, "gone": 0, "still": 0}
		var headings: int = 1 if speed == 0.0 else HEADINGS
		for across: float in ACROSS:
			for depth: float in DEPTH:
				for h: int in headings:
					var heading: float = TAU * h / HEADINGS
					var outcome: String = _trial(across, depth, speed, heading)
					var kind: String = outcome.get_slice(" ", 0)
					tally[kind] = int(tally[kind]) + 1
					if kind == "in":
						goals.append("  %s %.1f m/s heading %3.0f° from (%+.2f across, %+.2f deep): %s" % [where,
								speed, rad_to_deg(heading), across, depth, outcome])
		lines.append("%-7s %4.1f  | %d / %d / %d / %d / %d" % [where, speed, tally["in"], tally["untouched"],
				tally["covered"], tally["gone"], tally["still"]])


# One trial: the puck laid at (across, depth) from him in the net's frame at
# `speed` along `heading` (0 straight at his net), then played out.
func _trial(across: float, depth: float, speed: float, heading: float) -> String:
	_settle()
	var me := Vector2(_keeper.motor.x, _keeper.motor.z)
	var at := Vector3(me.x + across, GameRules.PUCK_COLLISION_HALF_HEIGHT, me.y + depth)
	if at.z >= -GameRules.PUCK_COLLISION_RADIUS:
		return "still (behind the line)"
	var v := Vector3(sin(heading), 0.0, cos(heading)) * speed
	_puck.clear_carrier()
	_puck.motion_pinned = false
	_puck.pickup_locked = false
	_puck.global_position = _rink(at)
	_puck.set_puck_velocity(_keeper._net.basis * v)
	_touched = "-"
	_covered = false
	var t: float = 0.0
	while t < SECONDS:
		_keeper._physics_process(DT)
		var before: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		_puck._physics_process(DT)
		_puck.drain_contact_events()
		t += DT
		var p: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		if p.z >= 0.0 and before.z < 0.0 and absf(p.x) < GameRules.NET_HALF_WIDTH \
				and p.y < GameRules.NET_HEIGHT:
			if _touched == "-" and not _covered:
				return "untouched"
			return "in at %.2f s, x %+.2f, last touched %s, covered first %s, he was %s, rest %d" % [t, p.x,
					_touched, _covered, KeeperMotor.Mover.keys()[_keeper.motor._mover], _keeper.motor.rest]
		if Vector2(p.x - me.x, p.z - me.y).length() > 3.0:
			return "covered" if _covered else "gone"
	if _covered:
		return "covered"
	return "still"


# Set on a puck lying at `_set_on`, from a full reset.
func _settle() -> void:
	_keeper.reset_to_crease()
	_puck.clear_carrier()
	_puck.motion_pinned = false
	_puck.pickup_locked = false
	var out: Vector3 = _rink(Vector3(_set_on.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, _set_on.y))
	for _i: int in 180:
		_puck.global_position = out
		_puck.set_puck_velocity(Vector3.ZERO)
		_keeper._physics_process(DT)


# One trial, tick by tick: in the RVH, a puck lying still a quarter metre in
# front of him.
func test_trace_rvh_dead_puck() -> void:
	_build()
	_set_on = SET_ON[3][1]
	_settle()
	var me := Vector2(_keeper.motor.x, _keeper.motor.z)
	var at := Vector3(me.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, me.y - 0.25)
	_puck.clear_carrier()
	_puck.global_position = _rink(at)
	_puck.set_puck_velocity(Vector3.ZERO)
	var lines: PackedStringArray = ["him at %s yaw %.2f rest %d" % [me, _keeper.motor.yaw, _keeper.motor.rest]]
	for i: int in 40:
		_keeper._physics_process(DT)
		_puck._physics_process(DT)
		_puck.drain_contact_events()
		var p: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		var v: Vector3 = _keeper._net.basis.inverse() * _puck.get_puck_velocity()
		lines.append("t %.3f him (%+.2f,%+.2f) yaw %+.2f rest %d mover %-8s goal (%+.2f,%+.2f) r%d cover %s | puck (%+.2f,%+.2f) v (%+.2f,%+.2f) %s" % [
				(i + 1) * DT, _keeper.motor.x, _keeper.motor.z, _keeper.motor.yaw, _keeper.motor.rest,
				KeeperMotor.Mover.keys()[_keeper.motor._mover], _keeper.motor.route.spot.x, _keeper.motor.route.spot.y,
				_keeper.motor.route.rest, _keeper._covering, p.x, p.z, v.x, v.z, _touched])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)
