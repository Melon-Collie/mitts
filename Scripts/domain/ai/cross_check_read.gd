class_name AICrossCheckRead
extends RefCounted

# When a bot's cross-check is worth its stick, and where to aim it, read from
# what the bot can see. The push is the one the host would land
# (CrossCheckRules.victim_dv — the same function, so a change to the model moves
# the prediction with it) on the man as he stands now: his facing, posture,
# stagger and intent. Moving him is worth it:
# - at our net, when he hides the release from our goalie (the goalie's own
#   silhouette and sightline, GoalieBehaviorRules.ScreenConfig) and would not
#   once moved;
# - on a loose puck, when he beats us to it now and would not once moved, our
#   own stick's absence through the push charged to us.
# Pure/static, no allocation.

# A shoved man drifts on the push this long before he can redirect against it:
# the read-and-redirect delay a defender takes on a carrier's cut.
const PUSHED_REACTION_S: float = AICarrySpace.EVADE_REACTION_S
# The shover's stick is out of play from the press until it is back.
const STICK_OUT_S: float = CrossCheckRules.THROW_S + CrossCheckRules.RECOVER_S
# A shove is tried along the way that matters and turned off it by 30° and 60°
# either side (aim_turn): a push along a man's blades moves him furthest and one
# across them least, so the best aim trades the two and the tries sample it.
const AIM_TRIES: int = 5
const _AIM_TURN_STEP_RAD: float = PI / 6.0

static var _league: SkaterMovementRules.MovementConfig = SkaterMovementRules.league_config()
static var _check_cfg := BodyCheckRules.Config.new()


# The Δv (m/s) a shove along `push_dir` (unit XZ) from a shover of `shover_weight`
# pushing at `shover_thrust` lands on `man`; `man_caps` null reads a league body.
static func predicted_dv(shover_weight: float, shover_thrust: float,
		man: SkaterNetworkState, man_caps: AISkaterCaps, push_dir: Vector2) -> float:
	var posture: int = SkaterMovementRules.posture_of(man.stance_active, man.hit_committed)
	var lateral_grip: float = man_caps.lateral_grip if man_caps != null else 1.0
	var edge: float = CrossCheckRules.edge_accel(_league, posture,
			BodyCheckRules.grip_mult(man.stagger_timer, _check_cfg)) * lateral_grip
	var drive: float = CrossCheckRules.drive_accel(_league, posture,
			man_thrust(man_caps) * BodyCheckRules.thrust_mult(man.stagger_timer, _check_cfg))
	return CrossCheckRules.victim_dv(shover_weight, shover_thrust,
			man_caps.weight if man_caps != null else 1.0, push_dir, man.facing, edge,
			man.move_intent, drive)


# The `i`th try's turn off the want (rad): 0, then +-30°, then +-60°.
static func aim_turn(i: int) -> float:
	return floorf((i + 1) * 0.5) * _AIM_TURN_STEP_RAD * (1.0 if i % 2 == 1 else -1.0)


# Off the goalie's sightline to the puck the shortest way (unit XZ): square
# across it, toward the side `man_pos` already stands on.
static func off_sightline_dir(man_pos: Vector3, goalie_pos: Vector3,
		puck_pos: Vector3) -> Vector2:
	var line := Vector2(puck_pos.x - goalie_pos.x, puck_pos.z - goalie_pos.z).normalized()
	var off := Vector2(man_pos.x - goalie_pos.x, man_pos.z - goalie_pos.z)
	var side: Vector2 = line.orthogonal()
	return side if side.dot(off) >= 0.0 else -side


static func man_thrust(man_caps: AISkaterCaps) -> float:
	return man_caps.max_accel if man_caps != null else GameRules.DEFAULT_SKATER_THRUST_M_S2


# The stride `thrust` (m/s²) a man has left once a shove of `dv` has landed: the
# stagger it inflicts, at its start.
static func staggered_thrust(dv: float, thrust: float) -> float:
	return thrust * BodyCheckRules.thrust_mult(
			BodyCheckRules.stagger_seconds_from_impulse(dv, _check_cfg), _check_cfg)


# How far (m) a shove of `dv` moves a man who pushes back at `thrust`: the drift
# before he reacts, then the stop his own stride makes against it, slowed by the
# stagger the shove itself lands.
static func displacement_m(dv: float, thrust: float) -> float:
	if dv <= 0.0:
		return 0.0
	var brake: float = maxf(staggered_thrust(dv, thrust), 0.1)
	return dv * PUSHED_REACTION_S + dv * dv / (2.0 * brake)


# Whether `body` stands on the goalie's sightline to the release: between his
# eyes and the puck, clear of both ends (the shooter, and a body on his own
# eyes), and within the body's half-width at the height the line crosses it —
# the test GoalieBehaviorRules.screen_peek_offset makes of each body
# (test_cross_check_read.gd holds the two together).
static func hides_release(body: Vector3, goalie_pos: Vector3, puck_pos: Vector3,
		cfg: GoalieBehaviorRules.ScreenConfig) -> bool:
	var px: float = puck_pos.x - goalie_pos.x
	var pz: float = puck_pos.z - goalie_pos.z
	var p_len: float = sqrt(px * px + pz * pz)
	if p_len <= cfg.min_along:
		return false
	var vhx: float = px / p_len
	var vhz: float = pz / p_len
	var wx: float = body.x - goalie_pos.x
	var wz: float = body.z - goalie_pos.z
	var along: float = wx * vhx + wz * vhz
	if along <= cfg.min_along or along >= p_len - cfg.min_along:
		return false
	var eye_y: float = goalie_pos.y + cfg.eye_height
	var sight_y: float = eye_y + along / p_len * (puck_pos.y - eye_y)
	return absf(wx * -vhz + wz * vhx) < GoalieBehaviorRules.screener_half_width_at(sight_y, cfg)


# A screen the shove clears: he hides the release now, and moved
# `displacement` along `push_dir` he would not.
static func clears_screen(man_pos: Vector3, push_dir: Vector2, displacement: float,
		goalie_pos: Vector3, puck_pos: Vector3, cfg: GoalieBehaviorRules.ScreenConfig) -> bool:
	if not hides_release(man_pos, goalie_pos, puck_pos, cfg):
		return false
	var moved := Vector3(man_pos.x + push_dir.x * displacement, man_pos.y,
			man_pos.z + push_dir.y * displacement)
	return not hides_release(moved, goalie_pos, puck_pos, cfg)


# A loose-puck race the shove turns: he gets there first now (`his_now_s`), and
# once shoved (`his_after_s`) he no longer beats us, our stick back down first.
static func takes_the_race(ours_s: float, his_now_s: float, his_after_s: float) -> bool:
	return his_now_s < ours_s and maxf(ours_s, STICK_OUT_S) < his_after_s
