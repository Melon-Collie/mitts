class_name KeeperScreen
extends RefCounted

# Looking round a screen: where a body stands on his sightline to the puck
# (GoalieScreenRules.hides), the least step across that line that sees past the
# body, clear of its edge by the look's clearance, as goalies fight to find the
# puck through traffic. No further than half his chest (KeeperSave.SQUARE_M),
# so a shot down the line he left still meets his chest: the angle he gives up
# to see it. A body square on his line, which only a longer step clears, he
# cannot see round: the screen a goalie is beaten through. Pure; in the net's
# frame (x across, z back into the net), the puck at its height over the ice.

const STEP_MAX_M: float = KeeperSave.SQUARE_M

# The step across from his spot that sees past the screen; zero, a clean look
# or none to be had.
var step := Vector2.ZERO

var _cfg := GoalieScreenRules.ScreenConfig.new()
# His eyes' height on his feet, standing and in the low ready: his mask, as
# the stances hold it.
static var _eye_ready: float = NAN
static var _eye_low: float = NAN


# The look from `spot` (on his feet, `low` in the low ready) at the puck at
# `puck` past `bodies` (net frame, any height: only where they stand is read).
# Sets `step`.
func look(spot: Vector2, puck: Vector3, bodies: PackedVector3Array, low: bool) -> void:
	step = Vector2.ZERO
	_cfg.eye_height = eye_height(low)
	var at := Vector3(spot.x, 0.0, spot.y)
	var hider: int = GoalieScreenRules.hidden_by(at, puck, bodies, _cfg)
	if hider < 0:
		return
	var line := Vector2(puck.x - spot.x, puck.z - spot.y)
	var d: float = line.length()
	var u: Vector2 = line / d
	var n := Vector2(-u.y, u.x)
	var w := Vector2(bodies[hider].x - spot.x, bodies[hider].z - spot.y)
	var along: float = w.dot(u)
	var off: float = w.dot(n)
	var sight_y: float = _cfg.eye_height + along / d * (puck.y - _cfg.eye_height)
	var edge: float = GoalieScreenRules.screener_half_width_at(sight_y, _cfg) + _cfg.peek_clearance
	# A step across moves the sightline where it passes the body by this share
	# of it: the line pivots on the puck. Round the near edge.
	var share: float = (d - along) / d
	var e: float = (off - signf(off if off != 0.0 else 1.0) * edge) / share
	if absf(e) <= STEP_MAX_M and GoalieScreenRules.hidden_by(at + Vector3(n.x, 0.0, n.y) * e, puck, bodies, _cfg) < 0:
		step = n * e


# His eyes' height over the ice on his feet, `low` in the low ready.
static func eye_height(low: bool) -> float:
	if is_nan(_eye_ready):
		var p := KeeperPose.new()
		var skel := KeeperSkeleton.new()
		KeeperPoses.ready(p)
		skel.pose(p)
		_eye_ready = KeeperGear.box(skel, KeeperGear.Part.MASK).origin.y
		KeeperPoses.low_ready(p)
		skel.pose(p)
		_eye_low = KeeperGear.box(skel, KeeperGear.Part.MASK).origin.y
	return _eye_low if low else _eye_ready
