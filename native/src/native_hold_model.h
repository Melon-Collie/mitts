#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "arm_swivel.h"

namespace mitts {

// C++ port of Scripts/actors/skater_hold_model.gd (SkaterHoldModel.evaluate and
// project): whether a body holds the stick with its top hand at `hand` and the
// blade's heel at `blade`, and the held hand — the anchor moved over the sphere
// the stick allows round the blade by the least that holds it. GDScript is the
// reference; tests/unit/rules/test_native_hold_model_parity.gd holds them
// together. The body comes in packed each call (SkaterHoldModel.pack): it is
// the tick's, rebuilt every tick.
class NativeHoldModel : public godot::RefCounted {
	GDCLASS(NativeHoldModel, godot::RefCounted)

	ArmSwivel swivel;
	// SkaterHoldModel's constants (configure_hold).
	int shaft_samples = 8;
	double shaft_from = 0.12;
	double shaft_to = 0.6;
	double shaft_radius = 0.015;
	int project_steps = 24;
	double project_settled = 0.0005;
	double project_lie = 0.0;
	double normal_step = 0.01;
	double clearance_cap = 1.0;

	// The body of the call in hand (set_body).
	godot::Vector3 shoulders[2];
	godot::Vector3 rest_poles[2];
	godot::Vector3 outward[2];
	godot::Vector3 back;
	godot::Vector3 wrists[2];
	godot::Transform3D torso;
	godot::Transform3D to_torso;
	double unit = 1.0;
	double upper_len = 0.33;
	double forearm_len = 0.33;
	double reach = 0.64;
	double slack = 0.06;
	double elbow_flex_max = 2.5;
	double fist_radius = 0.07;
	double knob_extend = 0.09;
	double knob_radius = 0.035;
	double spacing = 0.12;
	double grip = 0.25;
	double hand_below_shoulder = INFINITY;

	struct ArmHold {
		double reach_past = 0.0;
		double sleeve = 0.0;
		double slip = 0.0;
		godot::Vector3 elbow;
	};
	struct Report {
		double fist = 0.0;
		double fold = 0.0;
		double high = 0.0;
		double knob = 0.0;
		double shaft = 0.0;
		ArmHold top;
		ArmHold bottom;
		double bottom_grip = 0.0;
		godot::Vector3 bottom_hand;
		double total() const;
	};

	bool set_body(const godot::PackedVector3Array &vectors, const godot::Transform3D &p_torso,
			const godot::PackedFloat64Array &scalars);
	double clearance(const godot::Vector3 &p) const;
	double capped(const godot::Vector3 &p) const;
	void arm(int which, const godot::Vector3 &hand, const godot::Vector3 &shaft, ArmHold &out) const;
	void score(const godot::Vector3 &hand, const godot::Vector3 &blade, Report &out) const;
	godot::Vector3 push(const godot::Vector3 &hand, const godot::Vector3 &blade, const Report &held) const;
	godot::Vector3 out_of_jersey(const godot::Vector3 &p) const;
	godot::Vector3 on_sphere(const godot::Vector3 &blade, const godot::Vector3 &p, double length,
			double lie0) const;

protected:
	static void _bind_methods();

public:
	// As NativeArmRig's: SkaterMeshBuilder's torso section, the sleeve and its
	// contact; SkaterArmPoses' swivel weights.
	void configure_torso(const godot::PackedVector2Array &profile, const godot::PackedFloat64Array &sway,
			const godot::PackedFloat64Array &depth, double x_scale, double z_scale,
			double p_sleeve_radius, double p_contact);
	void configure_swivel(const godot::PackedFloat64Array &weights);
	// (SHAFT_SAMPLES, SHAFT_FROM, SHAFT_TO, SHAFT_RADIUS_M, PROJECT_STEPS,
	// PROJECT_SETTLED_M, PROJECT_LIE_DEG in radians, _NORMAL_STEP_M,
	// _CLEARANCE_CAP_M): SkaterHoldModel's.
	void configure_hold(const godot::PackedFloat64Array &constants);

	// `vectors` and `scalars` as SkaterHoldModel.pack lays them out.
	godot::Vector3 project(const godot::PackedVector3Array &vectors, const godot::Transform3D &p_torso,
			const godot::PackedFloat64Array &scalars, const godot::Vector3 &anchor,
			const godot::Vector3 &blade, double lie);
	// (fist, fold, high, knob, shaft, top reach, top sleeve, bottom reach,
	// bottom sleeve, bottom grip, total): SkaterHoldModel.Report's, for the
	// parity test.
	godot::PackedFloat64Array evaluate(const godot::PackedVector3Array &vectors,
			const godot::Transform3D &p_torso, const godot::PackedFloat64Array &scalars,
			const godot::Vector3 &hand, const godot::Vector3 &blade);
};

} // namespace mitts
