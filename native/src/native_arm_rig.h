#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

namespace mitts {

// C++ port of one arm in Scripts/actors/skater_arm_rig.gd (SkaterArmRig.
// _update_arm: the textured, check-loaded shoulder, the tucked and blended
// poles, TwoBoneIK.reach_root / solve_elbow, the wrist
// (SkaterArmPoses.place_wrist) and the part posing). The GDScript is the
// reference; the parity fuzz test
// (tests/unit/rules/test_native_arm_rig_parity.gd) keeps them identical.
//
// One call per arm, and it writes the five bones itself: the math is cheaper
// than the crossings, so a kernel that hands values back for GDScript to write
// saves almost nothing. pose() answers false on a degenerate span (hand on the
// elbow) and writes nothing; the rig takes its GDScript path for that arm,
// whose held-pose branches read the skeleton's current poses.
class NativeArmRig : public godot::RefCounted {
	GDCLASS(NativeArmRig, godot::RefCounted)

	godot::ObjectID skeleton_id;
	int32_t bone_upper = -1;
	int32_t bone_forearm = -1;
	int32_t bone_cuff = -1;
	int32_t bone_elbow = -1;
	int32_t bone_glove = -1;
	int32_t bone_spine = -1;

	// Per-part pose scale (SkaterArmRig._thickness): X/Y the radius, the
	// bones' Z is the live length.
	godot::Vector3 thick_upper;
	godot::Vector3 thick_forearm;
	godot::Vector3 thick_cuff;
	godot::Vector3 thick_elbow;
	godot::Vector3 thick_glove;
	// Skater.wrist_break_max_deg, in radians.
	double wrist_break_max = 0.0;

protected:
	static void _bind_methods();

public:
	// `bones` is (upper arm, forearm, cuff, elbow, glove, spine).
	void bind(godot::Object *p_skeleton, const godot::PackedInt32Array &p_bones);
	void configure(const godot::Vector3 &p_thick_upper, const godot::Vector3 &p_thick_forearm,
			const godot::Vector3 &p_thick_cuff, const godot::Vector3 &p_thick_elbow,
			const godot::Vector3 &p_thick_glove, double p_wrist_break_max);

	// `marker` and `hand` are the shoulder and hand markers in UpperBody's
	// frame; `grip` the shaft's direction at the hand in that frame, zero off
	// the stick; `frame` UpperBody as drawn, in skeleton space
	// (Skater.drawn_upper_body); `pole` the arm's elbow pole mirrored onto its
	// side, untucked.
	// `aside` the second pole on its side (Skater.arm_pole_aside_local) and its
	// weight (TwoBoneIK.blended_pole), zero weight for none.
	// `lengths` is (upper arm, forearm, working length, girdle slack), `load`
	// (check lead, shoulder half-width, cuff back of the wrist, hand length).
	bool pose(const godot::Vector3 &marker, const godot::Vector3 &hand,
			const godot::Vector3 &grip, const godot::Transform3D &frame,
			const godot::Basis &trunk_texture, const godot::Vector3 &pole,
			const godot::Vector4 &aside, const godot::Vector4 &lengths,
			const godot::Vector4 &load);
};

} // namespace mitts
