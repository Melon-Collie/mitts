#include "native_skater_movement.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace mitts {

// SkaterMovementRules.GRIP_MIN_SPEED / SKID_TURN_TAPER / Posture.
static constexpr double GRIP_MIN_SPEED = 0.5;
static constexpr double SKID_TURN_TAPER = Math_PI * 0.25;
static constexpr int64_t POSTURE_STANCE = 1;
static constexpr int64_t POSTURE_COMMIT = 2;

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

void NativeSkaterMovement::set_stagger_params(double max_stagger_seconds, double max_thrust_penalty,
		double max_grip_penalty) {
	stagger_max_seconds = max_stagger_seconds;
	stagger_max_thrust_penalty = max_thrust_penalty;
	stagger_max_grip_penalty = max_grip_penalty;
}

// BodyCheckRules._stagger_frac; thrust_mult and grip_mult are 1 − frac × penalty.
static double stagger_frac(double stagger_timer, double max_seconds) {
	if (stagger_timer <= 0.0 || max_seconds <= 0.0) {
		return 0.0;
	}
	return CLAMP(stagger_timer / max_seconds, 0.0, 1.0);
}

Vector3 NativeSkaterMovement::apply_movement_internal(
		const Vector3 &current_velocity,
		const Vector2 &move_input,
		double facing_rotation_y,
		bool has_puck, bool brake, double delta, int64_t posture,
		double thrust, double grip_scale) const {
	Vector3 velocity = current_velocity;
	double stride_mult = 1.0;
	double cap_mult = 1.0;
	double posture_grip = 1.0;
	if (posture == POSTURE_STANCE) {
		stride_mult = cfg.stance_stride_mult;
		cap_mult = cfg.stance_max_speed_mult;
		posture_grip = cfg.stance_grip_mult;
	} else if (posture == POSTURE_COMMIT) {
		stride_mult = cfg.commit_stride_mult;
		posture_grip = cfg.commit_grip_mult;
	}
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
				double push_mult = stride_mult;
				if (posture == POSTURE_STANCE) {
					const double across = (double)facing_dir.cross(move_input.normalized());
					push_mult = Math::lerp(cfg.stance_stride_mult, cfg.stance_shuffle_mult, across * across);
				}
				horiz += move_input * (real_t)(thrust * push_mult * thrust_scale * delta);
			}
			horiz = horiz.move_toward(Vector2(),
					(real_t)((cfg.friction + cfg.friction_drag * (double)horiz.length()) * delta));
		}
		velocity.x = horiz.x;
		velocity.z = horiz.y;
		return velocity;
	}

	const Vector2 travel = horiz / (real_t)speed;
	double turn = 0.0;
	if (brake) {
		speed = MAX(speed - cfg.stop_decel * delta, 0.0);
	} else {
		double scrape = 0.0;
		if (has_input) {
			const double stick = MIN((double)move_input.length(), 1.0);
			const double steer = (double)travel.angle_to(move_input);
			const double steer_abs = Math::abs(steer);
			const double edge_grip = cfg.lateral_grip * grip_scale;
			const double taper = MIN((Math_PI - steer_abs) / SKID_TURN_TAPER, 1.0);
			const double turn_rate = MIN(cfg.turn_accel * edge_grip * posture_grip * stick / speed,
					cfg.max_turn_rate) * taper;
			turn = SIGN(steer) * MIN(turn_rate * delta, steer_abs);
			if (posture == POSTURE_STANCE) {
				const double upright_rate = MIN(cfg.turn_accel * edge_grip * stick / speed,
						cfg.max_turn_rate) * taper;
				const double upright_turn = MIN(upright_rate * delta, steer_abs);
				scrape = cfg.stance_scrape * (Math::abs(turn) - upright_turn) / delta * speed;
			}
			const double par = (double)move_input.dot(travel);
			if (par >= 0.0) {
				double effective_max = cfg.max_speed * cap_mult;
				if (has_puck) {
					effective_max *= cfg.puck_carry_speed_multiplier;
				}
				const double backward = CLAMP(-(double)travel.dot(facing_dir), 0.0, 1.0);
				effective_max *= Math::lerp(1.0, cfg.backward_max_speed_multiplier, backward);
				const double applied_thrust = thrust * stride_mult;
				const double drive = MIN(applied_thrust, applied_thrust * cfg.power_knee_speed / speed);
				const double driven = speed + par * drive * thrust_scale * delta;
				speed = MIN(driven, MAX(speed, effective_max));
			} else {
				speed = MAX(speed + par * cfg.stop_decel * cfg.reverse_skid_fraction * delta, 0.0);
			}
		}
		speed = MAX(speed - (cfg.friction + cfg.friction_drag * speed + scrape) * delta, 0.0);
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
		bool has_puck, bool brake, double delta, int64_t posture) const {
	return apply_movement_internal(current_velocity, move_input, facing_rotation_y,
			has_puck, brake, delta, posture, cfg.thrust, 1.0);
}

Vector3 NativeSkaterMovement::apply_movement_staggered(
		const Vector3 &current_velocity,
		const Vector2 &move_input,
		double facing_rotation_y,
		bool has_puck, bool brake, double delta, int64_t posture,
		double thrust, double grip_scale) const {
	return apply_movement_internal(current_velocity, move_input, facing_rotation_y,
			has_puck, brake, delta, posture, thrust, grip_scale);
}

void NativeSkaterMovement::integrate_forward(
		const Vector3 &position,
		const Vector3 &velocity,
		const Vector2 &move_input,
		double facing_rotation_y,
		bool has_puck, bool brake, int64_t posture,
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
		double grip_scale = 1.0;
		if (stagger_timer > 0.0 && use_stagger) {
			const double remaining = MAX(stagger_timer - (double)(i + 1) * dt, 0.0);
			const double frac = stagger_frac(remaining, stagger_max_seconds);
			thrust = cfg.thrust * (1.0 - frac * stagger_max_thrust_penalty);
			grip_scale = 1.0 - frac * stagger_max_grip_penalty;
		}
		vel = apply_movement_internal(vel, decayed_input, facing_rotation_y,
				has_puck, brake, dt, posture, thrust, grip_scale);
		pos += vel * (real_t)dt;
	}
	fwd_position = pos;
	fwd_velocity = vel;
}

void NativeSkaterMovement::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "movement_config"),
			&NativeSkaterMovement::configure);
	ClassDB::bind_method(D_METHOD("set_stagger_params", "max_stagger_seconds", "max_thrust_penalty",
			"max_grip_penalty"),
			&NativeSkaterMovement::set_stagger_params);
	ClassDB::bind_method(D_METHOD("apply_movement",
			"current_velocity", "move_input", "facing_rotation_y",
			"has_puck", "brake", "delta", "posture"),
			&NativeSkaterMovement::apply_movement);
	ClassDB::bind_method(D_METHOD("apply_movement_staggered",
			"current_velocity", "move_input", "facing_rotation_y",
			"has_puck", "brake", "delta", "posture", "thrust", "grip_scale"),
			&NativeSkaterMovement::apply_movement_staggered);
	ClassDB::bind_method(D_METHOD("integrate_forward",
			"position", "velocity", "move_input", "facing_rotation_y",
			"has_puck", "brake", "posture", "dt", "ticks",
			"intent_decay_ticks", "stagger_timer", "use_stagger"),
			&NativeSkaterMovement::integrate_forward);
	ClassDB::bind_method(D_METHOD("get_forward_position"),
			&NativeSkaterMovement::get_forward_position);
	ClassDB::bind_method(D_METHOD("get_forward_velocity"),
			&NativeSkaterMovement::get_forward_velocity);
}

} // namespace mitts
