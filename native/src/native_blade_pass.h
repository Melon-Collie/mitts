#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include "native_blade_dangle.h"
#include "native_top_hand_ik.h"

#include <cmath>

namespace mitts {

// C++ port of SkaterIKCoordinator.apply_blade_toward: the tracked blade's whole
// tick, from the cursor to the markers. The GDScript is the reference;
// tests/unit/controllers/test_native_blade_pass_parity.gd skates the two side by
// side. Change them together or not at all.
//
// It reads nothing live. SkaterIKCoordinator gathers the pass's inputs once
// (`run`'s arguments), and the rink, the net and the controller's tunables are
// handed over when they change (set_rink, set_net, configure). It writes nothing
// either: the markers, the reach target and a puck released mid-pass come back
// for the coordinator to apply, the releases first, as the GDScript fires them
// before it writes the markers.
//
// Scalars are double and vector components real_t, as in GDScript, so the two
// agree to roundoff.
class NativeBladePass : public godot::RefCounted {
	GDCLASS(NativeBladePass, godot::RefCounted)

public:
	// run()'s scalar inputs, by index.
	enum Scalar {
		S_DELTA,
		S_HOLD_BLADE,
		S_HOLD_SEAT,
		S_HAS_PUCK,
		S_LEFT_HANDED,
		S_WRISTER_AIM,
		S_TRUNK_FOLD,
		S_ADDRESS,
		S_FOREHAND_FACTOR,
		S_TRANSIT_FACTOR,
		S_LIFT_BLEND,
		S_COMMIT_BLEND,
		S_GRIP_CHOKE,
		S_CHECK_LEAD,
		S_HAS_PUCK_NODE,
		S_PURPOSE_RIM,
		S_BLADE_LENGTH,
		S_CARRY_BLADE_OFFSET,
		S_CARRY_TRANSIT_LIFT,
		S_WALL_SQUEEZE_THRESHOLD,
		S_WALL_PIN_INWARD_BIAS,
		S_BOTTOM_REACH,
		S_GLOVE_SPACING,
		S_HAS_NET_ANCHOR,
		S_REACH_PURPOSE,
		S_COUNT,
	};
	// run()'s vector inputs, by index.
	enum Vec {
		V_TARGET,
		V_SHOULDER,
		V_BOTTOM_SHOULDER,
		V_BLADE_MARKER,
		V_BLADE_FORWARD,
		V_PREV_CONTACT,
		V_PUCK_POS,
		V_PUCK_VEL,
		V_VELOCITY,
		V_UB_ROTATION,
		V_LAST_TARGET,
		V_NET_ANCHOR,
		V_COUNT,
	};

private:
	godot::Ref<NativeTopHandIK> top;
	godot::Ref<NativeBladeDangle> dangle;

	// GameRules: the rink's inner boundary.
	double inner_half_width = 0.0;
	double inner_half_length = 0.0;
	double inner_corner_radius = 0.0;
	double corner_center_x = 0.0;
	double corner_center_z = 0.0;
	// GameRules: the net.
	double goal_line_z = 0.0;
	double net_half_width = 0.0;
	double net_post_radius = 0.0;
	double net_depth = 0.0;
	double net_top_depth = 0.0;
	double net_height = 0.0;
	double net_back_half_width = 0.0;
	double net_crown_half_width = 0.0;
	double net_mouth_corner_radius = 0.0;
	double net_mesh_give = 0.0;
	double back_slope = 0.0;

	// SkaterController tunables (configure).
	double hand_rest_y = 0.0;
	double hand_y_max = 0.0;
	double hand_pivot_forward = 0.0;
	double hand_pivot_inward = 0.0;
	double faceoff_center_hand_rise = 0.0;
	double faceoff_center_lean_deg = 0.0;
	double stick_length = 0.0;
	double rom_forward_reach_max = 0.0;
	double net_blade_half_thickness = 0.0;
	double blade_height = 0.0;
	double blade_lift_height = 0.0;
	double hit_commit_blade_lift_m = 0.0;
	double bh_release_angle_deg = 0.0;
	double reach_purpose_lookahead_s = 0.0;
	double reach_purpose_near_m = 0.0;
	double reach_purpose_far_m = 0.0;
	double hit_commit_hand_local_x = 0.0;
	double hit_commit_hand_local_y = 0.0;
	double hit_commit_hand_local_z = 0.0;
	double hit_commit_blade_bearing_x = 0.0;
	double hit_commit_blade_bearing_z = 0.0;
	double hit_commit_blade_sweep = 0.0;
	double goalie_block_radius = 0.0;
	double butterfly_pad_half_x = 0.0;
	double butterfly_pad_half_z = 0.0;
	double goalie_strip_power = 0.0;
	double bottom_hand_grip_fraction = 0.0;
	double faceoff_center_grip_fraction = 0.0;
	double twist_limit = 0.0;

	// The settle's held reach target, in the skater root's frame.
	godot::Vector3 held_seat_local;
	bool seat_held = false;

	// ── This pass ─────────────────────────────────────────────────────────────
	double s[S_COUNT] = {};
	godot::Vector3 v[V_COUNT];
	godot::Transform3D skater_xf;
	godot::Transform3D ub_xf;
	godot::Transform3D ub_inv;
	bool has_puck = false;
	double sign = 1.0;
	double blade_y_local = 0.0;
	godot::Basis tilt;
	godot::Vector3 trunk_shoulder;
	godot::Vector3 arm_shoulder;
	godot::Vector3 bottom_trunk_shoulder;
	godot::Vector3 wall_normal;
	godot::Vector3 net_anchor;
	bool has_net_anchor = false;
	double reach_purpose = 1.0;

	// Where a pass suspended for a release, and what it resumes with.
	enum Stage {
		STAGE_DONE,
		STAGE_AFTER_WALL_RELEASE,
		STAGE_AFTER_BUTTERFLY_RELEASE,
		STAGE_AFTER_CYLINDER_RELEASE,
	};
	Stage stage = STAGE_DONE;
	godot::PackedFloat64Array goalie_data;
	int goalie_index = 0;
	godot::Vector3 goalie_prev;
	godot::Vector3 hand;
	godot::Vector3 intended_blade;
	godot::Vector3 wall_clamped;
	godot::Vector3 heel_world;
	godot::Vector3 clamped_heel;
	bool pending = false;
	godot::Vector3 pending_dir;
	double pending_power = 0.0;

	// Outputs.
	bool skipped = false;
	godot::Vector3 out_hand;
	godot::Vector3 out_blade;
	godot::Vector3 out_last_target;
	godot::Vector3 out_smoothed;

	// Level-frame solve config: what _level_config / _ik_config fill.
	struct Cfg {
		double blade_y;
		double hand_rest_y;
		double hand_y_max;
		double pivot_forward;
		double pivot_inward;
		double stick_length;
		double max_blade_reach;
	};

	godot::Vector3 shoulder_in_frame(const godot::Vector3 &marker) const;
	double address_hand_ceiling() const;
	Cfg ik_config(double p_blade_y, double max_reach) const;
	Cfg level_config(double hang_y, double p_blade_y, double max_reach) const;
	double lean_corrected_y(double x, double z) const;
	godot::Vector2 blade_target_for(const godot::Vector2 &p_cursor_xz) const;
	double board_reach_limit(const godot::Vector2 &target_xz, const godot::Vector3 &shoulder_world) const;
	double purpose(const godot::Vector3 &skater_pos) const;
	godot::Vector2 carry_backhand_stop(const godot::Vector2 &target_xz) const;
	void apply_cfg(const Cfg &cfg) const;
	double two_hand_reach(const godot::Vector3 &shoulder, const godot::Vector2 &target_xz, const Cfg &cfg);
	double rest_reach(const godot::Vector3 &shoulder, const godot::Vector2 &target_xz, const Cfg &cfg);
	void solve_top_hand(godot::Vector2 desired_xz, double max_reach, bool limits,
			godot::Vector3 &r_hand, godot::Vector3 &r_blade);
	void commit_hand_pose(godot::Vector3 &r_hand, godot::Vector3 &r_blade, double commit_t) const;
	godot::Vector3 clamp_blade_to_walls(const godot::Vector3 &local_pos);
	godot::Vector3 clamp_butterfly_box(const godot::Vector3 &blade_world,
			const godot::Vector3 &gpos, double rot_y);
	godot::Vector3 resolve_net(const godot::Vector3 &heel_world);
	godot::Vector3 blade_toe_for(const godot::Vector3 &heel_world) const;
	void release(const godot::Vector3 &dir, double power);
	// The pass from the wall-pin release on: the goalies, the net, the rebuild.
	// Returns at a release, to be resumed, as the GDScript fires one mid-pass.
	void continue_pass();
	void finish();

	// TopHandIK.
	double max_reach_for_angle(double angle_to_forehand) const;
	godot::Vector3 hand_for_clamped_blade(const godot::Vector3 &shoulder, const godot::Vector2 &blade_xz,
			double p_blade_y, const Cfg &cfg) const;
	void enforce_rigid_stick(const godot::Vector3 &shoulder, godot::Vector3 &r_hand,
			godot::Vector3 &r_blade, const Cfg &cfg) const;

	// GameRules rink.
	godot::Vector2 clamp_to_rink_inner(const godot::Vector2 &xz) const;
	double distance_to_rink_inner(const godot::Vector2 &xz) const;
	double ray_to_rink_inner(const godot::Vector2 &origin, const godot::Vector2 &dir) const;

	// NetGeometry.
	double near_end_z(double z) const { return z >= 0.0 ? goal_line_z : -goal_line_z; }
	double back_depth_at_height(double y) const;
	double back_plane_norm() const { return std::sqrt(1.0 + back_slope * back_slope); }
	double back_plane_distance(const godot::Vector3 &p) const;
	godot::Vector3 back_plane_normal(double end_sign) const;
	bool interior_or_mouth(const godot::Vector3 &p) const;
	double post_top_y() const { return net_height - net_mouth_corner_radius; }
	godot::Vector3 closest_point_on_bend(const godot::Vector3 &p, double end_z) const;
	double ray_to_solid_face(const godot::Vector2 &origin, const godot::Vector2 &dir, double y) const;
	double ray_to_post(const godot::Vector2 &origin, const godot::Vector2 &dir, double clearance) const;
	double distance_to_near_net(const godot::Vector2 &origin, double clearance) const;
	double ray_to_net(const godot::Vector2 &origin, const godot::Vector2 &dir, double y, double clearance) const;
	godot::Vector3 post_overlap_xz(const godot::Vector2 &a, const godot::Vector2 &b, double post_x,
			double end_z, double clearance) const;

	// NetBladeCollision.
	bool net_resolve(const godot::Vector3 &prev, const godot::Vector3 &heel, const godot::Vector3 &toe,
			double half_thickness, double mesh_give, godot::Vector3 &r_offset) const;
	bool resolve_bend(const godot::Vector3 &heel, const godot::Vector3 &toe, double end_z,
			double half_thickness, godot::Vector3 &r_offset) const;
	godot::Vector3 twine_offset(const godot::Vector3 &prev, const godot::Vector3 &point, bool interior,
			double mesh_give, double end_z) const;
	godot::Vector3 side_anchor(const godot::Vector3 &anchor, const godot::Vector3 &contact) const;

protected:
	static void _bind_methods();

public:
	void bind(const godot::Ref<godot::RefCounted> &p_top, const godot::Ref<godot::RefCounted> &p_dangle);
	void set_rink(double p_inner_half_width, double p_inner_half_length, double p_inner_corner_radius,
			double p_corner_center_x, double p_corner_center_z);
	void set_net(double p_goal_line_z, double p_net_half_width, double p_net_post_radius,
			double p_net_depth, double p_net_top_depth, double p_net_height,
			double p_net_back_half_width, double p_net_crown_half_width,
			double p_net_mouth_corner_radius, double p_net_mesh_give);
	// The controller's tunables, by their GDScript names, and the ROM limits
	// onto the bound NativeTopHandIK. False when one is missing: a binary older
	// than a tunable the scripts read.
	bool configure(const godot::Dictionary &tunables);
	void reset_seat() { seat_held = false; }

	// One pass. `goalies` is (x, z, butterfly, rotation_y) per goalie, read only
	// while carrying, as the GDScript reads get_goalie_data(). When it returns
	// with a release pending, the caller fires it and calls resume with whether
	// the skater still has the puck; outputs are ready once nothing is pending.
	void run(const godot::Transform3D &p_skater_xf, const godot::Transform3D &p_ub_xf,
			const godot::PackedFloat64Array &scalars, const godot::PackedVector3Array &vectors,
			const godot::PackedFloat64Array &goalies);
	void resume(bool p_has_puck);
	bool get_pending() const { return pending; }
	godot::Vector3 get_pending_dir() const { return pending_dir; }
	double get_pending_power() const { return pending_power; }

	bool get_skipped() const { return skipped; }
	godot::Vector3 get_hand() const { return out_hand; }
	godot::Vector3 get_blade() const { return out_blade; }
	godot::Vector3 get_last_target() const { return out_last_target; }
	godot::Vector3 get_smoothed_blade() const { return out_smoothed; }
	double get_reach_purpose() const { return reach_purpose; }
	godot::Vector3 get_wall_normal() const { return wall_normal; }
	godot::Vector3 get_net_anchor() const { return net_anchor; }
	bool get_has_net_anchor() const { return has_net_anchor; }
};

} // namespace mitts
