#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

namespace mitts {

// C++ port of the gait's numeric core:
//   - SkaterLocomotion (Scripts/controllers/skater_locomotion.gd): the state
//     mix, its easing, the shared clocks and every state's stroke, with the
//     pure helpers it calls (LocomotionRules.classify, HockeyStopRules,
//     CarveRules.turn_rate);
//   - SkaterSkatingCoordinator's hip-to-travel alignment and pivot read, with
//     PivotRules;
//   - GaitPose's stance and knee solve, for a pass no GaitLayer shapes.
// The GDScript is the reference for the math and its reasoning, and
// tests/unit/rules/test_native_gait_parity.gd drives a native coordinator and a
// GDScript one side by side through fuzzed sequences. Change them together or
// not at all.
//
// The overlay layers stay in GDScript: they are mostly idle, and a pass where
// one shapes the pose runs GaitPose's GDScript solve from this kernel's stroke
// (get_stroke_*).
//
// Precision mirrors the reference: double scalars (GDScript's float), godot
// vectors (real_t) for the vector operations.

// Every SkaterController tunable the core reads, by its exact property name.
#define MITTS_GAIT_TUNABLES(X) \
	X(backpedal_ccut_roll_deg) X(backpedal_ccut_sweep_deg) X(backpedal_chest_deg) \
	X(backpedal_pitch_fade) X(backpedal_tuck_fade) X(cadence_cruise_falloff) \
	X(cadence_glide_stance_gain) X(carve_clearance_knee_deg) X(carve_engage_speed) \
	X(carve_min_speed) X(carve_over_pitch_deg) X(carve_over_roll_deg) \
	X(carve_ref_turn_rate) X(carve_stance) X(carve_stride_fade) \
	X(carve_under_roll_deg) X(crossover_commit_speed) X(crossover_lean_deg) \
	X(crossover_phase_per_turn) X(crossover_scissor_deg) X(dig_in_cadence_rate) \
	X(dig_in_chop) X(dig_in_fade_speed) X(dig_in_intensity) X(dig_in_stance) \
	X(glide_hold_skew) X(glide_inside_tuck_deg) X(glide_stance) X(glide_sway_deg) \
	X(glide_sway_hz) X(hip_align_max_deg) X(hip_align_speed) \
	X(hockey_stop_edge_deg) X(hockey_stop_max_yaw_deg) X(hockey_stop_min_speed) \
	X(hockey_stop_split_deg) X(hockey_stop_stance) X(locomotion_blend_speed) \
	X(max_speed) X(pivot_band_hi_deg) X(pivot_band_lo_deg) X(pivot_blend_speed) \
	X(pivot_commit_time) X(pivot_depth_ramp_deg) X(pivot_min_speed) \
	X(pivot_mohawk_deg) X(pivot_rate_min) X(pivot_stance) X(pivot_step_begin) \
	X(pivot_yaw_speed) X(reversal_plant_deg) X(reversal_stance) \
	X(shuffle_cadence_rate) X(shuffle_intensity) X(stance_lean_deg) \
	X(stance_sit_gain) X(stance_sit_floor) X(stance_stride_gain) \
	X(stance_full_speed_fraction) \
	X(stance_hip_deg) X(stance_knee_release) X(stance_push_gain) \
	X(stride_abduction_deg) X(stride_back_pitch_deg) X(stride_bob_m) \
	X(stride_cadence) X(stride_cadence_max_rate) X(stride_effort_ref_accel) \
	X(stride_effort_speed) X(stride_glide_floor) X(stride_intensity_speed) \
	X(stride_knee_deg) X(stride_pitch_deg) X(stride_push_ceiling) \
	X(stride_push_gain) X(stride_rear_bias) X(stride_roll_deg) X(stride_skew) \
	X(stride_sway_deg) X(tight_turn_split_deg) \
	X(tight_turn_stance) X(weight_shift_deg) X(weight_spring_damping) \
	X(weight_spring_stiffness)

class NativeSkaterGait : public godot::RefCounted {
	GDCLASS(NativeSkaterGait, godot::RefCounted)

public:
	// locomote() flags bitmask.
	enum Flags {
		FLAG_BRAKE = 1,
		FLAG_STANCE = 2,
		FLAG_PLANTED = 4,
	};

private:
	struct Config {
#define X(name) double name = 0.0;
		MITTS_GAIT_TUNABLES(X)
#undef X
	};
	Config cfg;
	double leg_scale = 1.0;

	// LocomotionRules.Mix.
	struct Mix {
		double glide = 0.0;
		double stride = 0.0;
		double crossover = 0.0;
		double backward = 0.0;
		double shuffle = 0.0;
		double skid = 0.0;
		double tight = 0.0;
		double stop = 0.0;
		double side = 1.0;
		void clear() {
			glide = stride = crossover = backward = shuffle = skid = tight = stop = 0.0;
		}
	};

	// ── SkaterLocomotion state, field for field ──
	Mix mix;
	Mix target;
	double stride_phase = 0.0;
	double intensity = 0.0;
	double effort = 0.0;
	double turn_rate = 0.0;
	double loaded = 0.0;
	double cruise_gear = 0.0;
	double push_scale = 1.0;
	double stop_side = 1.0;
	double stop_yaw = 0.0;
	double l_pitch = 0.0;
	double r_pitch = 0.0;
	double l_roll = 0.0;
	double r_roll = 0.0;
	double l_ext = 0.0;
	double r_ext = 0.0;
	double l_tuck = 0.0;
	double r_tuck = 0.0;
	double stance = 0.0;
	double bob = 0.0;
	double edge_floor = 0.0;
	double trunk_pitch = 0.0;
	double trunk_roll = 0.0;
	bool stop_latched = false;
	double cross_signed = 0.0;
	godot::Vector3 prev_velocity;
	bool have_prev_velocity = false;
	double fd_time = 0.0;
	double fd_effort_target = 0.0;
	double fd_turn = 0.0;
	double glide_phase = 0.0;
	double weight_shift = 0.0;
	double weight_shift_vel = 0.0;
	double ground_speed = 0.0;
	double speed_t = 0.0;
	double start = 0.0;

	// ── SkaterSkatingCoordinator alignment / pivot state ──
	double travel_align_yaw = 0.0;
	double hip_align_yaw = 0.0;
	double prev_psi = 0.0;
	bool have_prev_psi = false;
	double psi_smooth = 0.0;
	double psi_rate = 0.0;
	bool pivot_engaged = false;
	double pivot_sense = 1.0;
	double pivot_blend = 0.0;
	double pivot_dwell = 0.0;
	double pivot_yaw_l = 0.0;
	double pivot_yaw_r = 0.0;

	// ── GaitPose outputs of solve() ──
	double p_l_pitch = 0.0;
	double p_l_roll = 0.0;
	double p_l_knee = 0.0;
	double p_r_pitch = 0.0;
	double p_r_roll = 0.0;
	double p_r_knee = 0.0;
	double p_drop = 0.0;
	double p_trunk_pitch = 0.0;
	double p_trunk_roll = 0.0;
	double p_edge_l = 0.0;
	double p_edge_r = 0.0;

	void sense(double delta, const godot::Vector3 &vel, const godot::Vector2 &intent,
			const godot::Basis &basis, bool brake, bool stance_active, bool planted, double hold);
	double align_and_pivot(double delta, const godot::Vector3 &vel, const godot::Basis &basis);
	void strokes(double delta, double fwd);
	void stroke(double w, double push, double rock, double flare, double tuck,
			double s, double s_opp, double cs, double cs_opp,
			double ext_l, double ext_r, double bias);
	void stance_of(double s);
	void ease_mix(double delta);
	void sample_velocity(double delta, const godot::Vector3 &vel);
	void clear_strokes();

protected:
	static void _bind_methods();

public:
	// Returns a space-separated list of missing property names — empty means
	// every tunable loaded.
	godot::String configure(godot::Object *controller);
	void set_leg_scale(double p_leg_scale) { leg_scale = p_leg_scale; }
	// SkaterLocomotion.reset plus the coordinator's alignment/pivot reset.
	void reset();

	// SkaterLocomotion.sense, the coordinator's alignment and pivot read, then
	// SkaterLocomotion.strokes in the yawed hip frame.
	void locomote(double delta, const godot::Vector3 &velocity, const godot::Vector2 &intent,
			const godot::Basis &basis, int64_t flags, double hold);

	// (stride_phase, stop_yaw, travel_align_yaw, pivot_hold)
	godot::Vector4 get_channels() const;
	// The locomotion stance floored by the pivot's.
	double get_base_stance() const;

	// The stroke, for GaitPose's GDScript solve when a layer shapes the pass.
	godot::Vector4 get_stroke_legs() const;   // (l_pitch, l_roll, r_pitch, r_roll)
	godot::Vector4 get_stroke_knees() const;  // (l_ext, r_ext, l_tuck, r_tuck)
	godot::Vector4 get_stroke_body() const;   // (bob, trunk_pitch, trunk_roll, edge_floor)
	godot::Vector4 get_stroke_drive() const;  // (intensity, pivot_yaw_l, pivot_yaw_r, 0)

	// GaitPose's solve at `stance` with no layer shaping it.
	void solve(double p_stance);
	godot::Vector4 get_leg_l() const;  // (pitch, roll, knee, yaw)
	godot::Vector4 get_leg_r() const;
	godot::Vector4 get_body() const;   // (drop, trunk_pitch, trunk_roll, 0)
	godot::Vector2 get_edges() const;

	// Diagnostics (allocates): the eased mix, in LocomotionRules.Mix field
	// order — glide, stride, crossover, backward, shuffle, skid, tight, stop, side.
	godot::PackedFloat64Array get_mix() const;
};

} // namespace mitts
