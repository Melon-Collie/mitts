#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace mitts {

// C++ port of Scripts/domain/ai/evade_read.gd (AIEvadeRead.evade_safety: the
// carrier's keep odds, the seam sweep under exact bounds) and of the part of
// Scripts/domain/ai/carry_space.gd it reads (AICarrySpace.reach_clearance with
// the whole window committed, its prescreen and abort, board_gap_m and
// clearance_to_safety) with AIStrideRamp.distance_in. The GDScript is the
// reference; tests/unit/ai/test_native_evade_read_parity.gd fuzzes the two.
// Change them together or not at all.
//
// Every quantity is a double taken in the GDScript's order, so the two agree to
// the bit. The constants arrive once (set_kinematics, set_rink, set_sweep); a
// read keeps nothing between calls, so one instance serves any thread.
class NativeEvadeRead : public godot::RefCounted {
	GDCLASS(NativeEvadeRead, godot::RefCounted)

	// AICarrySpace / AIArrival / AIStrideRamp / GameRules.
	double maneuver_accel = 1.0;
	double stick_reach = 1.0;
	double ref_speed = 1.0;
	double reaction_s = 0.0;
	double free_shed = 0.0;
	double shed_decel = 1.0;
	double reversal_brake = 1.0;
	double power_knee = 1.0;
	double efficiency = 1.0;
	double safe_margin = 1.0;

	double inner_half_width = 1.0;
	double inner_half_length = 1.0;
	double corner_radius = 1.0;
	double corner_center_x = 0.0;
	double corner_center_z = 0.0;

	double horizon_s = 0.4;
	int angles = 12;
	std::vector<double> rings;
	double saturated_m = 1.0;
	double poke_contact = 0.5;
	double dwell_half_band = 0.3;

	struct Defender {
		double x, z, vx, vz;
		double accel, stick, vmax, grip;
		double bound_x, bound_z, bound_slack;
	};

	double board_gap(double x, double z) const;
	double distance_in(double v0, double time, double vmax, double accel) const;
	double committed_clearance(double point_x, double point_z, double tau, double px,
			double pz, double vx, double vz, double accel, double stick, double vmax,
			double lateral_grip) const;
	double reach_clearance(double px, double pz, double time,
			const std::vector<Defender> &defs, double abort_below) const;
	double clearance_bound(double px, double pz, const std::vector<Defender> &defs) const;
	double clearance_to_safety(double clearance) const;

protected:
	static void _bind_methods();

public:
	void set_kinematics(double p_maneuver_accel, double p_stick_reach, double p_ref_speed,
			double p_reaction_s, double p_free_shed, double p_shed_decel,
			double p_reversal_brake, double p_power_knee, double p_efficiency,
			double p_safe_margin);
	void set_rink(double p_inner_half_width, double p_inner_half_length,
			double p_corner_radius, double p_corner_center_x, double p_corner_center_z);
	void set_sweep(double p_horizon_s, int64_t p_angles,
			const godot::PackedFloat64Array &p_rings, double p_saturated_m,
			double p_poke_contact, double p_dwell_half_band);

	// AIEvadeRead.evade_safety. `caps` is four per opponent (max_accel,
	// blade_span, max_speed, lateral_grip), or empty for the league's. A point
	// the GDScript builds as a Vector3 is rounded to float as it is (f32).
	double evade_safety(const godot::Vector3 &carrier_pos, const godot::Vector3 &carrier_vel,
			const godot::Array &opponents, const godot::Array &opponent_vels,
			double handle_reach, const godot::PackedFloat64Array &caps) const;
};

} // namespace mitts
