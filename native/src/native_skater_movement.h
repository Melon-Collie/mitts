#pragma once

#include <godot_cpp/classes/ref_counted.hpp>

namespace mitts {

// C++ port of Scripts/domain/rules/skater_movement_rules.gd
// (SkaterMovementRules.apply_movement / integrate_forward) plus the one
// BodyCheckRules formulas integrate_forward consumes (thrust_mult, grip_mult). The
// GDScript files are the reference; tests/unit/rules/test_native_movement_parity.gd
// fuzzes the implementations against each other. Change them together or not
// at all.
//
// This kernel sits on all three multiplied paths: the live tick (x10
// skaters), reconcile replay (once per unconfirmed input), and stage-3
// remote forward prediction / host lag-comp rewind (integrate_forward's N
// ticks cross the boundary in ONE call here — the loop runs natively).
//
// MovementConfig fields load by property name from the GDScript config
// object via configure(cfg); the stagger scaling needs only three
// BodyCheckRules.Config fields, set via set_stagger_params. `posture` is
// SkaterMovementRules.Posture as an int (UPRIGHT 0, STANCE 1, COMMIT 2).

#define MITTS_MOVEMENT_TUNABLES(X) \
	X(thrust) X(power_knee_speed) X(friction) X(friction_drag) X(max_speed) \
	X(move_deadzone) X(stop_decel) X(reverse_skid_fraction) X(turn_accel) \
	X(max_turn_rate) X(puck_carry_speed_multiplier) \
	X(backward_thrust_multiplier) X(crossover_thrust_multiplier) \
	X(backward_max_speed_multiplier) X(lateral_grip) \
	X(stance_grip_mult) X(stance_scrape) X(stance_stride_mult) \
	X(stance_max_speed_mult) X(stance_shuffle_mult) \
	X(commit_grip_mult) X(commit_stride_mult)

class NativeSkaterMovement : public godot::RefCounted {
	GDCLASS(NativeSkaterMovement, godot::RefCounted)

	struct Config {
#define X(name) double name = 0.0;
		MITTS_MOVEMENT_TUNABLES(X)
#undef X
	};
	Config cfg;

	double stagger_max_seconds = 0.0;
	double stagger_max_thrust_penalty = 0.0;
	double stagger_max_grip_penalty = 0.0;

	godot::Vector3 fwd_position;
	godot::Vector3 fwd_velocity;

	godot::Vector3 apply_movement_internal(
			const godot::Vector3 &current_velocity,
			const godot::Vector2 &move_input,
			double facing_rotation_y,
			bool has_puck, bool brake, double delta, int64_t posture,
			double thrust, double grip_scale) const;

protected:
	static void _bind_methods();

public:
	// Returns a space-separated list of missing property names — empty means
	// every tunable loaded.
	godot::String configure(godot::Object *movement_config);
	void set_stagger_params(double max_stagger_seconds, double max_thrust_penalty,
			double max_grip_penalty);

	godot::Vector3 apply_movement(
			const godot::Vector3 &current_velocity,
			const godot::Vector2 &move_input,
			double facing_rotation_y,
			bool has_puck, bool brake, double delta, int64_t posture) const;

	// The live-tick shape: SkaterController scales thrust and grip by the
	// stagger penalty each tick, so the effective values arrive per call instead
	// of forcing a per-tick reconfigure.
	godot::Vector3 apply_movement_staggered(
			const godot::Vector3 &current_velocity,
			const godot::Vector2 &move_input,
			double facing_rotation_y,
			bool has_puck, bool brake, double delta, int64_t posture,
			double thrust, double grip_scale) const;

	void integrate_forward(
			const godot::Vector3 &position,
			const godot::Vector3 &velocity,
			const godot::Vector2 &move_input,
			double facing_rotation_y,
			bool has_puck, bool brake, int64_t posture,
			double dt, int64_t ticks, int64_t intent_decay_ticks,
			double stagger_timer, bool use_stagger);

	godot::Vector3 get_forward_position() const { return fwd_position; }
	godot::Vector3 get_forward_velocity() const { return fwd_velocity; }
};

} // namespace mitts
