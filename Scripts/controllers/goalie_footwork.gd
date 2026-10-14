class_name GoalieFootwork
extends RefCounted

# The upright goalie's footwork — what his legs do while the arc mover carries
# him across the crease. Three movements, each eased in and out:
#
# - SHUFFLE: both skates stay on the ice. The trailing skate pushes, sliding
#   out from under him as the body goes on, then draws back in, lifting as it
#   recovers; the stance widens and closes once per stroke.
# - T-PUSH: the lead skate turns toward where he is going and he rides it while
#   the trailing leg extends and drives off its inside edge.
# - EDGE STOP: braking onto his spot, the lead skate plants out wide on its
#   edge and he leans back against his momentum.
#
# The pads are the legs and the save surfaces, so this moves what stops pucks.
# Pad motion is written as a per-tick STEP the actor lays over its eased stance
# (GoalieBodyConfig.*_pad_step_*): a stroke's cadence is faster than the stance
# ease, which would smooth it away. The lean rides the body's own ease.
#
# Host-side, like the rest of the pose solve: the pads and body roll reach every
# client through the replicated pose.

# Body travel per shuffle stroke, and the share of it the push takes — the
# recovery that draws the skate back in is the quicker remainder.
const SHUFFLE_STROKE_M: float = 0.45
const SHUFFLE_PUSH_SHARE: float = 0.6
# How far the pushing skate has slid out at the end of its push; it rolls onto
# its inside edge to push and lifts clear as it recovers.
const SHUFFLE_PUSH_OUT_M: float = 0.09
const SHUFFLE_EDGE_DEG: float = 8.0
const SHUFFLE_LIFT_M: float = 0.02
const SHUFFLE_LEAN_DEG: float = 2.0
# The lead skate's turn toward travel. A real T-push turns it nearly sideways;
# this keeps most of the pad's face on the shooter.
const T_PUSH_LEAD_TURN_DEG: float = 38.0
const T_PUSH_TRAIL_OUT_M: float = 0.12
const T_PUSH_TRAIL_EDGE_DEG: float = 12.0
const T_PUSH_LEAN_DEG: float = 6.0
const STOP_LEAD_OUT_M: float = 0.05
const STOP_LEAD_EDGE_DEG: float = 10.0
const STOP_LEAN_BACK_DEG: float = 5.0
# How quickly each movement eases in and out (1/s): a step is on in ~0.1 s.
const EASE_RATE: float = 12.0
# Below this lateral speed (m/s) the travel side holds, so settling onto a spot
# cannot flip the lead skate.
const SIDE_HOLD_SPEED: float = 0.2

# Stroke phase in [0, 1), advanced by distance travelled.
var phase: float = 0.0
# Goalie-local side he is travelling toward (+1 his right, −1 his left).
var side: float = 1.0
# Eased weights in [0, 1].
var moving: float = 0.0
var pushing: float = 0.0
var stopping: float = 0.0


func reset() -> void:
	phase = 0.0
	moving = 0.0
	pushing = 0.0
	stopping = 0.0


# `lateral_speed` is his signed goalie-local lateral velocity (m/s, + right);
# `t_push` whether the mover is driving a T-push; `braking` whether the edge
# stop is holding his speed down; `shuffle_speed` the pace a full shuffle is.
func advance(delta: float, lateral_speed: float, t_push: bool, braking: bool,
		shuffle_speed: float) -> void:
	var speed: float = absf(lateral_speed)
	if speed > SIDE_HOLD_SPEED:
		side = signf(lateral_speed)
	phase = fposmod(phase + speed * delta / SHUFFLE_STROKE_M, 1.0)
	var k: float = minf(1.0, EASE_RATE * delta)
	moving += (clampf(speed / maxf(shuffle_speed, 0.01), 0.0, 1.0) - moving) * k
	pushing += ((1.0 if t_push and not braking else 0.0) - pushing) * k
	stopping += ((1.0 if braking and speed > SIDE_HOLD_SPEED else 0.0) - stopping) * k


# Write the footwork onto `c` for `state`. Zeroes the pad steps first, so a
# stance that has no footwork — or no footwork at all (`fw` null) — carries none.
static func apply(c: GoalieBodyConfig, fw: GoalieFootwork, state: int) -> void:
	c.left_pad_step_pos = Vector3.ZERO
	c.left_pad_step_rot = Vector3.ZERO
	c.right_pad_step_pos = Vector3.ZERO
	c.right_pad_step_rot = Vector3.ZERO
	if fw == null or not GoalieStateMachine.is_on_his_feet(state):
		return
	fw._write(c)


func _write(c: GoalieBodyConfig) -> void:
	if moving + stopping < 0.001:
		return
	var s: float = side
	var shuffle: float = moving * (1.0 - pushing)
	var push: float = moving * pushing
	# Lead pad (the side he travels toward) and trail pad, as offsets.
	var lead_pos := Vector3.ZERO
	var lead_rot := Vector3.ZERO
	var trail_pos := Vector3.ZERO
	var trail_rot := Vector3.ZERO
	# Shuffle stroke on the trailing skate. An inward roll is `pad side` signed,
	# and the trail is on side −s.
	if phase < SHUFFLE_PUSH_SHARE:
		var u: float = phase / SHUFFLE_PUSH_SHARE
		trail_pos.x -= s * SHUFFLE_PUSH_OUT_M * u * shuffle
		trail_rot.z -= s * SHUFFLE_EDGE_DEG * sin(PI * u) * shuffle
	else:
		var u: float = (phase - SHUFFLE_PUSH_SHARE) / (1.0 - SHUFFLE_PUSH_SHARE)
		trail_pos.x -= s * SHUFFLE_PUSH_OUT_M * (1.0 - smoothstep(0.0, 1.0, u)) * shuffle
		trail_pos.y += SHUFFLE_LIFT_M * sin(PI * u) * shuffle
	# T-push: the lead skate turns toward travel (negative yaw turns his front
	# toward +x), the trail leg extends and drives off its inside edge.
	lead_rot.y -= s * T_PUSH_LEAD_TURN_DEG * push
	trail_pos.x -= s * T_PUSH_TRAIL_OUT_M * push
	trail_rot.z -= s * T_PUSH_TRAIL_EDGE_DEG * push
	# Edge stop: the lead skate plants out wide on its inside edge.
	lead_pos.x += s * STOP_LEAD_OUT_M * stopping
	lead_rot.z += s * STOP_LEAD_EDGE_DEG * stopping
	# Lean: into a shuffle or a push, back against the momentum in the stop.
	# Positive body roll tips the chest toward −x.
	c.body_rot.z += s * (STOP_LEAN_BACK_DEG * stopping
			- SHUFFLE_LEAN_DEG * shuffle - T_PUSH_LEAN_DEG * push)
	if s > 0.0:
		_set_step(c, true, lead_pos, lead_rot)
		_set_step(c, false, trail_pos, trail_rot)
	else:
		_set_step(c, false, lead_pos, lead_rot)
		_set_step(c, true, trail_pos, trail_rot)


# Lay a step on the right (`right`) or left pad, keeping it on the ice: a roll
# moves the pad's lowest corner, so the step carries the height that rests it
# back down (a lift rides on top).
static func _set_step(c: GoalieBodyConfig, right: bool, pos: Vector3, rot: Vector3) -> void:
	var base_rot: Vector3 = c.right_pad_rot if right else c.left_pad_rot
	pos.y += GoalieAnatomy.pad_center_y_on_ice(base_rot + rot) \
			- GoalieAnatomy.pad_center_y_on_ice(base_rot)
	if right:
		c.right_pad_step_pos = pos
		c.right_pad_step_rot = rot
	else:
		c.left_pad_step_pos = pos
		c.left_pad_step_rot = rot
