class_name KeeperRestepEase
extends RefCounted

# A client's predicted goalie, eased onto a prediction that jumped (#913): a
# snapshot that re-steps his predictor, or the predictor taking over from the
# interpolated fallback. The new prediction is the right one and the old one is
# what is on screen, so for EASE_S he is drawn moving from one onto the other
# rather than in the new place on the next frame: his root carries the gap it
# had at the jump, shrinking, so he keeps moving with the prediction, and his
# pose blends from the one on screen. His save boxes are seated from what is
# drawn, so through the ease the puck and the sticks meet him where he is drawn.
#
# A gap past SNAP_M is a teleport (a faceoff, a goal's reset), and a frame drawn
# by something else (a replay) leaves nothing on screen to ease from: both snap.

const EASE_S: float = 0.08
# Twice the worst re-step measured (~0.47 m of box gap, #913).
const SNAP_M: float = 1.0

var _shown := GoalieNetworkState.new()
var _shown_frame: int = -2
var _from := GoalieNetworkState.new()
var _off_x: float = 0.0
var _off_z: float = 0.0
var _off_yaw: float = 0.0
var _elapsed: float = -1.0
var _out := GoalieNetworkState.new()


# What was drawn of him on physics frame `frame`, by whichever path drew him.
func note_drawn(s: GoalieNetworkState, frame: int) -> void:
	_shown.copy_from(s)
	_shown_frame = frame


# What to draw for `target` on physics frame `frame`, `delta` after the last;
# `jumped` when it does not continue the prediction drawn last frame. Returns
# `target` itself or this ease's own state, to be read before the next call.
func apply(target: GoalieNetworkState, jumped: bool, delta: float, frame: int) -> GoalieNetworkState:
	if jumped:
		_elapsed = -1.0
		var gap := Vector2(_shown.position_x - target.position_x, _shown.position_z - target.position_z)
		if _shown_frame == frame - 1 and gap.length() <= SNAP_M:
			_from.copy_from(_shown)
			_off_x = gap.x
			_off_z = gap.y
			_off_yaw = angle_difference(target.rotation_y, _shown.rotation_y)
			_elapsed = 0.0
	if _elapsed < 0.0:
		return target
	_elapsed += delta
	var s: float = smoothstep(0.0, 1.0, clampf(_elapsed / EASE_S, 0.0, 1.0))
	var rest: float = 1.0 - s
	_out.copy_from(target)
	_out.position_x = target.position_x + _off_x * rest
	_out.position_z = target.position_z + _off_z * rest
	_out.rotation_y = target.rotation_y + _off_yaw * rest
	_out.pose.blend(_from.pose, target.pose, s)
	if s >= 1.0:
		_elapsed = -1.0
	return _out
