#pragma once

#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace mitts {

// The arm's two-bone geometry and the elbow's swivel round the torso
// (SkaterArmPoses.swivel_bend), shared by the kernels that pose or measure an
// arm: NativeArmRig draws it, NativeHoldModel scores a hand by it. GDScript is
// the reference; each kernel's parity fuzz holds this against it.

// TwoBoneIK.reach_root.
godot::Vector3 reach_root(const godot::Vector3 &shoulder, const godot::Vector3 &hand, double arm_len,
		double slack);
// TwoBoneIK.bend_direction.
godot::Vector3 bend_direction(const godot::Vector3 &shoulder, const godot::Vector3 &hand,
		const godot::Vector3 &pole_world);
// SkaterArmPoses._elbow_foot / _elbow_offset.
double elbow_foot(double d, double upper_len, double forearm_len);
double elbow_offset(double d, double upper_len, double forearm_len);
// SkaterArmPoses._parabola_floor.
double parabola_floor(double x0, double y0, double x1, double y1, double x2, double y2);
// SkaterArmPoses.elbow_on_circle.
godot::Vector3 elbow_on_circle(const godot::Vector3 &shoulder, const godot::Vector3 &hand,
		double upper_len, double forearm_len, const godot::Vector3 &bend);

struct ArmSwivel {
	// SkaterMeshBuilder's torso (torso_clearance), the sleeve's radius and the
	// contact it is allowed (SkaterArmPoses.SWIVEL_CONTACT_M).
	godot::PackedVector2Array torso_profile;
	godot::PackedFloat64Array torso_sway;
	godot::PackedFloat64Array torso_depth;
	double torso_x_scale = 1.0;
	double torso_z_scale = 1.0;
	double sleeve_radius = 0.0;
	double contact = 0.0;

	// SkaterArmPoses' swivel weights and search (configure).
	double swivel_torso = 0.0;
	double swivel_rest = 0.0;
	double swivel_shoulder = 0.0;
	double swivel_extension_max = 0.0;
	double swivel_wrist = 0.0;
	double swivel_hold = 0.0;
	double swivel_upper_sample = 0.0;
	int swivel_samples = 12;
	int swivel_golden_steps = 0;
	double swivel_free_dot = 1.0;

	void configure_torso(const godot::PackedVector2Array &profile, const godot::PackedFloat64Array &sway,
			const godot::PackedFloat64Array &depth, double x_scale, double z_scale, double p_sleeve_radius,
			double p_contact);
	// (jersey, rest, shoulder, extension limit, wrist, hold, upper-arm sample,
	// samples, golden-section steps, the free rest bend's |cos| off the arm):
	// SkaterArmPoses.SWIVEL_* and SWIVEL_FREE_DOT.
	void configure(const godot::PackedFloat64Array &weights);

	// SkaterMeshBuilder.torso_clearance, torso-local.
	double torso_clearance(const godot::Vector3 &p) const;
	// SkaterArmPoses._depth / _arm_depth.
	double depth(const godot::Vector3 &p, const godot::Transform3D &to_torso, double unit) const;
	double arm_depth(const godot::Vector3 &shoulder, const godot::Vector3 &elbow,
			const godot::Vector3 &hand, const godot::Transform3D &to_torso, double unit) const;
	// SkaterArmPoses.swivel_cost / swivel_bend.
	double swivel_cost(const godot::Vector3 &shoulder, const godot::Vector3 &elbow,
			const godot::Vector3 &hand, const godot::Vector3 &bend, double upper_len,
			const godot::Vector3 &rest_n, const godot::Vector3 &hold, const godot::Vector3 &outward,
			const godot::Vector3 &back, const godot::Transform3D &to_torso, double unit,
			const godot::Vector3 &shaft, const godot::Vector3 &wrist) const;
	godot::Vector3 swivel_bend(const godot::Vector3 &shoulder, const godot::Vector3 &hand,
			double upper_len, double forearm_len, const godot::Vector3 &rest,
			const godot::Vector3 &held, const godot::Vector3 &outward, const godot::Vector3 &back,
			const godot::Transform3D &torso, const godot::Vector3 &shaft,
			const godot::Vector3 &wrist) const;
};

} // namespace mitts
