#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace mitts {

// C++ port of the carry-space reads the bots make most: AIEvadeRead.evade_safety
// (Scripts/domain/ai/evade_read.gd: the carrier's keep odds, the seam sweep under
// its exact bounds) and AICarrySpace.carry_safety / carry_strip_point
// (Scripts/domain/ai/carry_space.gd: a carry's keep odds and where it is
// stripped), with what they read: reach_clearance (its escape gate and the
// defender who stops), the crossing band, the two safety maps, board_gap_m and
// AIStrideRamp.distance_in. The GDScript is the reference;
// tests/unit/ai/test_native_carry_space_parity.gd fuzzes the two. Change them
// together or not at all.
//
// Every quantity is a double taken in the GDScript's order, and a point or
// direction the GDScript holds in a Vector3 / Vector2 is rounded to float as it
// is there (f32, Vector3::lerp's float arithmetic), so the two agree to the bit.
// The constants arrive once (set_kinematics, set_rink, set_sweep, set_carry); a
// read keeps nothing between calls, so one instance serves any thread.
class NativeCarrySpace : public godot::RefCounted {
	GDCLASS(NativeCarrySpace, godot::RefCounted)

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

	double transit_strip = -0.4;
	double transit_safe = 0.6;
	double lunge_window_s = 0.4;
	double protect_shift = 0.1;
	double league_blade_reach = 2.4;

	struct Defender {
		double x, z, vx, vz;
		double accel, stick, vmax, grip, blade_reach;
		double bound_x, bound_z, bound_slack;
	};

	// The opponents and their caps (CAPS_PER per man, or empty for the league's);
	// false when there is nothing to read against (none, or velocities that do not
	// index-match), which reach_clearance reads as fully clear.
	bool load(const godot::Array &opponents, const godot::Array &opponent_vels,
			const godot::PackedFloat64Array &caps, std::vector<Defender> &defs) const;
	double board_gap(double x, double z) const;
	double distance_in(double v0, double time, double vmax, double accel) const;
	double committed_clearance(double point_x, double point_z, double tau, double px,
			double pz, double vx, double vz, double accel, double stick, double vmax,
			double lateral_grip) const;
	double stopped_clearance(double point_x, double point_z, double time, double w,
			const Defender &o, double accel, double pace_share) const;
	double reach_clearance(double px, double pz, double time,
			const std::vector<Defender> &defs, bool valid, double maneuver_time,
			double carry_dx, double carry_dz, double carry_speed, double abort_below) const;
	double clearance_bound(double px, double pz, const std::vector<Defender> &defs) const;
	double clearance_to_safety(double clearance) const;
	double transit_clearance_to_safety(double clearance) const;
	double crossing_keep(double fx, double fz, double tx, double tz, double arrival_time,
			const std::vector<Defender> &defs, bool valid) const;

protected:
	static void _bind_methods();

public:
	// Per opponent in `caps`: max_accel, blade_span, max_speed, lateral_grip,
	// max_blade_reach.
	static constexpr int CAPS_PER = 5;

	void set_kinematics(double p_maneuver_accel, double p_stick_reach, double p_ref_speed,
			double p_reaction_s, double p_free_shed, double p_shed_decel,
			double p_reversal_brake, double p_power_knee, double p_efficiency,
			double p_safe_margin);
	void set_rink(double p_inner_half_width, double p_inner_half_length,
			double p_corner_radius, double p_corner_center_x, double p_corner_center_z);
	void set_sweep(double p_horizon_s, int64_t p_angles,
			const godot::PackedFloat64Array &p_rings, double p_saturated_m,
			double p_poke_contact, double p_dwell_half_band);
	void set_carry(double p_transit_strip, double p_transit_safe, double p_lunge_window_s,
			double p_protect_shift, double p_league_blade_reach);

	// AIEvadeRead.evade_safety.
	double evade_safety(const godot::Vector3 &carrier_pos, const godot::Vector3 &carrier_vel,
			const godot::Array &opponents, const godot::Array &opponent_vels,
			double handle_reach, const godot::PackedFloat64Array &caps) const;
	// AICarrySpace.carry_safety.
	double carry_safety(const godot::Vector3 &from, const godot::Vector3 &to,
			double arrival_time, const godot::Array &opponents,
			const godot::Array &opponent_vels, const godot::PackedFloat64Array &caps,
			bool apply_escape) const;
	// AICarrySpace.carry_strip_point.
	godot::Vector3 carry_strip_point(const godot::Vector3 &from, const godot::Vector3 &to,
			double arrival_time, const godot::Array &opponents,
			const godot::Array &opponent_vels, const godot::PackedFloat64Array &caps,
			bool apply_escape, bool covered_only) const;
};

} // namespace mitts
