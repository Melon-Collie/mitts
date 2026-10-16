class_name FacingRules

# Where a skater's body heads. A skater moving faces where they skate — the hips
# go with the stride, and the torso twist and arm reach carry the puck out at the
# side — so the target blends from the cursor to the travel direction with speed.
#
# Two speed bands, picked by which of the two the body faces now: taking up the
# travel needs real skating speed (engage_*), so a side-step tap stays squared;
# keeping it holds down to a crawl (hold_*), so a coast keeps its line. It squares
# to the cursor when the cursor falls behind the travel cone (skating backward
# while watching the play) and when braking. Either way round the target can sit
# behind the body, and the body turns round to it (turn_round_angle). The stance
# squares to the cursor too, but only below stance_square_max_speed — opening up
# to a man or a pass is a low-speed move, and at speed squaring would swing the
# hips off the line and turn the stride into a shuffle.
#
# Stateless: the band and the cone's hysteresis are read off whichever of the two
# the body faces now, so reconcile replay agrees. All vectors are world XZ.

# The speed band over which the stance hands facing from the cursor back to travel.
const STANCE_SQUARE_BLEND_M_S: float = 0.5


class Config:
	var engage_min_speed: float = 1.6
	var engage_full_speed: float = 2.4
	var hold_min_speed: float = 0.5
	var hold_full_speed: float = 1.5
	var cone_rad: float = deg_to_rad(120.0)
	var cone_hysteresis_rad: float = deg_to_rad(15.0)
	var stance_square_max_speed: float = 3.0


# Caller-owned result, filled each call.
class Result:
	var target: Vector2 = Vector2.ZERO
	# The cursor has fallen behind the travel cone of a moving skater: facing turns
	# round to it, even past the unreachable-wedge freeze — that turn is how a
	# skater goes to skating backward.
	var turning_to_cursor_behind: bool = false
	# Facing has taken up some of the travel: the target is where the skating goes,
	# not the cursor, so the unreachable-wedge freeze (which keeps the body off a
	# cursor it cannot reach) does not hold it. A backward skater whose cursor comes
	# round ahead turns to skate forward this way.
	var taking_up_travel: bool = false


static func solve(out: Result, facing: Vector2, cursor_dir: Vector2, velocity: Vector2,
		brake: bool, stance: bool, cfg: Config) -> void:
	out.target = cursor_dir
	out.turning_to_cursor_behind = false
	out.taking_up_travel = false
	if brake:
		return
	var speed: float = velocity.length()
	if speed < 0.001:
		return
	var travel: Vector2 = velocity / speed
	var following: bool = absf(facing.angle_to(travel)) <= absf(facing.angle_to(cursor_dir))
	var share: float
	if following:
		share = smoothstep(cfg.hold_min_speed, cfg.hold_full_speed, speed)
	else:
		share = smoothstep(cfg.engage_min_speed, cfg.engage_full_speed, speed)
	if stance:
		share = minf(share, smoothstep(cfg.stance_square_max_speed - STANCE_SQUARE_BLEND_M_S,
				cfg.stance_square_max_speed, speed))
	if share <= 0.0:
		return
	var cone: float = cfg.cone_rad + (cfg.cone_hysteresis_rad if following
			else -cfg.cone_hysteresis_rad)
	if absf(travel.angle_to(cursor_dir)) > cone:
		out.turning_to_cursor_behind = true
		return
	out.taking_up_travel = true
	out.target = cursor_dir.slerp(travel, share)


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
