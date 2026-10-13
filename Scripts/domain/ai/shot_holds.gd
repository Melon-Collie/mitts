class_name AIShotHolds
extends RefCounted

# Where a bot holds the puck for a charged release, and what each hold carries.
# A wrist shot fires from where the puck sits at the press, at the share of the
# bot's pace its load allows there (WristerLoad), so the carrier prices the holds
# the blade can put the puck in first and the state machine carries it to the
# winner. One instance per bot, configured from its own build: the carrier and
# the state machine read the same answers.
#
# Holds (solve_shot), index 0 the puck where it is: the best-loaded pocket
# (WristerPocket), and a reach out to either side of the shot line, which moves
# the whole tangent-cone geometry around a goalie in tight (the pull-across, the
# backhand tuck) at whatever pace the load leaves there. A pull costs its real
# time: the blade's travel, or the body's turn onto the cursor when the turn is
# what loads the puck (a forehand pulled beside the stick hip is loaded before
# the body moves). A pulled hold sits at the handling reach; the load reads its
# bearing, not its distance. All vectors are world XZ, offsets off the body.

# A puck this near the body's centre has no bearing to load from.
const MIN_OFFSET_M: float = 0.05

var is_left_handed: bool = false
var load_cfg: WristerLoad.Config = WristerLoad.Config.new()
var facing_cfg: FacingRules.Config = FacingRules.Config.new()
var unloaded_share: float = 0.6
var backhand_coefficient: float = 0.75
var handle_reach: float = 0.9
var blade_speed: float = 10.0
var facing_turn_rate: float = 6.0

# solve_shot's holds: offset, share of pace, pull time. A quarter-turn that is
# the pocket itself is not listed twice.
var offset: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var share: Array[float] = [1.0, 1.0, 1.0, 1.0]
var pull_s: Array[float] = [0.0, 0.0, 0.0, 0.0]
var count: int = 0
# solve_pass's hold and the share the press waits for.
var pass_offset: Vector2 = Vector2.ZERO
var pass_share: float = 0.0
# The hand of the last share_at.
var is_backhand: bool = false
# The last pocket solved (solve_shot, pocket).
var pocket_result := WristerPocket.Result.new()

var _facing := FacingRules.Result.new()
var _load := WristerLoad.Result.new()


func configure_from(ctx: RoleContext) -> void:
	is_left_handed = ctx.self_forehand_perp_sign > 0.0
	load_cfg = ctx.self_wrister_load
	facing_cfg = ctx.self_facing_rules
	unloaded_share = ctx.self_wrister_unloaded_share
	backhand_coefficient = ctx.self_backhand_power_coefficient
	handle_reach = ctx.self_handle_reach
	blade_speed = ctx.self_blade_speed
	facing_turn_rate = ctx.self_facing_turn_rate


# Share of pace a release along `aim` carries with the puck at `puck_offset` and
# the body facing `facing`, which a wrist shot freezes at the press.
func share_at(puck_offset: Vector2, aim: Vector2, facing: Vector2) -> float:
	if puck_offset.length() < MIN_OFFSET_M:
		is_backhand = false
		return WristerLoad.power_share(0.0, false, unloaded_share, backhand_coefficient)
	var s: float = WristerPocket.share_at(puck_offset, aim, facing, is_left_handed,
			load_cfg, unloaded_share, backhand_coefficient, _load)
	is_backhand = _load.is_backhand
	return s


# The best-loaded pocket for a release along `aim`, into pocket_result.
func pocket(aim: Vector2, velocity: Vector2, facing: Vector2) -> WristerPocket.Result:
	WristerPocket.solve(pocket_result, aim, velocity, facing, is_left_handed, load_cfg,
			facing_cfg, unloaded_share, backhand_coefficient, _facing, _load)
	return pocket_result


# The pocket's offset at the handling reach.
func pocket_offset() -> Vector2:
	return pocket_result.dir * handle_reach


# Where a charged pass needing `needed` of the pace holds the puck: where it is
# when that already carries the feed, else the pocket for it.
func solve_pass(aim: Vector2, puck_offset: Vector2, velocity: Vector2, facing: Vector2,
		needed: float) -> void:
	if share_at(puck_offset, aim, facing) >= needed:
		pass_offset = puck_offset
		pass_share = needed
		return
	pocket(aim, velocity, facing)
	pass_offset = pocket_offset()
	pass_share = minf(needed, pocket_result.power_share)


func solve_shot(aim: Vector2, puck_offset: Vector2, velocity: Vector2,
		facing: Vector2) -> void:
	offset[0] = puck_offset
	share[0] = share_at(puck_offset, aim, facing)
	pull_s[0] = 0.0
	pocket(aim, velocity, facing)
	_fill_pulled(1, pocket_result.dir, aim, pocket_result.facing, facing)
	count = 2
	for side: int in 2:
		var dir: Vector2 = aim.normalized().rotated(PI * 0.5 if side == 0 else -PI * 0.5)
		if dir.dot(pocket_result.dir) > 0.999:
			continue
		FacingRules.solve(_facing, facing, dir, velocity, false, false, facing_cfg)
		_fill_pulled(count, dir, aim, _facing.target, facing)
		count += 1


# A pulled hold along `dir`. The cursor on it turns the body toward `body`, but
# the press waits for that turn only when the turn is what loads the puck.
func _fill_pulled(k: int, dir: Vector2, aim: Vector2, body: Vector2,
		facing: Vector2) -> void:
	offset[k] = dir * handle_reach
	var blade_s: float = offset[k].distance_to(offset[0]) / maxf(blade_speed, 0.1)
	var share_now: float = share_at(offset[k], aim, facing)
	var share_turned: float = share_at(offset[k], aim, body)
	if share_now >= share_turned - 0.001 or facing.length_squared() < 0.0001:
		share[k] = share_now
		pull_s[k] = blade_s
		return
	share[k] = share_turned
	pull_s[k] = maxf(blade_s, absf(facing.angle_to(body)) / maxf(facing_turn_rate, 0.1))
