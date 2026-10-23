class_name KeeperGlide
extends RefCounted

# Skating to a spot that moves: the way he tracks the play, where footwork's
# moves go to a spot and stop on it. Pure, stepped at the tick.
#
# His body is driven by velocity, never stopped between spots: what he skates
# at is the spot's own velocity, plus the closing speed his edges could still
# brake out on it (GoaliePushRules.braking_speed_cap read against the spot's
# own motion, so a spot that keeps moving costs him no lag and one that stops
# he stops on), at most the T-push's top speed; his edges change it at most
# at his lateral acceleration, and dig it out at the edge stop's rate.
#
# His legs show what that takes. Gaining speed, the trail skate (behind the way
# he goes) strokes: it holds its place on the ice while the body passes over
# it, then slides back in under him along the ice. Matched, he glides in the
# stance, both skates on the ice. Faster than a shuffle, the lead skate turns
# toward the travel as a T-push's does; slowing, the lead skate's edge digs and
# he leans back against it. A move mostly in depth strokes as C-cuts, the
# skates taking turns.
#
# The net frame, as the motor's places: x across, z back toward the net; his
# turn `yaw` is the motor's, given to step and pose.

# A spot this near, moving no faster than this relative to him, he is on.
const THERE_M: float = 0.005
const MATCHED_M_S: float = 0.05
# The stroke: the body travel per stroke, and how much of it the skate holds
# its place for; at a T-push's speed the stroke is a push this much longer.
const STROKE_M: float = 0.45
const HOLD_M: float = 0.14
const LONG_STROKE_SHARE: float = 1.0
# How fast the drive, the brake and the lead skate's turn come on and go.
const EASE_S: float = 0.08
# The brake's look at full: the lead skate out and onto its edge, the lean
# back; and the lean into a drive.
const BRAKE_OUT_M: float = 0.05
const BRAKE_EDGE_RAD: float = deg_to_rad(12.0)
const BRAKE_LEAN_RAD: float = deg_to_rad(6.0)
const DRIVE_LEAN_RAD: float = deg_to_rad(4.0)
# A C-cut stroke's skate heel turned out at its widest.
const CUT_HEEL_RAD: float = KeeperFootwork.C_CUT_HEEL_OUT_RAD
# A skate left out when he stops driving comes back in at least this fast: the
# footwork's push leg coming back under him.
const RETURN_S: float = KeeperFootwork.RECOVER_S

var t_push_speed: float = GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S
var shuffle_speed: float = GameRules.DEFAULT_GOALIE_SHUFFLE_SPEED_M_S
var accel: float = GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2

var x: float = 0.0
var z: float = 0.0
var velocity := Vector2.ZERO

# How far through its stroke the stroking skate is (0 at rest under him), the
# strokes taken, which way he last went in his own frame (+x his blocker side),
# and how far the drive, the brake and the lead skate's turn are on.
var _phase: float = 0.0
var _strokes: int = 0
var _way := Vector2.RIGHT
# The stroke's form, held from its start until it is back under him: lateral
# (a shuffle's or a T-push's) or in depth (a C-cut's), the way it goes (+1 his
# blocker side, or back), and the leg a C-cut strokes with.
var _lateral: bool = true
var _side: float = 1.0
var _cut_leg: int = 0
var _drive: float = 0.0
var _brake: float = 0.0
var _turn: float = 0.0


# Whether he is on `spot`, moving with it.
func is_on(spot: Vector2, spot_velocity: Vector2) -> bool:
	return Vector2(x, z).distance_to(spot) <= THERE_M and velocity.distance_to(spot_velocity) <= MATCHED_M_S


# His legs back in the stance: no stroke out, no drive, brake or turn left.
func is_settled() -> bool:
	return _phase <= 0.0 and _drive <= 0.0 and _brake <= 0.0 and _turn <= 0.0


func step(dt: float, spot: Vector2, spot_velocity: Vector2, yaw: float) -> void:
	var at := Vector2(x, z)
	var to: Vector2 = spot - at
	var d: float = to.length()
	var dir: Vector2 = to / d if d > 1e-6 else Vector2.ZERO
	# How fast he closes on the spot, in its own motion, and what is left of
	# the way after this tick's travel.
	var rel: Vector2 = velocity - spot_velocity
	var closing: float = rel.dot(dir)
	var next_left: float = d - maxf(closing, 0.0) * dt
	var was: Vector2 = velocity
	var pushing: bool
	if d > 1e-6 and closing > 0.0 and closing >= GoaliePushRules.braking_speed_cap(next_left, accel):
		# The stop starts the tick it would be too late to after this one's
		# travel, the edges digging as hard as it takes to stop on the spot,
		# and any drift across it killed on them too.
		var across: Vector2 = (rel - dir * closing).move_toward(Vector2.ZERO,
				accel * GameRules.GOALIE_EDGE_STOP_DECEL_RATIO * dt)
		closing = maxf(closing - closing * closing / (2.0 * d) * dt, 0.0)
		velocity = spot_velocity + dir * closing + across
		pushing = false
	else:
		var want: Vector2 = spot_velocity
		if d > 1e-6:
			want += dir * GoaliePushRules.braking_speed_cap(next_left, accel)
		want = want.limit_length(t_push_speed)
		var change: Vector2 = want - velocity
		# Speeding up along the way he goes is his push; anything else his
		# edges.
		pushing = change.dot(velocity) >= 0.0 or velocity.length() < MATCHED_M_S
		var most: float = (accel if pushing else accel * GameRules.GOALIE_EDGE_STOP_DECEL_RATIO) * dt
		velocity += change.limit_length(most)
	var moved: Vector2 = 0.5 * (was + velocity) * dt
	x += moved.x
	z += moved.y
	if d <= THERE_M and spot_velocity.length() < MATCHED_M_S and velocity.length() < accel * dt:
		x = spot.x
		z = spot.y
		velocity = Vector2.ZERO
	var change_now: float = (velocity - was).length() / maxf(dt, 1e-6)
	# The legs: in his own frame.
	var mine: Vector2 = velocity.rotated(yaw)
	var speed: float = mine.length()
	if speed > MATCHED_M_S:
		_way = mine / speed
	var gaining: bool = pushing and change_now > accel * 0.5 and speed > MATCHED_M_S
	var slowing: bool = not pushing and change_now > accel * 0.5
	_drive = move_toward(_drive, 1.0 if gaining else 0.0, dt / EASE_S)
	_brake = move_toward(_brake, (clampf(speed / shuffle_speed, 0.0, 1.0) if slowing else 0.0), dt / EASE_S)
	var fast: float = clampf((speed - shuffle_speed) / maxf(t_push_speed - shuffle_speed, 1e-3), 0.0, 1.0)
	# The T-push's form is a lateral one: in depth the strokes stay C-cuts.
	_turn = move_toward(_turn, fast * _drive if _lateral else 0.0, dt / EASE_S)
	# A stroke goes with the ground under him while he drives; one under way
	# when he stops driving still comes in, at least as fast as a skate comes
	# back under a standing goalie.
	if _phase <= 0.0 and (_drive <= 0.0 or _turn <= 0.0) and _brake <= 0.0:
		_take_form()
	if _drive > 0.0 or _phase > 0.0:
		var on: float = speed * dt / _stroke_length()
		if _drive <= 0.0:
			on = maxf(on, dt / RETURN_S)
		_phase += on
		if _phase >= 1.0:
			_strokes += 1
			_phase = fmod(_phase, 1.0) if _drive > 0.0 else 0.0
			_take_form()


# The next stroke's form, from the way he is going now.
func _take_form() -> void:
	_lateral = absf(_way.x) >= absf(_way.y)
	_side = signf(_way.x if _lateral else _way.y)
	if _side == 0.0:
		_side = 1.0
	_cut_leg = _strokes % 2


func pose(p: KeeperPose) -> void:
	KeeperPoses.ready(p)
	var side: float = _side
	var out: float = _stroke_out() * _stroke_length() / STROKE_M
	if _lateral:
		var lead: KeeperPose.Leg = p.legs[1 if side > 0.0 else 0]
		var trail: KeeperPose.Leg = p.legs[0 if side > 0.0 else 1]
		trail.ankle.x -= side * HOLD_M * out
		_drive_knee_over(p, trail, -side, out)
		# Faster than a shuffle the lead skate turns toward the travel.
		var way := Vector3(_way.x, 0.0, _way.y)
		lead.toe = lead.toe.slerp(way, _turn)
		# Slowing, its edge digs.
		lead.ankle.x += side * BRAKE_OUT_M * _brake
		lead.shin_front = lead.shin_front.rotated(Vector3.FORWARD, -side * BRAKE_EDGE_RAD * _brake)
		p.lumbar_rot.z -= side * (DRIVE_LEAN_RAD * _drive - BRAKE_LEAN_RAD * _brake)
	else:
		# In depth, the skates take turns carving out to the side.
		var leg: int = _cut_leg
		var sx: float = -1.0 if leg == 0 else 1.0
		var cut: KeeperPose.Leg = p.legs[leg]
		# Going back the C carves out in front of him; going forward it barely
		# holds behind, driven out to the side instead (KeeperFootwork's).
		var back: bool = side > 0.0
		cut.ankle.x += sx * (KeeperFootwork.C_CUT_OUT_BACK_M if back else KeeperFootwork.C_CUT_OUT_FORWARD_M) * out
		cut.ankle.z -= side * (KeeperFootwork.C_CUT_HOLD_BACK_M if back else KeeperFootwork.C_CUT_HOLD_FORWARD_M) * out
		var toe_out: float = KeeperPoses.READY_TOE_OUT_RAD - side * CUT_HEEL_RAD * out
		cut.toe = Vector3(sx * sin(toe_out), 0.0, -cos(toe_out))
		_drive_knee_over(p, cut, sx, out)
		for i: int in 2:
			var s: float = -1.0 if i == 0 else 1.0
			p.legs[i].ankle.x += s * 0.5 * BRAKE_OUT_M * _brake
		p.lumbar_rot.x += side * (DRIVE_LEAN_RAD * _drive - BRAKE_LEAN_RAD * _brake)


# The stroking leg's knee comes out of the stance's knee-in to drive over its
# skate, as the footwork's push leg's does, or the pad's corner is driven into
# the ice; and the hips sink as far as the leg needs to reach the skate.
static func _drive_knee_over(p: KeeperPose, leg: KeeperPose.Leg, sx: float, out: float) -> void:
	var drive := Vector3(sx * KeeperFootwork.PUSH_KNEE_OUT, 0.0, -1.0)
	var driven: float = smoothstep(0.0, KeeperFootwork.PUSH_KNEE_DRIVEN_AT, out)
	leg.knee_pole = leg.knee_pole.lerp(drive, driven)
	leg.shin_front = leg.shin_front.lerp(drive, driven)
	var reach: float = KeeperFootwork.TRAIL_REACH * (KeeperAnatomy.THIGH_M + KeeperAnatomy.SHIN_M)
	var across: float = leg.ankle.x - sx * KeeperAnatomy.HIP_HALF_SPACING_M
	var ahead: float = leg.ankle.z - p.pelvis.z
	var up: float = sqrt(maxf(reach * reach - across * across - ahead * ahead, 0.0))
	p.pelvis.y = minf(p.pelvis.y, leg.ankle.y + up)


# How far out the stroking skate is, 0 to 1 of the hold: out while it holds
# its place on the ice as he passes over it, then back in under him along it.
func _stroke_out() -> float:
	var hold: float = HOLD_M / STROKE_M
	if _phase < hold:
		return _phase / hold
	return 1.0 - smoothstep(0.0, 1.0, (_phase - hold) / (1.0 - hold))


func _stroke_length() -> float:
	return STROKE_M * (1.0 + LONG_STROKE_SHARE * _turn)
