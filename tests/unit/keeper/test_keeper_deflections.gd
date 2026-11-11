extends GutTest

# A flat puck that meets his gear in a stance he sets in, on his feet or down,
# comes off it away from the net: through his gear's own contact rule
# (GoalieSaveRules.resolve_contact), whatever it meets first, it never heads on
# into the mouth past him. A hole is KeeperSeams' to allow
# (test_keeper_seams.gd); gear that turns a puck in is never a window. The
# kick, a leg thrust out in motion, is not held here: a puck clipping its edge
# may glance on in.
#
# Keeper space: he faces -z, the goal line GOAL_LINE_Z behind him, as at the
# top of his crease.

const GOAL_LINE_Z: float = CreaseRules.ARC_RADIUS
const SHOOTER_Z: float = -3.2
const SHOOTERS_X: Array[float] = [-2.0, 0.0, 2.0]
const AIMS: int = 32
const SPEED_M_S: float = 20.0

var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()
var _hit := SweptDiscOBB.Result.new()
var _scratch := SweptDiscOBB.Result.new()
var _after := SweptDiscOBB.Result.new()
var _contact := GoalieSaveRules.ContactResult.new()


func _stances() -> Array:
	return [
		["ready", func(p: KeeperPose) -> void: KeeperPoses.ready(p)],
		["low ready", func(p: KeeperPose) -> void: KeeperPoses.low_ready(p)],
		["butterfly", func(p: KeeperPose) -> void: KeeperPoses.butterfly(p)],
		["half L", func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, -1.0)],
		["half R", func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, 1.0)],
		["extension L", func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, -1.0)],
		["extension R", func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, 1.0)],
	]


func test_no_flat_puck_comes_off_his_gear_into_the_net() -> void:
	var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
	var reach: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
	for stance: Array in _stances():
		(stance[1] as Callable).call(_pose)
		_skel.pose(_pose)
		for sx: float in SHOOTERS_X:
			for i: int in AIMS:
				var aim_x: float = lerpf(-reach, reach, float(i) / float(AIMS - 1))
				var from := Vector3(sx, y, SHOOTER_Z)
				var to := Vector3(aim_x, y, GOAL_LINE_Z)
				var part: int = KeeperGear.nearest(_skel, from, to, GameRules.PUCK_COLLISION_RADIUS, _hit, _scratch)
				if part < 0:
					continue
				GoalieSaveRules.resolve_contact((to - from).normalized() * SPEED_M_S, KeeperGear.save_part(part),
						_hit.normal, _contact, Vector3.FORWARD)
				assert_false(_goes_in(_hit.point + _hit.normal * _hit.depth, _contact.velocity),
						"%s: a flat puck from x %.1f at x %.2f comes off %s into the net"
						% [stance[0], sx, aim_x, KeeperGear.Part.keys()[part]])


# Whether a rebound from `at` along `v` reaches the goal line between the posts
# and under the bar without meeting more of him on the way.
func _goes_in(at: Vector3, v: Vector3) -> bool:
	if v.z <= 0.0 or _contact.caught:
		return false
	var cross: Vector3 = at + v * ((GOAL_LINE_Z - at.z) / v.z)
	if absf(cross.x) > GameRules.NET_HALF_WIDTH or cross.y > GameRules.NET_HEIGHT:
		return false
	var start: Vector3 = at + v.normalized() * 0.01
	return KeeperGear.nearest(_skel, start, cross, GameRules.PUCK_COLLISION_RADIUS, _after, _scratch) < 0
