class_name KeeperClear
extends RefCounted

# Clearing a loose puck at his feet with the stick: one an opponent will get a
# stick on before his glove can land on it he sweeps away to the corner rather
# than going down on a puck he would lose, when the blade gets there first.
# The race is KeeperFetch's (the opponent at full sprint, his read of the play
# as the margin); the blade is sent as the poke's (KeeperPoke.aim), turned toe
# forward as far as it takes to lie flat on a puck in close on his blocker
# side. The corner is on the side away from that opponent, out along the boards
# in front of his goal line, so a clear never goes back across the crease at
# its man or toward the net; a puck beside a post goes out its own side. One
# whose way there runs into his own body (a puck by one skate with the man on
# that side) he does not sweep across himself, and covers instead. Pure:
# the puck and the opponents in the net's frame (x across, z back into the
# net), the blade in his authored space as KeeperPoke's.

# The sweep's pace off his paddle: enough to carry it to the boards and round
# them past the opponent on the ice's friction.
const SPEED_M_S: float = 10.0
# Blade turns tried, toe forward from the stance's, least first.
const TURNS_RAD: Array[float] = [0.0, deg_to_rad(30.0), deg_to_rad(60.0), deg_to_rad(90.0)]
# The corner aimed at lies on the boards this far in front of his goal line,
# or of the puck where it is further out.
const CORNER_OUT_M: float = 1.0
# An opponent coming at the puck within this of its line straight out from the
# goal line comes at it head on, and leaves it no side away from him: it goes
# out its own side.
const HEAD_ON_M: float = 0.3
# How far along its way a clear is tested against his body: past the furthest
# of his gear from a puck at his feet.
const PATH_M: float = 1.5
# What of him moves with the sweep, and so never stands in its way.
const STICK: Array[int] = [KeeperGear.Part.BLADE, KeeperGear.Part.PADDLE, KeeperGear.Part.SHAFT]

# Where the blade's centre is sent (his space, on the ice), turned how
# (KeeperPose's blade_yaw), and in how long it gets there; the way the puck is
# cleared, net frame, unit.
var target := Vector3.ZERO
var blade_yaw: float = 0.0
var reach_s: float = 0.0
var way := Vector2.ZERO

var _aim := KeeperPoke.new()
var _hit := SweptDiscOBB.Result.new()


# Whether he clears a puck at his feet at `puck` (net frame) with `opponents`
# where they are, from where `motor` has him (`mirrored` for a right-catcher):
# the first of them gets a stick on it before his glove would land on it
# (`cover_s` from now; his read `read_s` the margin) and the blade, thrust at
# `speed_m_s`, gets there before they do. Sets `target`, `blade_yaw`, `reach_s`
# and `way`.
func plan(puck: Vector2, motor: KeeperMotor, mirrored: bool, opponents: PackedVector2Array, read_s: float,
		speed_m_s: float, cover_s: float) -> bool:
	var theirs: float = KeeperFetch.their_time(puck, opponents)
	if theirs == INF or cover_s + read_s < theirs:
		return false
	_aim.pose_from(motor)
	var rest: Vector3 = _aim.rest_blade()
	var stance_yaw: float = _aim.rest_yaw()
	var want: Vector3 = KeeperPoke.in_his_space(puck, motor, mirrored)
	for turn: float in TURNS_RAD:
		if _aim.aim(want, stance_yaw + turn):
			target = _aim.target
			blade_yaw = stance_yaw + turn
			reach_s = rest.distance_to(target) / speed_m_s
			way = clear_way(puck, _nearest(puck, opponents))
			return reach_s + read_s < theirs and _clear_of_him(want, _his_way(way, motor, mirrored))
	return false


# Whether a puck at `from` (his space) sent along `along` meets nothing of him
# but his stick, as the last aim posed him.
func _clear_of_him(from: Vector3, along: Vector3) -> bool:
	var at := Vector3(from.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, from.z)
	var to: Vector3 = at + along * PATH_M
	for part: int in KeeperGear.PART_COUNT:
		if part not in STICK and SweptDiscOBB.contact(at, to, GameRules.PUCK_COLLISION_RADIUS,
				KeeperGear.box(_aim.skel, part), KeeperGear.half_extents(part), _hit):
			return false
	return true


# A net-frame way on the ice in his space.
static func _his_way(along: Vector2, motor: KeeperMotor, mirrored: bool) -> Vector3:
	var w: Vector3 = Basis(Vector3.UP, motor.yaw).inverse() * Vector3(along.x, 0.0, along.y)
	if mirrored:
		w.x = -w.x
	return w


# The way a puck at `puck` is cleared from an opponent at `them` (net frame):
# to the corner away from him; out its own side from beside a post, or from
# one coming at it head on.
static func clear_way(puck: Vector2, them: Vector2) -> Vector2:
	var side: float = signf(puck.x - them.x)
	var by_post: bool = puck.y > -CORNER_OUT_M and absf(puck.x) > GameRules.NET_HALF_WIDTH
	if by_post or absf(puck.x - them.x) <= HEAD_ON_M:
		side = signf(puck.x)
	if side == 0.0:
		side = -1.0
	var corner := Vector2(side * GameRules.INNER_HALF_WIDTH, minf(puck.y, 0.0) - CORNER_OUT_M)
	return (corner - puck).normalized()


static func _nearest(at: Vector2, opponents: PackedVector2Array) -> Vector2:
	var best := Vector2.INF
	for o: Vector2 in opponents:
		if o.distance_to(at) < best.distance_to(at):
			best = o
	return best
