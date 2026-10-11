#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

namespace mitts {

// C++ port of the leg chain in Scripts/actors/skater_leg_rig.gd (SkaterLegRig):
// the ankle's give-back (_foot_pose), the chain to a runner at a knee
// extension (_chain / _chain_low), and the second-foot plant that walks a knee
// to meet the other blade (_plant_feet, _solve_knee, _refine, _extremum). The
// contact seat evaluates the chain a dozen to two dozen times a frame, which is
// the cost. The GDScript is the reference; the parity fuzz
// (tests/unit/rules/test_native_leg_chain_parity.gd) keeps them identical.
//
// The rig keeps the bones and the writes. It hands this kernel the leg's rest
// geometry (configure, set_side), and on every gait write the pose the chain
// starts from (set_pose, set_ankles).
//
// Precision mirrors the reference: double scalars, real_t vectors and bases,
// and the walk's samples held in single precision as its PackedFloat32Arrays
// hold them.
class NativeLegChain : public godot::RefCounted {
	GDCLASS(NativeLegChain, godot::RefCounted)

	struct Side {
		godot::Vector3 leg_pos;
		godot::Vector3 shin_pos;
		godot::Vector3 foot_pos;
		godot::Basis foot_basis;
		godot::Vector3 foot_scale = godot::Vector3(1, 1, 1);
		godot::Vector3 shin_base;
		godot::Vector3 gait_leg;
		double gait_knee = 0.0;
		double ankle = 0.0;
		double level = 0.0;
	};
	Side sides[2];
	godot::Basis ice;
	godot::Vector3 runner_toe;
	godot::Vector3 runner_heel;
	double shin_frac = 0.0;
	double slack = 0.0;
	double fold_limit = 0.0;
	double first_step = 0.0;
	int walk_steps = 0;

	godot::Transform3D chain(int side, double ext) const;
	double low(const godot::Transform3D &hips_body, int side, double ext) const;
	double solve_knee(const godot::Transform3D &hips_body, int side, double target,
			double h_start, double dir) const;
	double extremum(const godot::Transform3D &hips_body, int side, double target,
			double a, double h_a, double b, double h_b, double c, double h_c) const;
	double refine(const godot::Transform3D &hips_body, int side, double target,
			double a, double h_a, double b, double h_b) const;

protected:
	static void _bind_methods();

public:
	// The runner's toe and heel on the boot, and the walk: (slack, fold limit,
	// first step, steps).
	void configure(const godot::Vector3 &p_toe, const godot::Vector3 &p_heel,
			const godot::Vector4 &p_walk, double p_shin_frac);
	// One leg's rest geometry: the pivots' positions, the boot's rest basis and
	// scale, and the shin's authored euler.
	void set_side(int64_t side, const godot::Vector3 &p_leg_pos, const godot::Vector3 &p_shin_pos,
			const godot::Vector3 &p_foot_pos, const godot::Basis &p_foot_basis,
			const godot::Vector3 &p_foot_scale, const godot::Vector3 &p_shin_base);
	// The gait's cached pose (SkaterLegRig._gait_leg_* / _gait_knee_*).
	void set_pose(const godot::Vector3 &p_leg_l, double p_knee_l,
			const godot::Vector3 &p_leg_r, double p_knee_r);
	// The ankles' weights and the hips' frame against the ice (set_ankle_flatten).
	void set_ankles(double p_ankle_l, double p_ankle_r, double p_level_l, double p_level_r,
			const godot::Basis &p_ice);

	// SkaterLegRig._foot_pose for `side`'s boot.
	godot::Transform3D foot_pose(int64_t side, const godot::Vector3 &leg, double knee,
			double weight, double level) const;
	// SkaterLegRig._chain_low.
	double chain_low(const godot::Transform3D &hips_body, int64_t side, double ext) const;
	// SkaterLegRig._plant_feet: each leg's knee extension, (left, right).
	godot::Vector2 plant(const godot::Transform3D &hips_body, double plant_l, double plant_r) const;
};

} // namespace mitts
