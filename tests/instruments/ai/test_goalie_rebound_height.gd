extends GutTest

# ── HOW HIGH DOES A REBOUND GO? ──────────────────────────────────────────────
# Fires the shot map at the live goalie and reports, per first surface struck,
# how high the puck climbs after that contact: the pop-up off a leaning stick
# face is a grip question (GoalieSaveRules.MATERIALS), and this is what a grip
# change is read against. The worst rows print the contact (normal, in, out,
# stance) so a pop-up can be traced to its face.
#
# Mirrors the save loop of real_goalie_shot_harness.fire_tracking_rebound, but
# follows every contact rather than stopping at the sweep. Peak heights include
# the contact's own height, so a high shot off the mask reads high without having
# popped; read the STICK and PAD rows, whose contacts are near the ice.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const MPH_TO_MS: float = 0.44704
const SPOTS: Array[Vector3] = [
	Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 6.4), Vector3(0.0, 0.0, 10.0),
	Vector3(0.0, 0.0, 16.0), Vector3(5.5, 0.0, 8.0), Vector3(-5.5, 0.0, 8.0),
	Vector3(8.5, 0.0, 4.0),
]
const AIMS: Array[float] = [-1.0, -0.6, -0.3, 0.0, 0.3, 0.6, 1.0]
const MPH: Array[float] = [40.0, 65.0, 85.0]

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController
var _h: RefCounted
var _names: Array = GoalieSaveRules.SavePart.keys()
var _first_part: int = -1
var _first_line: String = ""


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_ctrl)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)


func test_report_rebound_height_by_save_surface() -> void:
	var max_aim: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS \
			- GameRules.PUCK_COLLISION_RADIUS
	var lofts: Array[int] = [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW,
			ShotMechanics.ELEVATION_MID, ShotMechanics.ELEVATION_HIGH]
	# Per first part: [shots, peak > 1 m, peak > 2 m, sum of peaks]
	var by_part: Dictionary = {}
	var worst: Array = []
	for spot: Vector3 in SPOTS:
		var from := Vector3(spot.x, 0.0, GOAL_Z + spot.z)
		for loft: int in lofts:
			for frac: float in AIMS:
				for mph: float in MPH:
					_ctrl.reset_to_crease()
					_h.settle(from, 90)
					var peak: float = _shot(from, Vector3(frac * max_aim, 0.0, GOAL_Z), loft,
							mph * MPH_TO_MS)
					if _first_part < 0:
						continue
					var k: String = _names[_first_part]
					if not by_part.has(k):
						by_part[k] = [0, 0, 0, 0.0]
					var row: Array = by_part[k]
					row[0] += 1
					row[1] += 1 if peak > 1.0 else 0
					row[2] += 1 if peak > 2.0 else 0
					row[3] += peak
					worst.append([peak, "peak %.2f  %s L%d a%.1f %dmph  %s"
							% [peak, spot, loft, frac, mph, _first_line]])
	gut.p("first part | shots | peak>1m | peak>2m | mean peak")
	var t: Array = [0, 0, 0, 0.0]
	for k: String in by_part.keys():
		var r: Array = by_part[k]
		for i: int in 4:
			t[i] += r[i]
		gut.p("%-8s | %5d | %5d | %5d | %.2f" % [k, r[0], r[1], r[2], r[3] / maxf(r[0], 1)])
	gut.p("%-8s | %5d | %5d | %5d | %.2f" % ["TOTAL", t[0], t[1], t[2], t[3] / maxf(t[0], 1)])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i: int in mini(12, worst.size()):
		gut.p(worst[i][1])
	assert_true(true, "report")


# Marches one shot; returns the highest the puck gets after its first goalie
# contact (0 when it never touches him), over 1.5 s.
func _shot(from: Vector3, aim: Vector3, loft: int, speed: float) -> float:
	_first_part = -1
	var vel: Vector3 = _h.shot_velocity_at(from, aim, loft, speed, 0.0)
	_shooter.global_position = from
	_puck.clear_carrier()
	var pos: Vector3 = from
	pos.y = _puck.ice_height
	_puck.global_position = pos
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	var res := GoalieSaveRules.ContactResult.new()
	var frame := PuckGeometryCollision.Result.new()
	var tick := PuckAuthorityRules.TickResult.new()
	var peak: float = 0.0
	for _s: int in 180:
		var prev: Vector3 = pos
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_h._tick_goalie()
		if _puck.motion_pinned:
			break
		if _puck.linear_velocity.distance_to(vel) > 0.01:
			vel = _puck.linear_velocity
		PuckAuthorityRules.step_frame_substep(pos, vel, Harness.DT, Harness.RADIUS,
				_puck.max_speed, _puck.ice_height, _puck.max_height, frame, tick)
		pos = tick.position
		vel = tick.velocity
		if _first_part >= 0:
			peak = maxf(peak, pos.y)
		if GoalieContactDetector.nearest([_goalie], prev, pos, Harness.RADIUS,
				_h._scratch, _h._contact):
			var c: GoalieContactDetector.Contact = _h._contact
			var part: int = _h._classify_part(c.part as Node3D)
			var pv: Vector3 = _h._struck_part_velocity()
			var fwd: Vector3 = -(c.goalie as Node3D).global_transform.basis.z
			var vin: Vector3 = vel
			GoalieSaveRules.resolve_contact(vel, part, c.normal, res, fwd, pv)
			vel = res.velocity
			pos = c.point + c.normal * c.depth if not res.trapped \
					else Vector3(c.point.x, _puck.ice_height, c.point.z)
			if _first_part < 0:
				_first_part = part
				_first_line = "%s n=(%.2f,%.2f,%.2f) in=(%.1f,%.1f,%.1f) out=(%.1f,%.1f,%.1f) %s" % [
						_names[part], c.normal.x, c.normal.y, c.normal.z,
						vin.x, vin.y, vin.z, vel.x, vel.y, vel.z,
						GoalieStateMachine.State.keys()[_ctrl._sm.current]]
				peak = pos.y
			if res.caught:
				break
	return peak
