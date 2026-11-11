#pragma once

#include <godot_cpp/classes/ref_counted.hpp>

#include <cmath>

namespace mitts {

// C++ port of Scripts/domain/rules/top_hand_ik.gd (TopHandIK). The GDScript
// file is the reference for the math and its reasoning; this port must stay
// behaviorally identical — tests/unit/rules/test_native_ik_parity.gd fuzzes
// the two against each other. Change them together or not at all.
//
// Config fields live as properties on the instance (mirroring the cached-
// config pattern GDScript callers use); solve() stores hand/blade for
// retrieval via get_hand()/get_blade() so no per-call heap allocation crosses
// the boundary.
//
// Scalar intermediates are double on purpose: GDScript's float is 64-bit, so
// double-precision scalars keep this port numerically closest to the
// reference. Vector2/Vector3 component math stays real_t, same as GDScript's.
class NativeTopHandIK : public godot::RefCounted {
	GDCLASS(NativeTopHandIK, godot::RefCounted)

	double stick_length = 0.0;
	double blade_y = 0.0;
	double hand_rest_y = 0.0;
	double hand_y_max = 0.0;
	double rom_forehand_angle_max = 0.0;
	double rom_backhand_angle_max = 0.0;
	double rom_forward_reach_max = 0.0;
	double rom_forehand_reach_max = 0.0;
	double rom_backhand_reach_max = 0.0;
	double max_blade_reach = INFINITY;
	// TopHandIK.Config.hand_forward and its bands (forward_floor).
	double hand_forward = 0.0;
	double hand_forward_none = 0.3;
	double hand_forward_full = 0.9;
	double hand_forward_none_angle = 0.17453292519943295; // deg_to_rad(10)
	double hand_forward_full_angle = 0.9599310885968813; // deg_to_rad(55)
	// TopHandIK.REGIME_BAND_M and _FLOOR_ITERATIONS.
	static constexpr double REGIME_BAND_M = 0.08;
	static constexpr int FLOOR_ITERATIONS = 12;

	godot::Vector3 hand;
	godot::Vector3 blade;

	godot::Vector2 clamp_aim_to_rom(const godot::Vector2 &aim_dir, double blade_side_sign) const;
	double rim_reach(double angle_to_forehand) const;
	static double stick_horiz_for(double stick_length, double hand_y, double blade_y);
	double blade_for_span(double span, double to_forehand) const;

protected:
	static void _bind_methods();

public:
	godot::Vector3 project_blade(
			const godot::Vector3 &shoulder,
			const godot::Vector2 &desired_blade_xz,
			double blade_side_sign) const;
	void solve(
			const godot::Vector3 &shoulder,
			const godot::Vector2 &desired_blade_xz,
			double blade_side_sign);
	// SkaterIKCoordinator._solve_top_hand: three solves, each from the blade
	// height the previous one's blade lands at on the ice under the upper body's
	// pitch and roll (blade_y_lean_corrected), with the per-tick config in the
	// call rather than set property by property. `blade_y_base` is
	// blade_y_local(): the ice in upper-body height, before the lean.
	void solve_on_ice(
			const godot::Vector3 &shoulder,
			const godot::Vector2 &desired_blade_xz,
			double blade_side_sign,
			double blade_y_base,
			double pitch,
			double roll,
			double p_max_blade_reach,
			double p_stick_length,
			double p_hand_y_max);

	// TopHandIK.two_hand_reach, from the instance's config (max_blade_reach the
	// cap it bisects under, restored after). Leaves hand/blade overwritten.
	double two_hand_reach(
			const godot::Vector3 &shoulder,
			const godot::Vector2 &desired_blade_xz,
			double blade_side_sign,
			const godot::Vector3 &bottom_shoulder,
			double grip,
			double bottom_reach,
			double spacing);
	// TopHandIK.forward_floor / floored_reach / hand_reach / _to_forehand.
	double forward_floor(double d, double to_forehand) const;
	double floored_reach(double d, double rest_horiz, double to_forehand) const;
	static double hand_reach(double d, double rest_horiz);
	static double to_forehand(const godot::Vector2 &dir, double blade_side_sign);

	// BottomHandIK.reachable_grip: (fraction, overshoot).
	static godot::Vector2 reachable_grip(const godot::Vector3 &shoulder, const godot::Vector3 &top,
			const godot::Vector3 &blade, double grip, double reach, double spacing);

	godot::Vector3 get_hand() const { return hand; }
	godot::Vector3 get_blade() const { return blade; }

	void set_stick_length(double v) { stick_length = v; }
	double get_stick_length() const { return stick_length; }
	void set_blade_y(double v) { blade_y = v; }
	double get_blade_y() const { return blade_y; }
	void set_hand_rest_y(double v) { hand_rest_y = v; }
	double get_hand_rest_y() const { return hand_rest_y; }
	void set_hand_y_max(double v) { hand_y_max = v; }
	double get_hand_y_max() const { return hand_y_max; }
	void set_rom_forehand_angle_max(double v) { rom_forehand_angle_max = v; }
	double get_rom_forehand_angle_max() const { return rom_forehand_angle_max; }
	void set_rom_backhand_angle_max(double v) { rom_backhand_angle_max = v; }
	double get_rom_backhand_angle_max() const { return rom_backhand_angle_max; }
	void set_rom_forward_reach_max(double v) { rom_forward_reach_max = v; }
	double get_rom_forward_reach_max() const { return rom_forward_reach_max; }
	void set_rom_forehand_reach_max(double v) { rom_forehand_reach_max = v; }
	double get_rom_forehand_reach_max() const { return rom_forehand_reach_max; }
	void set_rom_backhand_reach_max(double v) { rom_backhand_reach_max = v; }
	double get_rom_backhand_reach_max() const { return rom_backhand_reach_max; }
	void set_max_blade_reach(double v) { max_blade_reach = v; }
	double get_max_blade_reach() const { return max_blade_reach; }
	void set_hand_forward(double v) { hand_forward = v; }
	double get_hand_forward() const { return hand_forward; }
	void set_hand_forward_none(double v) { hand_forward_none = v; }
	double get_hand_forward_none() const { return hand_forward_none; }
	void set_hand_forward_full(double v) { hand_forward_full = v; }
	double get_hand_forward_full() const { return hand_forward_full; }
	void set_hand_forward_none_angle(double v) { hand_forward_none_angle = v; }
	double get_hand_forward_none_angle() const { return hand_forward_none_angle; }
	void set_hand_forward_full_angle(double v) { hand_forward_full_angle = v; }
	double get_hand_forward_full_angle() const { return hand_forward_full_angle; }
};

} // namespace mitts
