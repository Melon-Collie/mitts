extends GutTest

# How soon a butterfly covers the low net: the drop played tick by tick
# through KeeperMotor (from the ready stance and from the low ready, at Hard's
# drop), and at each tick the share of lines across the mouth from the slot a
# puck at each height meets his gear on and comes off away from the net
# (KeeperGear, GoalieSaveRules). Each row's string is those lines on the ice,
# post to post: s stopped, G through, o in off him.
#
# Keeper space: he faces -z, the goal line at the top of his crease behind him.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const GOAL_LINE_Z: float = CreaseRules.ARC_RADIUS
const SHOOTER := Vector3(0.0, 0.0, -3.2)
const AIMS: int = 24
const HEIGHTS: Array[float] = [GameRules.PUCK_COLLISION_HALF_HEIGHT, 0.10, 0.20]

var _hit := SweptDiscOBB.Result.new()
var _scratch := SweptDiscOBB.Result.new()
var _after := SweptDiscOBB.Result.new()
var _contact := GoalieSaveRules.ContactResult.new()


func test_report() -> void:
	var lines: PackedStringArray = []
	for sunk: bool in [false, true]:
		var motor := KeeperMotor.new()
		motor.save_move.drop_s = GoalieSkillProfile.hard().butterfly_drop_s
		if sunk:
			motor.low_ready.asked = true
			for _i: int in 40:
				motor.step(DT)
		lines.append("== from the %s (Hard drop %.2f s) ==" % ["low ready" if sunk else "ready stance",
				motor.save_move.drop_s])
		lines.append("   t      on ice  10 cm  20 cm | on the ice, post to post")
		lines.append(_row(motor, -1.0))
		motor.save(KeeperSaveMove.Low.BUTTERFLY, 1.0)
		var t: float = 0.0
		while t < 0.4:
			motor.step(DT)
			t += DT
			lines.append(_row(motor, t))
			if motor.save_move.is_set() and t > 0.05:
				break
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _row(motor: KeeperMotor, t: float) -> String:
	var pose := KeeperPose.new()
	motor.pose(pose)
	var skel := KeeperSkeleton.new()
	skel.pose(pose)
	var row: String = ("  set   " if t < 0.0 else "  %.3f " % t)
	var ice: String = ""
	for h: float in HEIGHTS:
		var covered: int = 0
		for i: int in AIMS:
			var c: String = _line(skel, i, h)
			if c == "s":
				covered += 1
			if h == HEIGHTS[0]:
				ice += c
		row += "  %4.0f%%" % (100.0 * covered / AIMS)
	return row + " | " + ice


func _line(skel: KeeperSkeleton, i: int, h: float) -> String:
	var reach: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
	var from := Vector3(SHOOTER.x, h, SHOOTER.z)
	var to := Vector3(lerpf(-reach, reach, float(i) / float(AIMS - 1)), h, GOAL_LINE_Z)
	var part: int = KeeperGear.nearest(skel, from, to, GameRules.PUCK_COLLISION_RADIUS, _hit, _scratch)
	if part < 0:
		return "G"
	GoalieSaveRules.resolve_contact((to - from).normalized() * 25.0, KeeperGear.save_part(part),
			_hit.normal, _contact, Vector3.FORWARD)
	var v: Vector3 = _contact.velocity
	var at: Vector3 = _hit.point + _hit.normal * _hit.depth
	if v.z <= 0.0 or _contact.caught:
		return "s"
	var cross: Vector3 = at + v * ((GOAL_LINE_Z - at.z) / v.z)
	if absf(cross.x) > GameRules.NET_HALF_WIDTH or cross.y > GameRules.NET_HEIGHT:
		return "s"
	var start: Vector3 = at + v.normalized() * 0.01
	return "s" if KeeperGear.nearest(skel, start, cross, GameRules.PUCK_COLLISION_RADIUS, _after, _scratch) >= 0 else "o"
