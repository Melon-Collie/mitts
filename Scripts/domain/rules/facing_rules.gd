class_name FacingRules

# Where a skater's body heads. A skater moving keeps the hips on the skating line,
# forward or backward — the torso twist and arm reach carry the puck out at the
# side — so the target blends from the cursor to the line with speed.
#
# Two speed bands, picked by which of the two the body faces now: taking up the
# line needs real skating speed (engage_*), so a side-step tap stays squared;
# keeping it holds down to a crawl (hold_*), so a coast keeps its line. The hips
# pivot to the other line, turning toward the cursor, when the cursor passes the
# edge of what the blade can reach off the line on its side (forehand_edge_rad /
# backhand_edge_rad): the blade passes in front of the body and the cursor comes
# out on the other hand. Braking squares to the cursor. The stance squares to it
# too, but only below stance_square_max_speed — opening up to a man or a pass is
# a low-speed move, and at speed squaring would swing the hips off the line and
# turn the stride into a shuffle. A moving skater turns round to a target behind
# the body (turn_round_angle); only a standing one is held off it by the
# unreachable-wedge freeze.
#
# Stateless: the line and the band are read off whichever way the body faces now,
# so reconcile replay agrees, and a pivot leaves the cursor far inside the new
# line's edge, so it cannot flip back. All vectors are world XZ.

# The speed band over which the stance hands facing from the cursor back to travel.
const STANCE_SQUARE_BLEND_M_S: float = 0.5


class Config:
	var engage_min_speed: float = 1.6
	var engage_full_speed: float = 2.4
	var hold_min_speed: float = 0.5
	var hold_full_speed: float = 1.5
	# How far off the body's facing the blade reaches on each side: the torso's
	# twist plus the top hand's range of motion. SkaterController sets them from
	# its own (test_facing_follows_travel.gd holds it).
	var forehand_edge_rad: float = deg_to_rad(157.0)
	var backhand_edge_rad: float = deg_to_rad(157.0)
	var stance_square_max_speed: float = 3.0


# Caller-owned result, filled each call.
class Result:
	var target: Vector2 = Vector2.ZERO
	# The cursor has passed the reach edge off the line the hips are on: the target
	# is the other line, forward to backward or back.
	var pivoting: bool = false
	# Still moving (past hold_min_speed, braking included): a skater can pivot or
	# step round to anything, so the unreachable-wedge freeze holds only one
	# standing still.
	var free_to_turn_round: bool = false


static func solve(out: Result, facing: Vector2, cursor_dir: Vector2, velocity: Vector2,
		brake: bool, stance: bool, is_left_handed: bool, cfg: Config) -> void:
	out.target = cursor_dir
	out.pivoting = false
	var speed: float = velocity.length()
	out.free_to_turn_round = speed > cfg.hold_min_speed
	if brake or speed < 0.001:
		return
	var travel: Vector2 = velocity / speed
	var line: Vector2 = travel if facing.dot(travel) >= 0.0 else -travel
	var pivoting: bool = absf(line.angle_to(cursor_dir)) \
			> reach_edge(cfg, line, cursor_dir, is_left_handed)
	if pivoting:
		line = -line
	var on_line: bool = absf(facing.angle_to(line)) <= absf(facing.angle_to(cursor_dir))
	var share: float
	if on_line:
		share = smoothstep(cfg.hold_min_speed, cfg.hold_full_speed, speed)
	else:
		share = smoothstep(cfg.engage_min_speed, cfg.engage_full_speed, speed)
	if stance:
		share = minf(share, smoothstep(cfg.stance_square_max_speed - STANCE_SQUARE_BLEND_M_S,
				cfg.stance_square_max_speed, speed))
	if share <= 0.0:
		return
	out.pivoting = pivoting
	out.target = cursor_dir.slerp(line, share)


# The sign of facing.angle_to(dir) for a dir on the forehand side: a left-handed
# shot carries the blade on the body's left.
static func forehand_sign(is_left_handed: bool) -> float:
	return -1.0 if is_left_handed else 1.0


# How far off `facing` the blade reaches on the side `dir` lies.
static func reach_edge(cfg: Config, facing: Vector2, dir: Vector2,
		is_left_handed: bool) -> float:
	if signf(facing.angle_to(dir)) == forehand_sign(is_left_handed):
		return cfg.forehand_edge_rad
	return cfg.backhand_edge_rad


# The signed angle facing turns through to reach a target behind the body: round
# on the cursor's side, so the body opens toward where the player is looking.
# Turning round to the travel, target and cursor can sit either side of straight
# back, and the short way would then swing the body through the far side. With
# the cursor dead behind, the side is the one facing already leans to.
static func turn_round_angle(facing: Vector2, target: Vector2, cursor_dir: Vector2) -> float:
	var turn: float = facing.angle_to(target)
	if turn * facing.angle_to(cursor_dir) < 0.0:
		turn -= signf(turn) * TAU
	return turn
