class_name AICarryRollout
extends RefCounted

# The carrier's near moves, skated: each of a fixed set of stick inputs held for
# HORIZON_S from the carrier's real velocity and facing, through the movement
# physics every skater runs (SkaterMovementRules.apply_movement), the facing the
# pose coordinator turns him through (FacingRules at his own drag, wound up at
# his turn rate's limit), and the
# body's rink and net clamps. What a move is priced on is where that leaves him.
#
# Moves are relative to `toward`, the direction of the carry's destination. A
# forward move faces where it skates; the brake faces the destination (the brake
# check); the cut back skates away from it facing it — backward.
#
# A move holds the skating stance while the turn onto its stick needs more than
# the upright edges give (STANCE_TURN_WINDOW_S); the brake never does, a pure stop.
#
# Not modelled: other bodies (contact and checks), the goalie's footprint, and
# the knockdown and shot states that suspend locomotion.
#
# One instance per carrier, results overwritten by every roll; read them before
# the next call.
#
# Where the application layer installs `native_factory` (the extension is built),
# each instance rolls through its own NativeCarryRollout instead — the same tick,
# held to this file by test_native_carry_rollout_parity.gd.

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

enum Move { STRAIGHT, SOFT_LEFT, SOFT_RIGHT, HARD_LEFT, HARD_RIGHT, BRAKE, CUT_BACK }
const MOVE_COUNT: int = 7

# How long a move is held. Half a second is too short to price an escape: from a standstill with a checker three metres off,
# every move is within his reach for that long, and what a cut buys only shows
# in the half-second after.
const HORIZON_S: float = 1.0
const TICKS: int = int(HORIZON_S * _PhysicsConstants.PHYSICS_TICK)
const DT: float = 1.0 / _PhysicsConstants.PHYSICS_TICK
# Path samples per move, at equal times through the horizon (the last is the end).
const SAMPLES: int = 3
const _TICKS_PER_SAMPLE: int = TICKS / SAMPLES

# Physics ticks per rollout step. 1 is the live integration exactly; 30 Hz
# drifts from it by up to ~20 cm and 0.3 m/s over the horizon, inside a stick's
# reach, for a quarter of the cost (test_carry_rollout.gd bounds the drift). Must
# divide _TICKS_PER_SAMPLE.
const STEP_TICKS: int = _PhysicsConstants.PHYSICS_TICK / 30
var step_ticks: int = STEP_TICKS

# Stick angles off `toward`. In world XZ a positive Vector2.rotated turns toward
# +X from −Z, which is the skater's right.
const SOFT_TURN_RAD: float = deg_to_rad(30.0)
const HARD_TURN_RAD: float = deg_to_rad(75.0)

# A move is priced from its first path sample on, so its cut must be on its line
# by then: the stance holds while that turn outruns the upright edges
# (AISteering.stance_cuts_onto). The agent skates the same read.
const STANCE_TURN_WINDOW_S: float = HORIZON_S / SAMPLES

# Returns a configured kernel, or null. Unset, every roll is GDScript.
static var native_factory: Callable = Callable()

# Index-matched by Move.
var stick: Array[Vector2] = []
var cursor: Array[Vector2] = []
var brake: Array[bool] = []
var end_pos := PackedVector3Array()
var end_vel := PackedVector3Array()
var end_facing := PackedVector2Array()
# The rate each move's facing ends turning at (rad/s, FacingRules.turn_rate's).
var end_turn_rate := PackedFloat64Array()
# The path met the boards or the cage and was held off them, as the body is.
var touched_boundary: Array[bool] = []
# MOVE_COUNT × SAMPLES positions, row-major by move.
var samples := PackedVector3Array()

var _facing_out := FacingRules.Result.new()
var _native: RefCounted = null
# The caps the kernel last loaded; caps are rebuilt, never edited, when a body changes.
var _native_caps: AISkaterCaps = null


func _init() -> void:
	stick.resize(MOVE_COUNT)
	cursor.resize(MOVE_COUNT)
	brake.resize(MOVE_COUNT)
	end_pos.resize(MOVE_COUNT)
	end_vel.resize(MOVE_COUNT)
	end_facing.resize(MOVE_COUNT)
	end_turn_rate.resize(MOVE_COUNT)
	touched_boundary.resize(MOVE_COUNT)
	samples.resize(MOVE_COUNT * SAMPLES)
	if native_factory.is_valid():
		_native = native_factory.call()
		# A binary built before the facing's turn rate rolls without it.
		if not _native.has_method(&"get_end_turn_rate"):
			_native = null


# Rolls every move. `toward` is world XZ; it need not be normalised but must not
# be zero. `facing` is the body's facing (world XZ, unit), `turn_rate` the rate
# it is turning at (rad/s, Vector2.angle_to's sense: the wire's
# facing_angular_velocity, a bearing's, negated).
func roll_all(pos: Vector3, vel: Vector3, facing: Vector2, toward: Vector2,
		caps: AISkaterCaps, has_puck: bool = true, turn_rate: float = 0.0) -> void:
	var t: Vector2 = toward.normalized()
	for m: int in MOVE_COUNT:
		_set_move(m, t)
	if _native != null and _native_loaded(caps):
		_native.roll_all(pos, vel, facing, t, has_puck, step_ticks, turn_rate)
		end_pos = _native.get_end_pos()
		end_vel = _native.get_end_vel()
		end_facing = _native.get_end_facing()
		end_turn_rate = _native.get_end_turn_rate()
		samples = _native.get_samples()
		var touched: int = _native.get_touched_mask()
		for m: int in MOVE_COUNT:
			touched_boundary[m] = (touched >> m) & 1 == 1
		return
	for m: int in MOVE_COUNT:
		_roll(m, pos, vel, facing, turn_rate, caps, has_puck)


# Whether the kernel holds `caps`, loading them if not. A caps it cannot load
# (a field renamed under it) drops the kernel for good: the GDScript is the
# reference, and a stale binary must not roll on half its tunables.
func _native_loaded(caps: AISkaterCaps) -> bool:
	if caps == _native_caps:
		return true
	if _native.configure(caps) != "":
		_native = null
		return false
	_native_caps = caps
	return true


func sample(move: int, k: int) -> Vector3:
	return samples[move * SAMPLES + k]


# How many of `move`'s samples come before its path reaches a crease or passes
# |z| = `max_abs_z`: SAMPLES for the whole move, 0 for none of it.
func reach_short_of_net(move: int, max_abs_z: float) -> int:
	for k: int in SAMPLES:
		var s: Vector3 = sample(move, k)
		if absf(s.z) > max_abs_z or CreaseRules.is_in_crease(Vector2(s.x, s.z)):
			return k
	return SAMPLES


# Where `move` is `reach` samples in (its end, at SAMPLES).
func reach_pos(move: int, reach: int) -> Vector3:
	return end_pos[move] if reach == SAMPLES else sample(move, reach - 1)


# Its velocity there: the end's, or the mean over that sample's leg from `from`,
# the roll's start (no velocity is kept between the ends).
func reach_vel(move: int, reach: int, from: Vector3) -> Vector3:
	if reach == SAMPLES:
		return end_vel[move]
	var prev: Vector3 = from if reach == 1 else sample(move, reach - 2)
	return (sample(move, reach - 1) - prev) * (SAMPLES / HORIZON_S)


func _set_move(m: int, t: Vector2) -> void:
	brake[m] = false
	match m:
		Move.STRAIGHT:
			stick[m] = t
		Move.SOFT_LEFT:
			stick[m] = t.rotated(-SOFT_TURN_RAD)
		Move.SOFT_RIGHT:
			stick[m] = t.rotated(SOFT_TURN_RAD)
		Move.HARD_LEFT:
			stick[m] = t.rotated(-HARD_TURN_RAD)
		Move.HARD_RIGHT:
			stick[m] = t.rotated(HARD_TURN_RAD)
		Move.BRAKE:
			stick[m] = t
			brake[m] = true
		Move.CUT_BACK:
			stick[m] = -t
	cursor[m] = t if m == Move.BRAKE or m == Move.CUT_BACK else stick[m]


# One tick in the live order: the controller's input step (the movement physics
# on the facing the body has, then the facing step on the new velocity), then
# the body's integration and containment, which the controller runs ahead of.
#
# Between the corner arcs only the side boards bound the ice, and the cages sit
# past the goal lines, so a body there further from the side boards than its
# radius (the shield's probe, for the shield) skips each exactly.
func _roll(m: int, pos: Vector3, vel: Vector3, facing: Vector2, turn_rate: float,
		caps: AISkaterCaps, has_puck: bool) -> void:
	var cfg: SkaterMovementRules.MovementConfig = caps.movement
	var braking: bool = brake[m]
	# Skated as the bot skates it (AIBotMechanics.braked_stick): a brake is a
	# stop, its stick dropped, never a shuffle.
	var move: Vector2 = Vector2.ZERO if braking else stick[m]
	var cur: Vector2 = cursor[m]
	var drag: float = caps.facing_drag_speed_braking if braking else caps.facing_drag_speed
	var radius: float = caps.body_radius
	var dt: float = DT * step_ticks
	var contain_x: float = GameRules.INNER_HALF_WIDTH - radius
	var shield_x: float = GameRules.INNER_HALF_WIDTH - caps.board_shield_probe
	var upright: float = cfg.turn_accel * cfg.lateral_grip
	var p: Vector3 = pos
	var v: Vector3 = vel
	var f: Vector2 = facing
	var rate: float = turn_rate
	var touched: bool = false
	var stance: bool = false
	for i: int in range(step_ticks - 1, TICKS, step_ticks):
		stance = not braking and AISteering.stance_cuts_onto(move, Vector2(v.x, v.z), upright,
				STANCE_TURN_WINDOW_S, stance)
		v = SkaterMovementRules.apply_movement(v, move, atan2(-f.x, -f.y), has_puck,
				braking, dt, cfg, SkaterMovementRules.Posture.STANCE if stance
						else SkaterMovementRules.Posture.UPRIGHT)
		v.y = 0.0
		var between_arcs: bool = absf(p.z) <= GameRules.CORNER_CENTER_Z
		var turned: Vector2 = _face(f, cur, v, p, braking, stance, drag * dt, caps, has_puck,
				has_puck and not (between_arcs and absf(p.x) <= shield_x))
		rate = FacingRules.turn_rate(rate, f.angle_to(turned) / dt, caps.facing_turn_accel_max, dt)
		f = f.rotated(rate * dt)
		p += v * dt
		if absf(p.z) <= GameRules.CORNER_CENTER_Z and absf(p.x) <= contain_x:
			if (i + 1) % _TICKS_PER_SAMPLE == 0:
				samples[m * SAMPLES + (i + 1) / _TICKS_PER_SAMPLE - 1] = p
			continue
		var xz := Vector2(p.x, p.z)
		var held: Vector2 = GameRules.push_out_of_net(
				GameRules.clamp_to_rink_inner(xz, radius), radius)
		if xz.distance_squared_to(held) > 1e-6:
			var out_dir: Vector2 = (held - xz).normalized()
			var vxz := Vector2(v.x, v.z)
			var into: float = vxz.dot(out_dir)
			if into < 0.0:
				vxz -= into * out_dir
				v.x = vxz.x
				v.z = vxz.y
			p.x = held.x
			p.z = held.y
			touched = true
		if (i + 1) % _TICKS_PER_SAMPLE == 0:
			samples[m * SAMPLES + (i + 1) / _TICKS_PER_SAMPLE - 1] = p
	end_pos[m] = p
	end_vel[m] = v
	end_facing[m] = f
	end_turn_rate[m] = rate
	touched_boundary[m] = touched


# SkaterPoseCoordinator.apply_facing for a cursor held along `cur`: the facing
# rule's target (a carrier's pivoting at its carry stop, turned along the boards
# for one on them), a chord lerp toward it, or turned by angle on the cursor's
# side through a turn round, a carrier's yielding to a cursor round its forehand
# — where the turn asks to be, before its wind-up.
func _face(f: Vector2, cur: Vector2, v: Vector3, p: Vector3, braking: bool, stance: bool,
		step: float, caps: AISkaterCaps, has_puck: bool, shield: bool) -> Vector2:
	var rules: FacingRules.Config = caps.facing_rules
	var lefty: bool = caps.is_left_handed
	FacingRules.solve(_facing_out, f, cur, Vector2(v.x, v.z), braking, stance, lefty,
			caps.carry_facing_rules if has_puck else rules)
	var behind: bool = absf(f.angle_to(cur)) >= FacingRules.reach_edge(rules, f, cur, lefty)
	var target: Vector2 = _facing_out.target
	if shield:
		target = BoardPlayRules.board_shield_facing(target, BoardPlayRules.board_proximity(
				Vector2(p.x, p.z), caps.board_shield_probe), caps.board_shield_max_rad)
	var turned: Vector2
	if behind or absf(f.angle_to(target)) >= FacingRules.reach_edge(rules, f, target, lefty):
		turned = f.rotated(FacingRules.turn_round_angle(f, target, cur) * minf(step, 1.0))
	else:
		turned = f.lerp(target, step).normalized()
	if has_puck:
		turned = FacingRules.yield_on_forehand(turned, cur, lefty, caps.carry_facing_rules)
	return turned
