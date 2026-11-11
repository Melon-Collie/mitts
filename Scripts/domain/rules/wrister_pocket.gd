class_name WristerPocket

# Where to hold the puck before a wrist shot or a charged pass toward `aim`, so
# the release carries the most it can (WristerLoad). The load's full arc sits
# along the tangent at the puck's bearing, so the candidates are the aim turned
# a quarter turn either way (the forehand's pocket on one side, the backhand's on
# the other) and an eighth either side of each. Each is read in the frame the
# body will face once the cursor sits on it (FacingRules): at speed that is the
# travel, so a pocket beside the stick hip loads a shot ahead; at rest the body
# turns to the cursor, so the puck ends in front with the aim off to the side,
# the sideways stance a standing shooter takes.
#
# Pure: a function of the aim, the velocity, the current facing and the build.
# All vectors are world XZ.

# Candidate pocket bearings off the aim, radians: a quarter turn either way and
# an eighth either side of each.
const _CANDIDATES: Array[float] = [
	PI * 0.5, -PI * 0.5, PI * 0.25, -PI * 0.25, PI * 0.75, -PI * 0.75]
const CANDIDATE_COUNT: int = 6


class Result:
	# World XZ direction from the body to hold the puck in.
	var dir: Vector2 = Vector2.ZERO
	var is_backhand: bool = false
	var load_share: float = 1.0
	# Share of max_wrister_power the release from there can carry
	# (WristerLoad.power_share).
	var power_share: float = 1.0
	# World XZ facing the body settles to with the cursor on the pocket.
	var facing: Vector2 = Vector2.ZERO


static func solve(out: Result, aim: Vector2, velocity: Vector2, facing: Vector2,
		is_left_handed: bool, load_cfg: WristerLoad.Config, facing_cfg: FacingRules.Config,
		unloaded_share: float, backhand_coefficient: float,
		facing_scratch: FacingRules.Result, load_scratch: WristerLoad.Result,
		candidate_scratch: Result) -> void:
	out.dir = aim
	out.is_backhand = false
	out.load_share = 1.0
	out.power_share = 1.0
	out.facing = facing
	if aim.length_squared() < 0.000001:
		return
	# No hold beats this, and a tie keeps the first: the search is done there.
	var ceiling: float = maxf(1.0, backhand_coefficient)
	var best: float = -1.0
	for k: int in CANDIDATE_COUNT:
		if best >= ceiling:
			break
		if not read_candidate(candidate_scratch, k, aim, velocity, facing, is_left_handed, load_cfg,
				facing_cfg, unloaded_share, backhand_coefficient, facing_scratch, load_scratch):
			continue
		if candidate_scratch.power_share > best:
			best = candidate_scratch.power_share
			copy(out, candidate_scratch)


# Candidate `k` (of CANDIDATE_COUNT) round `aim`, read as solve reads each, into
# `out`; false when the blade cannot hold the puck there (the hips pivot onto
# the other line past the carry's backhand stop).
static func read_candidate(out: Result, k: int, aim: Vector2, velocity: Vector2,
		facing: Vector2, is_left_handed: bool, load_cfg: WristerLoad.Config,
		facing_cfg: FacingRules.Config, unloaded_share: float, backhand_coefficient: float,
		facing_scratch: FacingRules.Result, load_scratch: WristerLoad.Result) -> bool:
	var aim_dir: Vector2 = aim.normalized()
	var stick_sign: float = _stick_sign(is_left_handed)
	var pocket: Vector2 = aim_dir.rotated(_CANDIDATES[k])
	FacingRules.solve(facing_scratch, facing, pocket, velocity, false, false,
			is_left_handed, facing_cfg)
	if facing_scratch.pivoting:
		return false
	var body_yaw: float = _yaw(facing_scratch.target)
	WristerLoad.solve_load(load_scratch, _bearing(_yaw(pocket), body_yaw, stick_sign),
			_bearing(_yaw(aim_dir), body_yaw, stick_sign), load_cfg)
	out.dir = pocket
	out.is_backhand = load_scratch.is_backhand
	out.load_share = load_scratch.load_share
	out.power_share = WristerLoad.power_share(load_scratch.load_share,
			load_scratch.arm_share, load_scratch.is_backhand, unloaded_share,
			backhand_coefficient)
	out.facing = facing_scratch.target
	return true


static func copy(to: Result, from: Result) -> void:
	to.dir = from.dir
	to.is_backhand = from.is_backhand
	to.load_share = from.load_share
	to.power_share = from.power_share
	to.facing = from.facing


# Share of max_wrister_power a release toward `aim` carries with the puck at
# `puck_offset` from the body (both world XZ) and the body facing `facing`, which
# a wrist shot freezes at the press. Leaves the hand in `load_scratch`.
static func share_at(puck_offset: Vector2, aim: Vector2, facing: Vector2,
		is_left_handed: bool, load_cfg: WristerLoad.Config, unloaded_share: float,
		backhand_coefficient: float, load_scratch: WristerLoad.Result) -> float:
	if aim.length_squared() < 0.000001:
		load_scratch.is_backhand = false
		load_scratch.load_share = 1.0
		load_scratch.arm_share = 1.0
	else:
		var stick_sign: float = _stick_sign(is_left_handed)
		var body_yaw: float = _yaw(facing)
		WristerLoad.solve_load(load_scratch, _bearing(_yaw(puck_offset), body_yaw, stick_sign),
				_bearing(_yaw(aim), body_yaw, stick_sign), load_cfg)
	return WristerLoad.power_share(load_scratch.load_share, load_scratch.arm_share,
			load_scratch.is_backhand, unloaded_share, backhand_coefficient)


# WristerLoad's bearing frame: left-positive yaw, stick side positive.
static func _stick_sign(is_left_handed: bool) -> float:
	return 1.0 if is_left_handed else -1.0


# Yaw of a world XZ direction, 0 along −Z, left-positive.
static func _yaw(v: Vector2) -> float:
	return atan2(-v.x, -v.y)


# A direction's bearing off a body at `body_yaw`, in WristerLoad's frame.
static func _bearing(yaw: float, body_yaw: float, stick_sign: float) -> float:
	return stick_sign * wrapf(yaw - body_yaw, -PI, PI)
