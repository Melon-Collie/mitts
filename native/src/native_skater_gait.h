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
//     mix, its easing, the shared clocks and every state's foot path, with the
//     pure helpers it calls (LocomotionRules.classify, HockeyStopRules,
//     CarveRules.turn_rate);
//   - SkaterSkatingCoordinator's hip-to-travel alignment and pivot read, with
//     PivotRules, and the reach sit;
//   - GaitPose's stance, the leg solve that stands the skates on the ice
//     (seed_legs, with LegIK) and the trunk seed.
// The GDScript is the reference for the math and its reasoning, and
// tests/unit/rules/test_native_gait_parity.gd drives a native coordinator and a
// GDScript one side by side through fuzzed sequences. Change them together or
// not at all.
//
// The overlay layers stay in GDScript and shape the pose this kernel loads into
// GaitPose (load_native_legs / load_native_trunk), so every pass runs here.
//
// Precision mirrors the reference: double scalars (GDScript's float), godot
// vectors and bases (real_t) where the reference uses them.

// Every SkaterController tunable the core reads, by its exact property name.
#define MITTS_GAIT_TUNABLES(X) \
	X(backpedal_chest_deg) X(cadence_cruise_falloff) X(cadence_glide_stance_gain) \
	X(carve_engage_speed) X(carve_lead_m) X(carve_min_speed) X(carve_ref_turn_rate) \
	X(carve_stance) X(ccut_front_m) X(ccut_out_m) X(ccut_return_share) X(ccut_toe_deg) \
	X(crossover_back_m) X(crossover_commit_speed) X(crossover_cross_m) \
	X(crossover_land_fwd_m) X(crossover_lift_m) X(crossover_out_m) X(crossover_pass_m) \
	X(crossover_phase_per_turn) X(crossover_side_m) X(crossover_under_m) \
	X(dig_in_cadence_rate) X(dig_in_chop) X(dig_in_fade_speed) X(dig_in_intensity) \
	X(dig_in_stance) X(glide_hold_skew) X(glide_inside_tuck_deg) X(glide_stance) \
	X(glide_sway_deg) X(glide_sway_hz) X(hip_align_max_deg) X(hip_align_speed) \
	X(hockey_stop_lead_m) X(hockey_stop_max_yaw_deg) X(hockey_stop_min_speed) \
	X(hockey_stop_spread_m) X(hockey_stop_stagger_m) X(hockey_stop_stance) \
	X(lateral_grip) X(locomotion_blend_speed) X(max_speed) X(pivot_band_hi_deg) \
	X(pivot_band_lo_deg) X(pivot_blend_speed) X(pivot_commit_time) \
	X(pivot_depth_ramp_deg) X(pivot_min_speed) X(pivot_mohawk_deg) X(pivot_rate_min) \
	X(pivot_stance) X(pivot_step_begin) X(pivot_yaw_speed) X(reversal_lead_m) \
	X(reversal_spread_m) X(reversal_stance) X(reversal_toe_in_deg) \
	X(shuffle_cadence_rate) X(shuffle_intensity) X(shuffle_lift_m) X(shuffle_step_m) \
	X(stance_full_speed_fraction) X(stance_hip_deg) X(stance_push_gain) \
	X(stance_sit_gain) X(stance_stride_gain) X(stride_bob_m) X(stride_cadence) \
	X(stride_cadence_max_rate) X(stride_effort_ref_accel) X(stride_effort_speed) \
	X(stride_glide_floor) X(stride_intensity_speed) X(stride_land_fwd_m) \
	X(stride_lift_m) X(stride_push_back_m) X(stride_push_ceiling) X(stride_push_gain) \
	X(stride_push_out_m) X(stride_rock_m) X(stride_sit_max_deg) X(stride_skew) \
	X(stride_sway_deg) X(stride_toe_out_deg) X(tight_turn_lead_m) X(tight_turn_stance) \
	X(turn_accel) X(weight_shift_deg) X(weight_spring_damping) \
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
		double carve = 0.0;
		double backward = 0.0;
		double shuffle = 0.0;
		double skid = 0.0;
		double tight = 0.0;
		double stop = 0.0;
		double side = 1.0;
		void clear() {
			glide = stride = crossover = carve = backward = shuffle = skid = tight = stop = 0.0;
		}
	};

	// LegIK.Leg.
	struct Leg {
		double pitch = 0.0;
		double yaw = 0.0;
		double roll = 0.0;
		double knee = 0.0;
		double x = 0.0;
		double y = 0.0;
		double z = 0.0;
	};

	// ── SkaterLocomotion state, field for field ──
	Mix mix;
	Mix target;
	double stride_phase = 0.0;
	double intensity = 0.0;
	double effort = 0.0;
	double turn_rate = 0.0;
	double turning = 0.0;
	double loaded = 0.0;
	double cruise_gear = 0.0;
	double push_scale = 1.0;
	double stop_side = 1.0;
	double stop_yaw = 0.0;
	double stop_yaw_full = 0.0;
	double l_roll = 0.0;
	double r_roll = 0.0;
	double l_tuck = 0.0;
	double r_tuck = 0.0;
	double l_dx = 0.0;
	double l_dy = 0.0;
	double l_dz = 0.0;
	double l_yaw = 0.0;
	double r_dx = 0.0;
	double r_dy = 0.0;
	double r_dz = 0.0;
	double r_yaw = 0.0;
	double l_push = 0.0;
	double r_push = 0.0;
	double push_reach = 0.0;
	double authored = 0.0;
	double sliding = 0.0;
	double stance = 0.0;
	double bob = 0.0;
	double edge_floor = 0.0;
	double trunk_pitch = 0.0;
	double trunk_roll = 0.0;
	bool stop_latched = false;
	double cross_signed = 0.0;
	double carve_signed = 0.0;
	double tight_signed = 0.0;
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

	// ── GaitPose state and outputs of solve() ──
	double stance_hip = 0.0;
	double stance_knee = 0.0;
	double stance_shin = 0.0;
	double drop = 0.0;
	double gripping = 1.0;
	double foot_level = 0.0;
	double plant = 1.0;
	double edge_l = 0.0;
	double edge_r = 0.0;
	godot::Basis lean;
	godot::Basis ice;
	Leg leg_l;
	Leg leg_r;

	void sense(double delta, const godot::Vector3 &vel, const godot::Vector2 &intent,
			const godot::Basis &basis, bool brake, bool stance_active, bool planted, double hold);
	godot::Vector2 align_and_pivot(double delta, const godot::Vector3 &vel, const godot::Basis &basis);
	void strokes(double delta, const godot::Vector2 &travel);
	void stride_path(double w, double a, double s, double s_opp, double cs, double cs_opp);
	void crossover_path(double w, double side, double a, double s, double s_opp,
			double cs, double cs_opp);
	void stop_path(double w, const godot::Vector2 &along, const godot::Vector2 &turned);
	void skid_path(double w, const godot::Vector2 &along);
	void ccut_path(double w, double a, double s, double s_opp, double cs, double cs_opp);
	void shuffle_path(double w, double side, double a, double s, double s_opp,
			double cs, double cs_opp);
	double engaged() const;
	void stance_of(double s);
	void ease_mix(double delta);
	void sample_velocity(double delta, const godot::Vector3 &vel);
	void clear_strokes();

	void place(Leg &leg, double pitch, double yaw, double roll, double knee) const;
	void reach(Leg &leg, double dx, double dy, double dz, double yaw, double level, double side) const;
	double reach_for(const godot::Vector3 &ankle) const;
	godot::Vector3 within(const godot::Vector3 &target, double reach) const;

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
	// SkaterLocomotion.strokes in the aligned hip frame. Returns (the stance
	// floored by the pivot's and the reach sit's, the authored share).
	godot::Vector2 locomote(double delta, const godot::Vector3 &velocity, const godot::Vector2 &intent,
			const godot::Basis &basis, int64_t flags, double hold);
	// (stride_phase, stop_yaw, travel_align_yaw, pivot_hold)
	godot::Vector4 get_channels() const;

	// GaitPose.solve_stance and seed_legs at `stance` and `width`, on the hips'
	// tilt against the ice (GaitPose.lean / ice), and the stroke's seed_trunk
	// values.
	void solve(double p_stance, double p_width, const godot::Basis &p_lean, const godot::Basis &p_ice);
	godot::Vector4 get_leg_l() const;   // (pitch, roll, knee, yaw)
	godot::Vector4 get_leg_r() const;
	godot::Vector4 get_stance() const;  // (stance_hip, stance_knee, stance_shin, drop)
	godot::Vector4 get_seed() const;    // (foot_level, plant share, edge_l, edge_r)
	godot::Vector4 get_trunk() const;   // (bob, trunk_pitch, trunk_roll, 0)
	// (l_push, r_push, push strength, 0): SkaterLocomotion.push_strength().
	godot::Vector4 get_push() const;
	// (mix.stop, mix.skid, |turning|, 0): what the blades make heard — the stop
	// and the skid's scrape, the edges' load in a turn.
	godot::Vector4 get_sound() const;

	// Diagnostics (allocates): the eased mix, in LocomotionRules.Mix field
	// order — glide, stride, crossover, carve, backward, shuffle, skid, tight,
	// stop, side.
	godot::PackedFloat64Array get_mix() const;
};

} // namespace mitts
