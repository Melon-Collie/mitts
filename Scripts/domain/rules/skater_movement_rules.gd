class_name SkaterMovementRules

# Pure skating physics: current state + input + tuning config → new velocity.
# The caller (SkaterController) owns the state-machine guards (slapper wind-up
# etc.); this function only does the physics.
#
# Above GRIP_MIN_SPEED the travel direction stands in for the blade heading —
# blades glide along their length, so velocity IS where the skates point. The
# stick is then resolved against that heading rather than applied as a free
# thrust: the component along travel is a stride (power-limited, so it fades
# toward top speed), the component against travel is a skid (a skater must stop
# before pushing the other way), and the stick's angle off travel turns the
# velocity at an edge-limited rate (turn radius v²/(turn_accel·grip)). The brake
# is a hockey stop whatever the stick says. Below GRIP_MIN_SPEED there is no
# heading to respect and the push is free in any direction (first steps,
# net-front shuffles).

# How the skater is loaded over the skates. The caller resolves which one holds;
# a committed check wins over the stance.
enum Posture { UPRIGHT, STANCE, COMMIT }

class MovementConfig:
	var thrust: float = 0.0                      # standing-start push, m/s²
	# Speed (m/s) above which the push is power-limited: drive = thrust·knee/speed.
	var power_knee_speed: float = 0.0
	var friction: float = 0.0                    # glide: constant decel, m/s²
	var friction_drag: float = 0.0               # glide: velocity-proportional decel (m/s² per m/s)
	var max_speed: float = 0.0                   # forward skating top speed
	var move_deadzone: float = 0.0               # stick deadzone
	var stop_decel: float = 0.0                  # hockey-stop deceleration, m/s²
	# Fraction of stop_decel the skid delivers when the stick opposes travel
	# without the brake — the dedicated stop stays the better stop.
	var reverse_skid_fraction: float = 0.0
	# Centripetal acceleration of a striding turn at full stick, m/s² (× lateral_grip).
	var turn_accel: float = 0.0
	var max_turn_rate: float = 0.0               # rad/s ceiling, binds only at low speed
	var puck_carry_speed_multiplier: float = 0.0 # max speed reduction while carrying
	var backward_thrust_multiplier: float = 0.0  # stride scale when pushing against facing
	var crossover_thrust_multiplier: float = 0.0 # stride scale when pushing perpendicular to facing
	# Top-speed scale when TRAVEL runs against facing (backward skating).
	var backward_max_speed_multiplier: float = 1.0
	# Edge grip — scales turn authority (every posture), so
	# the emergent turn radius v²/(turn_accel·grip) is what agility (and later
	# the skate-profile gear) owns. Straight-line drive and stops are untouched.
	var lateral_grip: float = 1.0
	# Posture.STANCE — low and loaded: the edges bite harder, the strides chop.
	var stance_grip_mult: float = 1.0
	# m/s² of speed bled per m/s² of centripetal acceleration beyond what the
	# upright edges hold: an edge dug harder than a clean carve skids.
	var stance_scrape: float = 0.0
	var stance_stride_mult: float = 1.0          # along-travel stride scale
	var stance_max_speed_mult: float = 1.0       # where the stance's stride stops adding
	var stance_shuffle_mult: float = 1.0         # sideways free push below GRIP_MIN_SPEED
	# Posture.COMMIT — loaded on a shoulder for a check, off the edges.
	var commit_grip_mult: float = 1.0
	var commit_stride_mult: float = 1.0

# Below this horizontal speed (m/s) travel carries no usable heading — the
# velocity direction is numerically unstable — so the push is free in any
# direction.
const GRIP_MIN_SPEED: float = 0.5
# Within this many radians of dead-opposite the stride turn fades out, so a
# stick held straight back skids straight instead of picking a side by the
# sign of a rounding error.
const SKID_TURN_TAPER: float = PI * 0.25


# `grip_scale` multiplies the edge grip from outside the config (the body-check
# stagger); 1.0 is untouched.
static func apply_movement(
		current_velocity: Vector3,
		move_input: Vector2,
		facing_rotation_y: float,
		has_puck: bool,
		brake: bool,
		delta: float,
		cfg: MovementConfig,
		posture: Posture = Posture.UPRIGHT,
		grip_scale: float = 1.0) -> Vector3:
	var velocity: Vector3 = current_velocity
	var stride_mult: float = 1.0
	var cap_mult: float = 1.0
	var posture_grip: float = 1.0
	if posture == Posture.STANCE:
		stride_mult = cfg.stance_stride_mult
		cap_mult = cfg.stance_max_speed_mult
		posture_grip = cfg.stance_grip_mult
	elif posture == Posture.COMMIT:
		stride_mult = cfg.commit_stride_mult
		posture_grip = cfg.commit_grip_mult
	var has_input: bool = move_input.length() > cfg.move_deadzone
	var facing_dir := Vector2(-sin(facing_rotation_y), -cos(facing_rotation_y))

	# Stride scale by how the push lines up with facing (forward > crossover >
	# backward stride).
	var thrust_scale: float = 1.0
	if has_input:
		var move_dot: float = facing_dir.dot(move_input.normalized())
		if move_dot >= 0.0:
			thrust_scale = lerpf(cfg.crossover_thrust_multiplier, 1.0, move_dot)
		else:
			thrust_scale = lerpf(cfg.backward_thrust_multiplier, cfg.crossover_thrust_multiplier, move_dot + 1.0)

	var horiz := Vector2(velocity.x, velocity.z)
	var speed: float = horiz.length()
	if speed <= GRIP_MIN_SPEED:
		if brake:
			horiz = horiz.move_toward(Vector2.ZERO, cfg.stop_decel * delta)
		else:
			if has_input:
				var push_mult: float = stride_mult
				if posture == Posture.STANCE:
					var across: float = facing_dir.cross(move_input.normalized())
					push_mult = lerpf(cfg.stance_stride_mult, cfg.stance_shuffle_mult, across * across)
				horiz += move_input * (cfg.thrust * push_mult * thrust_scale * delta)
			horiz = horiz.move_toward(Vector2.ZERO,
					(cfg.friction + cfg.friction_drag * horiz.length()) * delta)
		velocity.x = horiz.x
		velocity.z = horiz.y
		return velocity

	var travel: Vector2 = horiz / speed
	var turn: float = 0.0
	if brake:
		speed = maxf(speed - cfg.stop_decel * delta, 0.0)
	else:
		var scrape: float = 0.0
		if has_input:
			var stick: float = minf(move_input.length(), 1.0)
			var steer: float = travel.angle_to(move_input)
			var steer_abs: float = absf(steer)
			var edge_grip: float = cfg.lateral_grip * grip_scale
			var taper: float = minf((PI - steer_abs) / SKID_TURN_TAPER, 1.0)
			var turn_rate: float = minf(cfg.turn_accel * edge_grip * posture_grip * stick / speed,
					cfg.max_turn_rate) * taper
			turn = signf(steer) * minf(turn_rate * delta, steer_abs)
			if posture == Posture.STANCE:
				var upright_rate: float = minf(cfg.turn_accel * edge_grip * stick / speed,
						cfg.max_turn_rate) * taper
				var upright_turn: float = minf(upright_rate * delta, steer_abs)
				scrape = cfg.stance_scrape * (absf(turn) - upright_turn) / delta * speed
			var par: float = move_input.dot(travel)
			if par >= 0.0:
				# Over-max speed from external sources (body-check boost, entering the
				# stance at speed) is preserved: the stride stops adding, nothing
				# clamps down.
				var effective_max: float = cfg.max_speed * cap_mult
				if has_puck:
					effective_max *= cfg.puck_carry_speed_multiplier
				var backward: float = clampf(-travel.dot(facing_dir), 0.0, 1.0)
				effective_max *= lerpf(1.0, cfg.backward_max_speed_multiplier, backward)
				var applied_thrust: float = cfg.thrust * stride_mult
				var drive: float = minf(applied_thrust, applied_thrust * cfg.power_knee_speed / speed)
				var driven: float = speed + par * drive * thrust_scale * delta
				speed = minf(driven, maxf(speed, effective_max))
			else:
				speed = maxf(speed + par * cfg.stop_decel * cfg.reverse_skid_fraction * delta, 0.0)
		speed = maxf(speed - (cfg.friction + cfg.friction_drag * speed + scrape) * delta, 0.0)
	horiz = travel.rotated(turn) * speed
	velocity.x = horiz.x
	velocity.z = horiz.y
	return velocity


# The posture the replicated bits name. A committed check wins over the stance;
# every path that integrates a skater from its broadcast state resolves through
# here, so the live sim, the client render and the host rewind agree.
static func posture_of(stance_active: bool, hit_committed: bool) -> Posture:
	if hit_committed:
		return Posture.COMMIT
	if stance_active:
		return Posture.STANCE
	return Posture.UPRIGHT


# Caller-owned result for integrate_forward (fill-a-scratch, no per-call alloc).
class ForwardResult:
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO


# Forward-integrate a skater's position + velocity from a snapshot through `ticks`
# physics steps of `dt`, driving the SAME apply_movement physics with the skater's
# broadcast movement intent (move_input / brake / posture). This is the shared
# primitive behind stage-3 remote forward-prediction: the client calls it to render
# a remote at (near) present instead of a full interp_delay in the past, and the
# HOST calls it — with the identical snapshot base + intent — to reconstruct that
# same predicted position when validating lag-comp claims, so render stays == rewind.
# Sharing one primitive is what guarantees the two agree; any divergence would
# reopen the contested-pickup desync that render == rewind fixed.
#
# Free-space integration (position += velocity·dt per tick): board/net clamps and
# facing evolution are deliberately omitted. Facing affects only the stride-
# alignment scale and the backward top speed, and turns slowly over the
# ~interp_delay span, so it is held constant here; the caller renders facing via the existing angular-velocity
# extrapolation. The residual vs the host's true integration is corrected by the
# next snapshot — what must match exactly is client-render vs host-rewind, and both
# run THIS function on the same inputs. Fills the caller-owned `result`.
# `stagger_timer` / `body_check_cfg` (optional): the snapshot's replicated
# body-check stagger, applied as the live sim's per-tick thrust and grip
# penalties (BodyCheckRules.thrust_mult / grip_mult of the tick-decayed
# remaining timer) so a recently-checked skater predicts its honest reduced
# acceleration and turning — right after checks is exactly when follow-up
# contests cluster. Both the client render and the host claim rewind pass the
# SAME snapshot field through the same formula, so render == rewind holds.
# cfg.thrust is transiently scaled and restored (the caller may pass a shared
# cached config). Omit (0 / null) to integrate unstaggered.
static func integrate_forward(
		position: Vector3,
		velocity: Vector3,
		move_input: Vector2,
		facing_rotation_y: float,
		has_puck: bool,
		brake: bool,
		posture: Posture,
		cfg: MovementConfig,
		dt: float,
		ticks: int,
		intent_decay_ticks: int,
		result: ForwardResult,
		stagger_timer: float = 0.0,
		body_check_cfg: BodyCheckRules.Config = null) -> void:
	var pos: Vector3 = position
	var vel: Vector3 = velocity
	var n: int = maxi(ticks, 0)
	var base_thrust: float = cfg.thrust
	for i in n:
		# Rocket-League-style input decay: a held intent is less likely to still be
		# held further into the prediction, so fade the assumed move_input linearly to
		# 0 over intent_decay_ticks. The far ticks coast on friction instead of
		# thrusting in a possibly-stale direction — this is what tames overshoot when
		# the real player CUTS mid-window. Both the client render and the host claim
		# rewind pass the SAME shared constant, so the decay is identical on both and
		# render == rewind holds. 0 = no decay (full intent every tick, the raw form).
		var decayed_input: Vector2 = move_input
		if intent_decay_ticks > 0:
			decayed_input = move_input * clampf(1.0 - float(i) / float(intent_decay_ticks), 0.0, 1.0)
		var grip_scale: float = 1.0
		if stagger_timer > 0.0 and body_check_cfg != null:
			# Mirror the live order: the sim decays the timer, THEN scales from the
			# decayed value — tick i uses stagger after i+1 decays.
			var remaining: float = maxf(stagger_timer - float(i + 1) * dt, 0.0)
			cfg.thrust = base_thrust * BodyCheckRules.thrust_mult(remaining, body_check_cfg)
			grip_scale = BodyCheckRules.grip_mult(remaining, body_check_cfg)
		vel = apply_movement(vel, decayed_input, facing_rotation_y, has_puck, brake, dt, cfg,
				posture, grip_scale)
		pos += vel * dt
	cfg.thrust = base_thrust
	result.position = pos
	result.velocity = vel
