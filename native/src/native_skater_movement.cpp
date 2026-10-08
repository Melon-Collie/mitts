#include "native_skater_movement.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace mitts {

// SkaterMovementRules.GRIP_MIN_SPEED / TIGHT_TURN_TAPER / SKID_TURN_TAPER.
static constexpr double GRIP_MIN_SPEED = 0.5;
static constexpr double TIGHT_TURN_TAPER = Math_PI * 0.25;
static constexpr double SKID_TURN_TAPER = Math_PI * 0.25;

String NativeSkaterMovement::configure(Object *movement_config) {
	ERR_FAIL_NULL_V(movement_config, String("null config"));
	String missing;
	// Every tunable is a float on MovementConfig, so NIL can only mean the
	// property doesn't exist (renamed/removed field).
#define X(name)                                                             \
	{                                                                       \
		const Variant v = movement_config->get(StringName(#name));          \
		if (v.get_type() == Variant::NIL) {                                 \
			missing += #name " ";                                           \
		} else {                                                            \
			cfg.name = (double)v;                                           \
		}                                                                   \
	}
	MITTS_MOVEMENT_TUNABLES(X)
#undef X
	return missing;
}

void NativeSkaterMovement::set_stagger_params(double max_stagger_seconds, double max_thrust_penalty) {
	stagger_max_seconds = max_stagger_seconds;
	stagger_max_thrust_penalty = max_thrust_penalty;
}

// BodyCheckRules.thrust_mult, on the two stored fields.
static double stagger_thrust_mult(double stagger_timer, double max_seconds, double max_penalty) {
	if (stagger_timer <= 0.0 || max_seconds <= 0.0) {
		return 1.0;
	}
	const double frac = CLAMP(stagger_timer / max_seconds, 0.0, 1.0);
	return 1.0 - frac * max_penalty;
}

Vector3 NativeSkaterMovement::apply_movement_internal(
		const Vector3 &current_velocity,
		const Vector2 &move_input,
		double facing_rotation_y,
		bool has_puck, bool brake, double delta, bool sprint_active,
		double thrust_override) const {
	Vector3 velocity = current_velocity;
	const double sprint_thrust = sprint_active ? cfg.sprint_thrust_multiplier : 1.0;
	const double sprint_max = sprint_active ? cfg.sprint_max_speed_multiplier : 1.0;
	const double applied_thrust = thrust_override * sprint_thrust;
	const bool has_input = (double)move_input.length() > cfg.move_deadzone;
	const Vector2 facing_dir(-Math::sin(facing_rotation_y), -Math::cos(facing_rotation_y));

	double thrust_scale = 1.0;
	if (has_input) {
		const double move_dot = (double)facing_dir.dot(move_input.normalized());
		if (move_dot >= 0.0) {
			thrust_scale = Math::lerp(cfg.crossover_thrust_multiplier, 1.0, move_dot);
		} else {
			thrust_scale = Math::lerp(cfg.backward_thrust_multiplier,
					cfg.crossover_thrust_multiplier, move_dot + 1.0);
		}
	}

	Vector2 horiz(velocity.x, velocity.z);
	double speed = horiz.length();
	if (speed <= GRIP_MIN_SPEED) {
		if (brake) {
			horiz = horiz.move_toward(Vector2(), (real_t)(cfg.stop_decel * delta));
		} else {
			if (has_input) {
				horiz += move_input * (real_t)(applied_thrust * thrust_scale * delta);
			}
			horiz = horiz.move_toward(Vector2(),
					(real_t)((cfg.friction + cfg.friction_drag * (double)horiz.length()) * delta));
		}
		velocity.x = horiz.x;
		velocity.z = horiz.y;
		return velocity;
	}

	const Vector2 travel = horiz / (real_t)speed;
	const double stick = MIN((double)move_input.length(), 1.0);
	const double steer = has_input ? (double)travel.angle_to(move_input) : 0.0;
	const double steer_abs = Math::abs(steer);
	double turn = 0.0;
	if (brake) {
		double w = 0.0;
		if (has_input) {
			w = MIN(steer_abs / MAX(cfg.tight_turn_align_angle, 0.001), 1.0);
			if (steer_abs > Math_PI * 0.5) {
				w *= MAX(0.0, 1.0 - (steer_abs - Math_PI * 0.5) / TIGHT_TURN_TAPER);
			}
		}
		if (w > 0.0) {
			const double tight_rate = MIN(
					cfg.turn_accel * cfg.tight_turn_multiplier * cfg.lateral_grip * stick / speed,
					cfg.max_turn_rate);
			turn = SIGN(steer) * MIN(tight_rate * delta, steer_abs);
		}
		speed = MAX(speed - Math::lerp(cfg.stop_decel, cfg.tight_turn_decel, w) * delta, 0.0);
	} else {
		if (has_input) {
			const double turn_rate = MIN(cfg.turn_accel * cfg.lateral_grip * stick / speed,
					cfg.max_turn_rate) * MIN((Math_PI - steer_abs) / SKID_TURN_TAPER, 1.0);
			turn = SIGN(steer) * MIN(turn_rate * delta, steer_abs);
			const double par = (double)move_input.dot(travel);
			if (par >= 0.0) {
				const double base_max = cfg.max_speed * sprint_max;
				double carry_mult = cfg.puck_carry_speed_multiplier;
				if (sprint_active) {
					carry_mult = Math::lerp(carry_mult, 1.0, cfg.sprint_carry_penalty_bypass);
				}
				double effective_max = has_puck ? base_max * carry_mult : base_max;
				const double backward = CLAMP(-(double)travel.dot(facing_dir), 0.0, 1.0);
				effective_max *= Math::lerp(1.0, cfg.backward_max_speed_multiplier, backward);
				const double drive = MIN(applied_thrust, applied_thrust * cfg.power_knee_speed / speed);
				const double driven = speed + par * drive * thrust_scale * delta;
				speed = MIN(driven, MAX(speed, effective_max));
			} else {
				speed = MAX(speed + par * cfg.stop_decel * cfg.reverse_skid_fraction * delta, 0.0);
			}
		}
		speed = MAX(speed - (cfg.friction + cfg.friction_drag * speed) * delta, 0.0);
	}
	horiz = travel.rotated((real_t)turn) * (real_t)speed;
	velocity.x = horiz.x;
	velocity.z = horiz.y;
	return velocity;
}

Vector3 NativeSkaterMovement::apply_movement(
		const Vector3 &current_velocity,
		const Vector2 &move_input,
		double facing_rotation_y,
		bool has_puck, bool brake, double delta, bool sprint_active) const {
	return apply_movement_internal(current_velocity, move_input, facing_rotation_y,
			has_puck, brake, delta, sprint_active, cfg.thrust);
}

Vector3 NativeSkaterMovement::apply_movement_with_thrust(
		const Vector3 &current_velocity,
		const Vector2 &move_input,
		double facing_rotation_y,
		bool has_puck, bool brake, double delta, bool sprint_active,
		double thrust) const {
	return apply_movement_internal(current_velocity, move_input, facing_rotation_y,
			has_puck, brake, delta, sprint_active, thrust);
}

void NativeSkaterMovement::integrate_forward(
		const Vector3 &position,
		const Vector3 &velocity,
		const Vector2 &move_input,
		double facing_rotation_y,
		bool has_puck, bool brake, bool sprint_active,
		double dt, int64_t ticks, int64_t intent_decay_ticks,
		double stagger_timer, bool use_stagger) {
	Vector3 pos = position;
	Vector3 vel = velocity;
	const int64_t n = MAX(ticks, (int64_t)0);
	for (int64_t i = 0; i < n; i++) {
		Vector2 decayed_input = move_input;
		if (intent_decay_ticks > 0) {
			decayed_input = move_input * (real_t)CLAMP(
					1.0 - (double)i / (double)intent_decay_ticks, 0.0, 1.0);
		}
		double thrust = cfg.thrust;
		if (stagger_timer > 0.0 && use_stagger) {
			const double remaining = MAX(stagger_timer - (double)(i + 1) * dt, 0.0);
			thrust = cfg.thrust * stagger_thrust_mult(
					remaining, stagger_max_seconds, stagger_max_thrust_penalty);
		}
		vel = apply_movement_internal(vel, decayed_input, facing_rotation_y,
				has_puck, brake, dt, sprint_active, thrust);
		pos += vel * (real_t)dt;
	}
	fwd_position = pos;
	fwd_velocity = vel;
}

void NativeSkaterMovement::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "movement_config"),
			&NativeSkaterMovement::configure);
	ClassDB::bind_method(D_METHOD("set_stagger_params", "max_stagger_seconds", "max_thrust_penalty"),
			&NativeSkaterMovement::set_stagger_params);
	ClassDB::bind_method(D_METHOD("apply_movement",
			"current_velocity", "move_input", "facing_rotation_y",
			"has_puck", "brake", "delta", "sprint_active"),
			&NativeSkaterMovement::apply_movement);
	ClassDB::bind_method(D_METHOD("apply_movement_with_thrust",
			"current_velocity", "move_input", "facing_rotation_y",
			"has_puck", "brake", "delta", "sprint_active", "thrust"),
			&NativeSkaterMovement::apply_movement_with_thrust);
	ClassDB::bind_method(D_METHOD("integrate_forward",
			"position", "velocity", "move_input", "facing_rotation_y",
			"has_puck", "brake", "sprint_active", "dt", "ticks",
			"intent_decay_ticks", "stagger_timer", "use_stagger"),
			&NativeSkaterMovement::integrate_forward);
	ClassDB::bind_method(D_METHOD("get_forward_position"),
			&NativeSkaterMovement::get_forward_position);
	ClassDB::bind_method(D_METHOD("get_forward_velocity"),
			&NativeSkaterMovement::get_forward_velocity);
}

} // namespace mitts
