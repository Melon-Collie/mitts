#pragma once

#include "native_skater_movement.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace mitts {

// C++ port of Scripts/domain/ai/carry_rollout.gd (AICarryRollout.roll_all: every
// move skated in one crossing) with the rules a rolled tick runs inlined —
// AISteering.stance_cuts_onto, SkaterMovementRules.apply_movement (shared with
// NativeSkaterMovement),
// FacingRules.solve, BoardPlayRules.board_proximity / board_shield_facing, and
// GameRules.clamp_to_rink_inner / push_out_of_net. The GDScript files are the
// reference; tests/unit/ai/test_native_carry_rollout_parity.gd fuzzes the two.
// Change them together or not at all.
//
// One instance per AICarryRollout: the results are its own state, and the bots
// run on the AI worker thread.
//
// The skater's tunables load by property name from an AISkaterCaps
// (configure): its movement config, its facing rules, and the body fields below.

#define MITTS_FACING_TUNABLES(X) \
	X(engage_min_speed) X(engage_full_speed) X(hold_min_speed) X(hold_full_speed) \
	X(cone_rad) X(cone_hysteresis_rad) X(stance_square_max_speed)

#define MITTS_ROLLOUT_BODY_TUNABLES(X) \
	X(facing_drag_speed) X(facing_drag_speed_braking) X(body_radius) \
	X(board_shield_probe) X(board_shield_max_rad) X(reach_cone_half_angle)

class NativeCarryRollout : public godot::RefCounted {
	GDCLASS(NativeCarryRollout, godot::RefCounted)

	static constexpr int MOVE_COUNT = 7;
	enum Move { STRAIGHT, SOFT_LEFT, SOFT_RIGHT, HARD_LEFT, HARD_RIGHT, BRAKE, CUT_BACK };

	MovementTunables move_cfg;
	struct Facing {
#define X(name) double name = 0.0;
		MITTS_FACING_TUNABLES(X)
#undef X
	} facing_cfg;
	struct Body {
#define X(name) double name = 0.0;
		MITTS_ROLLOUT_BODY_TUNABLES(X)
#undef X
	} body;

	// GameRules geometry.
	double inner_half_width = 0.0;
	double inner_half_length = 0.0;
	double inner_corner_radius = 0.0;
	double corner_center_x = 0.0;
	double corner_center_z = 0.0;
	double goal_line_z = 0.0;
	double net_depth = 0.0;
	double net_back_half_width = 0.0;

	// AICarryRollout's move set and clock.
	double soft_turn_rad = 0.0;
	double hard_turn_rad = 0.0;
	double tick_dt = 0.0;
	int64_t ticks = 0;
	int64_t samples_per_move = 1;

	// The stance read (AICarryRollout.STANCE_TURN_WINDOW_S, AISteering's
	// STANCE_CUT_MAX_ANGLE_DEG, STANCE_RELEASE_FRACTION and turn-rate ceiling,
	// FacingRules' STANCE_SQUARE_BLEND_M_S).
	double stance_window_s = 0.0;
	double stance_cut_max_rad = 0.0;
	double stance_release_fraction = 1.0;
	double max_turn_rate = 0.0;
	double stance_square_blend = 0.0;

	godot::PackedVector3Array end_pos;
	godot::PackedVector3Array end_vel;
	godot::PackedVector2Array end_facing;
	godot::PackedVector3Array samples;
	int64_t touched_mask = 0;

	godot::Vector2 clamp_to_rink_inner(const godot::Vector2 &world_xz, double margin) const;
	godot::Vector2 push_out_of_net(const godot::Vector2 &world_xz, double radius) const;
	godot::Vector2 face(const godot::Vector2 &f, const godot::Vector2 &cur,
			const godot::Vector3 &v, const godot::Vector3 &p, bool braking, bool stance,
			double step, bool shield) const;
	bool stance_cuts_onto(const godot::Vector2 &dir, const godot::Vector3 &v,
			double upright_lateral_accel, bool was_holding) const;
	void roll(int m, const godot::Vector2 &stick, const godot::Vector2 &cursor, bool braking,
			const godot::Vector3 &pos, const godot::Vector3 &vel, const godot::Vector2 &facing,
			bool has_puck, int64_t step_ticks);

protected:
	static void _bind_methods();

public:
	void set_geometry(double p_inner_half_width, double p_inner_half_length,
			double p_inner_corner_radius, double p_corner_center_x, double p_corner_center_z,
			double p_goal_line_z, double p_net_depth, double p_net_back_half_width);
	void set_moves(double p_soft_turn_rad, double p_hard_turn_rad, double p_tick_dt,
			int64_t p_ticks, int64_t p_samples_per_move);
	void set_stance(double p_window_s, double p_cut_max_rad, double p_release_fraction,
			double p_max_turn_rate, double p_square_blend);
	// Returns a space-separated list of missing property names — empty means
	// every tunable loaded.
	godot::String configure(godot::Object *caps);

	// `toward` must be normalised (AICarryRollout.roll_all normalises it once
	// for both paths).
	void roll_all(const godot::Vector3 &pos, const godot::Vector3 &vel,
			const godot::Vector2 &facing, const godot::Vector2 &toward, bool has_puck,
			int64_t step_ticks);

	godot::PackedVector3Array get_end_pos() const { return end_pos; }
	godot::PackedVector3Array get_end_vel() const { return end_vel; }
	godot::PackedVector2Array get_end_facing() const { return end_facing; }
	godot::PackedVector3Array get_samples() const { return samples; }
	int64_t get_touched_mask() const { return touched_mask; }
};

} // namespace mitts
