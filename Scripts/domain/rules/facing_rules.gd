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
# turn the stride into a shuffle. Standing or moving, a skater turns round to a
# target behind the body (turn_round_angle).
#
# Stateless: the line and the band are read off whichever way the body faces now,
# so reconcile replay agrees. A pivot under way commits (pivot_commit), so a
# cursor held on the edge cannot flick the hips back and forth, and it leaves the
# cursor far inside the new line's edge, so it cannot flip back. All vectors are
# world XZ.

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
	# How far the hips' turn toward the cursor, past where the line holds them,
	# eases the reach edge: a pivot under way carries through. Capped small, or a
	# body still turning onto the line from a cursor near the edge reads as one.
	var pivot_commit_rad: float = deg_to_rad(4.0)


# Caller-owned result, filled each call.
class Result:
	var target: Vector2 = Vector2.ZERO
	# The cursor has passed the reach edge off the line the hips are on: the target
	# is the other line, forward to backward or back.
	var pivoting: bool = false


static func solve(out: Result, facing: Vector2, cursor_dir: Vector2, velocity: Vector2,
		brake: bool, stance: bool, is_left_handed: bool, cfg: Config) -> void:
	out.target = cursor_dir
	out.pivoting = false
	var speed: float = velocity.length()
	if brake or speed < 0.001:
		return
	var travel: Vector2 = velocity / speed
	var line: Vector2 = travel if facing.dot(travel) >= 0.0 else -travel
	var share: float = _line_share(cfg, facing, line, cursor_dir, speed, stance)
	var off_line: float = line.angle_to(cursor_dir)
	# Measured past where the line would hold the hips, so a body still squared
	# to the cursor as it takes the line up is not a pivot under way.
	var turned: float = maxf(line.angle_to(facing) * signf(off_line)
			- (1.0 - share) * absf(off_line), 0.0)
	var pivoting: bool = absf(off_line) + minf(turned, cfg.pivot_commit_rad) \
			> reach_edge(cfg, line, cursor_dir, is_left_handed)
	if pivoting:
		line = -line
		share = _line_share(cfg, facing, line, cursor_dir, speed, stance)
	if share <= 0.0:
		return
	out.pivoting = pivoting
	out.target = cursor_dir.slerp(line, share)


# How much of the target is `line` rather than the cursor: the hold band once
# the body faces nearer the line, the engage band to take it up.
static func _line_share(cfg: Config, facing: Vector2, line: Vector2, cursor_dir: Vector2,
		speed: float, stance: bool) -> float:
	var share: float
	if absf(facing.angle_to(line)) <= absf(facing.angle_to(cursor_dir)):
		share = smoothstep(cfg.hold_min_speed, cfg.hold_full_speed, speed)
	else:
		share = smoothstep(cfg.engage_min_speed, cfg.engage_full_speed, speed)
	if stance:
		share = minf(share, smoothstep(cfg.stance_square_max_speed - STANCE_SQUARE_BLEND_M_S,
				cfg.stance_square_max_speed, speed))
	return share


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


# The body's turn rate after this tick (rad/s, either sense), from last tick's
# and the rate the facing rule asks for: a turn takes up its rate at most
# `max_accel` (rad/s²), and gives it up at once. A body has to be wound into a
# pivot but not out of one, so the turn never overshoots the target the rule
# eases toward — and a stale rate (a reconcile adopting a tick a snap turned)
# only removes the limit for a tick.
static func turn_rate(prev_rate: float, wanted_rate: float, max_accel: float,
		delta: float) -> float:
	var from: float = prev_rate if prev_rate * wanted_rate > 0.0 else 0.0
	if absf(wanted_rate) <= absf(from):
		return wanted_rate
	return move_toward(from, wanted_rate, max_accel * delta)
