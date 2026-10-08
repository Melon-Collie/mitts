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
// _update_arm: the textured, check-loaded shoulder, the tucked pole,
// TwoBoneIK.reach_root / solve_elbow, the part posing and the deltoid cap's
// orient-and-repose). The GDScript is the reference; the parity fuzz test
// (tests/unit/rules/test_native_arm_rig_parity.gd) keeps them identical.
//
// One call per arm, and it writes the six bones itself: the math is cheaper
// than the crossings, so a kernel that hands values back for GDScript to write
// saves almost nothing. pose() answers false on a degenerate span (hand on the
// elbow) and writes nothing; the rig takes its GDScript path for that arm,
// whose held-pose branches read the skeleton's current poses.
class NativeArmRig : public godot::RefCounted {
	GDCLASS(NativeArmRig, godot::RefCounted)

	godot::ObjectID skeleton_id;
	godot::ObjectID upper_body_id;
	int32_t bone_upper = -1;
	int32_t bone_forearm = -1;
	int32_t bone_cuff = -1;
	int32_t bone_elbow = -1;
	int32_t bone_glove = -1;
	int32_t bone_cap = -1;
	int32_t bone_spine = -1;

	// Per-part pose scale (SkaterArmRig._thickness): X/Y the radius, the
	// bones' Z is the live length.
	godot::Vector3 thick_upper;
	godot::Vector3 thick_forearm;
	godot::Vector3 thick_cuff;
	godot::Vector3 thick_elbow;
	godot::Vector3 thick_glove;
	godot::Vector3 cap_rest_pole;
	double cap_follow = 0.6;
	// The cap bone's scene rest (SkaterArmRig._pos / _scale).
	godot::Vector3 cap_pos;
	godot::Vector3 cap_scale = godot::Vector3(1, 1, 1);

	// The cap's last stable roll and its share of the girdle's give, in the
	// cap's untextured pose frame — read back by the rig for its own reposes.
	godot::Basis cap;
	godot::Vector3 girdle;

protected:
	static void _bind_methods();

public:
	// `bones` is (upper arm, forearm, cuff, elbow, glove, spine).
	void bind(godot::Object *p_skeleton, godot::Object *p_upper_body,
			const godot::PackedInt32Array &p_bones);
	// The cap is the one on this arm's side; `cap_state` is get_cap_state's
	// shape, the rig's current view of it.
	void configure(const godot::Vector3 &p_thick_upper, const godot::Vector3 &p_thick_forearm,
			const godot::Vector3 &p_thick_cuff, const godot::Vector3 &p_thick_elbow,
			const godot::Vector3 &p_thick_glove, const godot::Vector3 &p_cap_rest_pole,
			double p_cap_follow, int32_t p_cap_bone, const godot::Vector3 &p_cap_pos,
			const godot::Vector3 &p_cap_scale, const godot::Transform3D &p_cap_state);

	// `marker` and `hand` are the shoulder and hand markers in UpperBody's
	// frame; `pole` the arm's elbow pole mirrored onto its side, untucked.
	// `lengths` is (upper arm, forearm, working length, girdle slack), `load`
	// (check lead, shoulder half-width, cuff back of the hand).
	bool pose(const godot::Vector3 &marker, const godot::Vector3 &hand,
			const godot::Basis &trunk_texture, const godot::Vector3 &pole,
			const godot::Vector4 &lengths, const godot::Vector3 &load);

	// (cap basis, girdle give) as one Transform3D, so the rig syncs in one read.
	godot::Transform3D get_cap_state() const { return godot::Transform3D(cap, girdle); }
};

} // namespace mitts
