#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

namespace mitts {

// C++ port of one arm in Scripts/actors/skater_arm_rig.gd (SkaterArmRig.
// _update_arm: the textured, check-loaded shoulder, the tucked pole, the elbow
// steered round the torso and eased (SkaterArmPoses.steer_turn), the part
// posing, and the glove's sword grip with the top fist's roll eased
// (glove_basis, grip_roll). The GDScript is the reference; the parity fuzz test
// (tests/unit/rules/test_native_arm_rig_parity.gd) keeps them identical.
//
// One call per arm, and it writes the five bones itself: the math is cheaper
// than the crossings, so a kernel that hands values back for GDScript to write
// saves almost nothing. It owns the arm's two eased angles (the elbow's turn
// and the fist's roll), as the rig's _steer and _roll do on its own path.
// pose() answers DEGENERATE on a degenerate span (hand on the elbow) and writes
// nothing; the rig takes its GDScript path for that arm, whose held-pose
// branches read the skeleton's current poses. SETTLING says an eased angle has
// not reached its target, for the rig's rebuild gate.
class NativeArmRig : public godot::RefCounted {
	GDCLASS(NativeArmRig, godot::RefCounted)

	godot::ObjectID skeleton_id;
	int32_t bone_upper = -1;
	int32_t bone_forearm = -1;
	int32_t bone_cuff = -1;
	int32_t bone_elbow = -1;
	int32_t bone_glove = -1;
	int32_t bone_spine = -1;
	int32_t bone_torso = -1;

	// Per-part pose scale (SkaterArmRig._thickness): X/Y the radius, the
	// bones' Z is the live length.
	godot::Vector3 thick_upper;
	godot::Vector3 thick_forearm;
	godot::Vector3 thick_cuff;
	godot::Vector3 thick_elbow;
	godot::Vector3 thick_glove;
	// The glove's grip angle, and the wrist's ulnar, radial and flexion ranges
	// and the forearm's twist (Skater's, radians).
	double grip_angle = 0.0;
	double ulnar_max = 0.0;
	double radial_max = 0.0;
	double flex_max = 0.0;
	double twist_max = 0.0;
	// SkaterArmRig.steer_omega.
	double steer_omega = 0.0;

	// SkaterMeshBuilder's torso (torso_clearance) and the steer's contact
	// allowance (SkaterArmPoses._depth).
	godot::PackedVector2Array torso_profile;
	godot::PackedFloat64Array torso_sway;
	double torso_x_scale = 1.0;
	double torso_z_scale = 1.0;
	double sleeve_radius = 0.0;
	double steer_contact = 0.0;

	// The eased angles, (angle, rate), as GDScript's PackedVector2Array holds them.
	godot::Vector2 steer;
	godot::Vector2 roll;
	bool settling = false;

	double torso_clearance(const godot::Vector3 &p) const;
	double depth(const godot::Vector3 &p, const godot::Transform3D &to_torso, double unit) const;
	double arm_depth(const godot::Vector3 &shoulder, const godot::Vector3 &elbow,
			const godot::Vector3 &hand, const godot::Transform3D &to_torso, double unit) const;
	double steer_turn(const godot::Vector3 &shoulder, const godot::Vector3 &hand, double upper_len,
			double forearm_len, const godot::Vector3 &pole, const godot::Vector3 &outward,
			const godot::Transform3D &torso) const;
	double ease(godot::Vector2 &held, double delta, double target);

protected:
	static void _bind_methods();

public:
	enum Result {
		DEGENERATE = 0,
		POSED = 1,
		SETTLING = 2,
	};

	// `bones` is (upper arm, forearm, cuff, elbow, glove, spine, torso).
	void bind(godot::Object *p_skeleton, const godot::PackedInt32Array &p_bones);
	// `wrist` is (ulnar, radial, flexion, forearm twist), radians.
	void configure(const godot::Vector3 &p_thick_upper, const godot::Vector3 &p_thick_forearm,
			const godot::Vector3 &p_thick_cuff, const godot::Vector3 &p_thick_elbow,
			const godot::Vector3 &p_thick_glove, double p_grip_angle, const godot::Vector4 &wrist,
			double p_steer_omega);
	void configure_torso(const godot::PackedVector2Array &profile, const godot::PackedFloat64Array &sway,
			double x_scale, double z_scale, double p_sleeve_radius, double p_steer_contact);

	// `marker` and `hand` are the shoulder and hand markers in UpperBody's
	// frame; `grip` the shaft's direction at the hand in that frame, zero off
	// the stick; `frame` UpperBody as drawn, in skeleton space
	// (Skater.drawn_upper_body); `pole` the arm's elbow pole mirrored onto its
	// side, untucked.
	// `lengths` is (upper arm, forearm, working length, girdle slack), `load`
	// (check lead, shoulder half-width, cuff back of the hand), `motion`
	// (the frame's delta, below 0 to land the eased angles at once; the way the
	// fist rolls, 0 for none, SkaterArmPoses.knuckles_forward; the pole's side).
	int pose(const godot::Vector3 &marker, const godot::Vector3 &hand,
			const godot::Vector3 &grip, const godot::Transform3D &frame,
			const godot::Basis &trunk_texture, const godot::Vector3 &pole,
			const godot::Vector4 &lengths, const godot::Vector3 &load, const godot::Vector3 &motion);
};

} // namespace mitts
