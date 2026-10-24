class_name AIBotMechanics

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# League-default execution constants a bot's body runs on: the evaluators price
# them and SkaterAgentStateMachine executes them, so they live below both. A leaf
# (GameRules, the physics tick and the movement rules only).

# CARRY blade aim distance (m forward in goal direction) — the cursor ring the
# carry dangle, the pre-aim targets, and the arc-step all live on. 1.3 m is ~80%
# of the league blade orbit (stick + blade = 1.6 m), INSIDE reach, so the blade
# holds AT the cursor with slack in every direction, and the model's assumed
# carried-puck position (self + this × forward) is where the blade can really
# hold it.
#
# Anything denominated in metres ON THIS RING is really an angle: the state
# machine's stickhandle offset must be rescaled with it
# (aim errors are stored in radians on BotSkillProfile so they don't move).
const CARRY_BLADE_AIM_FORWARD_M: float = 1.3

# Blade-reach radius. Inside it the stick can reach the puck where it is, so the
# blade aims at its CURRENT position rather than the lead intercept (which rides
# the blade past a puck at our feet); steering still uses the lead. Stick + blade
# + a feel buffer so the snap kicks in just before the blade arrives.
#
# BLADE_REACH_M is the league default, for consumers that don't know whose reach
# to use (the PRESSURE role's gap geometry). A bot's own reach is the state
# machine's `_blade_reach`, scaled to its build in apply_capabilities.
const BLADE_REACH_BUFFER_M: float = 0.2
const BLADE_REACH_M: float = (
		GameRules.DEFAULT_STICK_LENGTH_M
		+ GameRules.DEFAULT_BLADE_LENGTH_M
		+ BLADE_REACH_BUFFER_M)

# The agent's SHOOT_PRESSED and charged PASS_PRESSED hold shoot_held for this many
# ticks while the blade sweeps from wind_up_start to aim_target, then release.
# Power rides input.bot_wrister_power_t, so the sweep is cosmetic, but the
# DURATION is the real commit→release delay: BOT_WRISTER_LOOKAHEAD_S is derived
# from it so the scorer's goalie prediction stays honest.
#
# ~125 ms: the keeper's reaction (~0.13 s leg / 0.18 s arm) has barely fired, so a
# set, squared goalie still covers a straight-on range shot while lateral lag and
# point-blank arm-deploy gaps stay open.
const BOT_WRISTER_CHARGE_TICKS: int = _PhysicsConstants.PHYSICS_TICK / 8   # ~125 ms

# Lookahead for scoring a wrister at COMMIT time — from the carrier picking SHOOT
# to the puck leaving the blade: the pre-aim's residual convergence (short, since
# _carry_aim_track_fire keeps facing pre-tracked during CARRY) plus the charge.
# Projects both the shooter's release position and the goalie / opponents.
const BOT_PRE_AIM_BUFFER_S: float = 0.01
const BOT_WRISTER_LOOKAHEAD_S: float = (
		float(BOT_WRISTER_CHARGE_TICKS) / _PhysicsConstants.PHYSICS_TICK + BOT_PRE_AIM_BUFFER_S)

# Base puck-protect reach: how far a carrier holds the puck off his body while
# handling. The blade lever scales it (a longer reach protects it further out /
# threads a tighter seam) — callers pass the scaled value; this is the league
# default.
const EVADE_CARRY_HANDLE_M: float = 0.9

# The league wrister's release speed (m/s; Puck.release consumes `direction ×
# power` as linear velocity) — the shot speed a read assumes for a shooter whose
# build it doesn't know.
const WRISTER_SHOT_SPEED_M_S: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S


# How far inside the boards the carry mouse target is clamped
# (GameRules.clamp_to_rink_inner). The blade IK chases the mouse, and a target at
# the kickplate slams the stick into the wall and knocks the carried puck loose;
# one blade length keeps the whole blade off the wall while still working the
# puck tight along the boards.
const CARRY_BLADE_WALL_MARGIN_M: float = GameRules.DEFAULT_BLADE_LENGTH_M

# The stick a bot's input skates. A bot's brake means stop, while its stick still
# names where it is steering; slow, under the brake, that stick would make the
# stop a shuffle (SkaterMovementRules.is_shuffle), which a bot decides on only
# with `shuffle` (a wound-up one-timer stepping onto the feed's line).
static func braked_stick(stick: Vector2, brake: bool, velocity: Vector3,
		shuffle: bool = false) -> Vector2:
	if shuffle:
		return stick
	if brake and Vector2(velocity.x, velocity.z).length() <= SkaterMovementRules.SHUFFLE_MAX_SPEED:
		return Vector2.ZERO
	return stick
