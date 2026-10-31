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
# of his reach), still at rest at his feet uncovered (KeeperCover.at_feet) or
# near him past them, and in: untouched (it slid in past him on its own) or off
# him (something he did), with what last touched it and what he was doing. A
# spot behind the goal line is not laid. Prints every goal off him, and where
# each puck left lying at his feet lies as he sees it.

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
var _last_status: String = ""


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
	var lines: PackedStringArray = ["set on  speed | in off him / in untouched / covered / gone / still at his feet / still near"]
	var goals: PackedStringArray = []
	var lying: PackedStringArray = []
	for set_on: Array in SET_ON:
		_set_on = set_on[1]
		_report_set(set_on[0], lines, goals, lying)
	gut.p("\n" + "\n".join(lines) + "\nGOALS OFF HIM\n" + "\n".join(goals) + "\nLEFT LYING AT HIS FEET\n"
			+ "\n".join(lying))
	assert_true(true)


func _report_set(where: String, lines: PackedStringArray, goals: PackedStringArray, lying: PackedStringArray) -> void:
	for speed: float in SPEEDS:
		var tally: Dictionary = {"in": 0, "untouched": 0, "covered": 0, "gone": 0, "feet": 0, "near": 0, "skip": 0}
		var headings: int = 1 if speed == 0.0 else HEADINGS
		for across: float in ACROSS:
			for depth: float in DEPTH:
				for h: int in headings:
					var heading: float = TAU * h / HEADINGS
					var outcome: String = _trial(across, depth, speed, heading)
					var kind: String = outcome.get_slice(" ", 0)
					if kind == "still":
						kind = outcome.get_slice(" ", 1)
					if kind == "feet:":
						kind = "feet"
						lying.append("  %s %.1f m/s: %s" % [where, speed, outcome.substr(12)])
					tally[kind] = int(tally[kind]) + 1
					if kind == "in":
						goals.append("  %s %.1f m/s heading %3.0f° from (%+.2f across, %+.2f deep): %s" % [where,
								speed, rad_to_deg(heading), across, depth, outcome])
		lines.append("%-7s %4.1f  | %d / %d / %d / %d / %d / %d" % [where, speed, tally["in"], tally["untouched"],
				tally["covered"], tally["gone"], tally["feet"], tally["near"]])


# One trial: the puck laid at (across, depth) from him in the net's frame at
# `speed` along `heading` (0 straight at his net), then played out.
func _trial(across: float, depth: float, speed: float, heading: float) -> String:
	_settle()
	var me := Vector2(_keeper.motor.x, _keeper.motor.z)
	var at := Vector3(me.x + across, GameRules.PUCK_COLLISION_HALF_HEIGHT, me.y + depth)
	if at.z >= -GameRules.PUCK_COLLISION_RADIUS:
		return "still skip (behind the line)"
	var v := Vector3(sin(heading), 0.0, cos(heading)) * speed
	_puck.clear_carrier()
	_puck.motion_pinned = false
	_puck.pickup_locked = false
	_puck.global_position = _rink(at)
	_puck.set_puck_velocity(_keeper._net.basis * v)
	_touched = "-"
	_covered = false
	_rebase_gear()
	var t: float = 0.0
	while t < SECONDS:
		_keeper._physics_process(DT)
		var before: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		_tick_puck()
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
	var rest: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
	if not KeeperCover.at_feet(rest, Vector3.ZERO, _keeper.motor):
		return "still near"
	var mine: Vector3 = Basis(Vector3.UP, _keeper.motor.yaw).inverse() \
			* (rest - Vector3(_keeper.motor.x, 0.0, _keeper.motor.z))
	return "still feet: %+.2f across, %+.2f ahead of him, rest %d, he was %s, covering %s" % [mine.x, -mine.z,
			_keeper.motor.rest, KeeperMotor.Mover.keys()[_keeper.motor._mover], _keeper._covering]


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
	_rebase_gear()
	var lines: PackedStringArray = ["him at %s yaw %.2f rest %d" % [me, _keeper.motor.yaw, _keeper.motor.rest]]
	for i: int in 120:
		_keeper._physics_process(DT)
		_tick_puck()
		var p: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		var v: Vector3 = _keeper._net.basis.inverse() * _puck.get_puck_velocity()
		lines.append("t %.3f him (%+.2f,%+.2f) yaw %+.2f rest %d mover %-8s goal (%+.2f,%+.2f) r%d cover %s | puck (%+.2f,%+.2f) v (%+.2f,%+.2f) %s" % [
				(i + 1) * DT, _keeper.motor.x, _keeper.motor.z, _keeper.motor.yaw, _keeper.motor.rest,
				KeeperMotor.Mover.keys()[_keeper.motor._mover], _keeper.motor.route.spot.x, _keeper.motor.route.spot.y,
				_keeper.motor.route.rest, _keeper._covering, p.x, p.z, v.x, v.z, _touched])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


const TRACED: Array = [["square", 2.5, 0.0, -0.3, 0.0], ["angle", 1.5, 315.0, 0.0, 0.5],
		["angle", 2.5, 0.0, -0.3, -0.25], ["angle", 2.5, 45.0, 0.0, -0.25], ["post", 2.5, 315.0, 0.0, 0.25],
		["post", 2.5, 270.0, 0.3, -0.25], ["post", 2.5, 270.0, 0.9, 0.25], ["rvh", 1.5, 45.0, -0.6, -0.5],
		["rvh", 2.5, 90.0, -0.3, -0.5]]


func test_trace_the_goals_off_him() -> void:
	_build()
	var lines: PackedStringArray = []
	for c: Array in TRACED:
		for s: Array in SET_ON:
			if s[0] == c[0]:
				_set_on = s[1]
		lines.append("== %s %.1f m/s heading %.0f° from (%+.2f, %+.2f)  without him: %s" % [c[0], c[1], c[2], c[3],
				c[4], _without_him(c)])
		_trace(c, lines)
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _start(c: Array) -> Array:
	var at := Vector3(_keeper.motor.x + float(c[3]), GameRules.PUCK_COLLISION_HALF_HEIGHT, _keeper.motor.z + float(c[4]))
	var h: float = deg_to_rad(float(c[2]))
	return [at, Vector3(sin(h), 0.0, cos(h)) * float(c[1])]


func _without_him(c: Array) -> String:
	_settle()
	var s: Array = _start(c)
	_puck.set_goalie_provider(func() -> Array: return [])
	_puck.clear_carrier()
	_puck.global_position = _rink(s[0])
	_puck.set_puck_velocity(_keeper._net.basis * (s[1] as Vector3))
	var out: String = "misses"
	var t: float = 0.0
	while t < SECONDS:
		var before: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		_puck._physics_process(DT)
		_puck.drain_contact_events()
		t += DT
		var p: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		if p.z >= 0.0 and before.z < 0.0 and absf(p.x) < GameRules.NET_HALF_WIDTH:
			out = "in at x %+.2f, %.2f s" % [p.x, t]
			break
	var rest: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
	_puck.set_goalie_provider(func() -> Array: return [_goalie])
	return out if out != "misses" else "stops at (%+.2f, %+.2f)" % [rest.x, rest.z]


func _trace(c: Array, lines: PackedStringArray) -> void:
	_settle()
	var s: Array = _start(c)
	var inv: Basis = _keeper._net.basis.inverse()
	lines.append("   him at (%+.2f, %+.2f) yaw %+.0f° rest %d; puck at (%+.2f, %+.2f)" % [_keeper.motor.x,
			_keeper.motor.z, rad_to_deg(_keeper.motor.yaw), _keeper.motor.rest, (s[0] as Vector3).x, (s[0] as Vector3).z])
	_puck.clear_carrier()
	_puck.global_position = _rink(s[0])
	_puck.set_puck_velocity(_keeper._net.basis * (s[1] as Vector3))
	_rebase_gear()
	var t: float = 0.0
	while t < SECONDS:
		_keeper._physics_process(DT)
		var v0: Vector3 = inv * _puck.get_puck_velocity()
		var before: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		_puck._goalie_contact.part = null
		_tick_puck()
		t += DT
		var p: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		var v1: Vector3 = inv * _puck.get_puck_velocity()
		var part: Node = _puck._goalie_contact.part
		var inv2: Basis = _keeper._net.basis.inverse()
		var plan_ok: bool = _keeper.cover.plan(p, inv2 * _puck.get_puck_velocity(), _keeper.motor, _keeper._keeper.skeleton.mirrored)
		var into := Basis(Vector3.UP, _keeper.motor.yaw).inverse()
		var mine: Vector3 = into * (p - Vector3(_keeper.motor.x, 0.0, _keeper.motor.z))
		var st: String = "plan %s reading %s fetching %s covering %s mover %s rest %d" % [plan_ok, _keeper.read.reading(),
				_keeper._fetching, _keeper._covering, KeeperMotor.Mover.keys()[_keeper.motor._mover], _keeper.motor.rest]
		if st != _last_status:
			_last_status = st
			lines.append("   . t %.2f %s | puck in his frame (%+.2f across, %+.2f ahead) speed %.2f" % [t, st, mine.x, -mine.z,
					_puck.get_puck_velocity().length()])
		if part != null:
			var pv: Vector3 = inv * _puck._goalie_contact.part_velocity
			var n: Vector3 = inv * _puck._goalie_contact.normal
			lines.append("   t %.2f %-9s gear v (%+.2f,%+.2f) normal (%+.2f,%+.2f) | him (%+.2f,%+.2f) %s | puck (%+.2f,%+.2f) v (%+.2f,%+.2f) -> (%+.2f,%+.2f)" % [
					t, String(part.name), pv.x, pv.z, n.x, n.z, _keeper.motor.x, _keeper.motor.z,
					KeeperMotor.Mover.keys()[_keeper.motor._mover], p.x, p.z, v0.x, v0.z, v1.x, v1.z])
		if p.z >= 0.0 and before.z < 0.0 and absf(p.x) < GameRules.NET_HALF_WIDTH:
			lines.append("   IN at %.2f s x %+.2f" % [t, p.x])
			return
	lines.append("   not in this time")


# The puck's tick, his gear's velocities sampled from where his boxes were a
# tick ago: stepped by hand inside one engine frame, Goalie's once-a-frame
# cache would otherwise hold them at zero, as if his gear never moved.
func _tick_puck() -> void:
	_goalie._part_velocity_frame = Engine.get_physics_frames() - 1
	_goalie.get_collision_part_velocities()
	_puck._physics_process(DT)
	_puck.drain_contact_events()


# His gear's velocities read from rest where he stands now, before a trial.
func _rebase_gear() -> void:
	_goalie._part_velocity_frame = -10
	_goalie.get_collision_part_velocities()
