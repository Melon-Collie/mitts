#include "native_arm_rig.h"

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace mitts {

namespace {

// SkaterArmRig.up_for_look_at.
Vector3 up_for_look_at(const Vector3 &direction) {
	if (Math::abs(direction.normalized().y) > 0.99) {
		return Vector3(0, 0, -1);
	}
	return Vector3(0, 1, 0);
}

// TwoBoneIK.reach_root.
Vector3 reach_root(const Vector3 &shoulder, const Vector3 &hand, double arm_len, double slack) {
	const Vector3 d_vec = hand - shoulder;
	const double d = d_vec.length();
	const double over = d - arm_len;
	if (over <= 0.0 || d < 0.0001) {
		return shoulder;
	}
	return shoulder + d_vec / (real_t)d * (real_t)Math::min(over, slack);
}

// TwoBoneIK.solve_elbow.
Vector3 solve_elbow(const Vector3 &shoulder, const Vector3 &hand, double upper_len,
		double forearm_len, const Vector3 &pole_world) {
	const Vector3 d_vec = hand - shoulder;
	const double d = d_vec.length();
	if (d < 0.0001) {
		return shoulder;
	}
	const Vector3 axis = d_vec / (real_t)d;
	const double d_clamped = Math::clamp(d, Math::abs(upper_len - forearm_len), upper_len + forearm_len);
	const double foot_t = (upper_len * upper_len - forearm_len * forearm_len + d_clamped * d_clamped)
			/ (2.0 * d_clamped);
	const double h_sq = upper_len * upper_len - foot_t * foot_t;
	const double h = Math::sqrt(Math::max(h_sq, 0.0));
	const Vector3 foot = shoulder + axis * (real_t)foot_t;
	Vector3 pole_dir = pole_world - axis * pole_world.dot(axis);
	if (pole_dir.length() < 0.0001) {
		const Vector3 fallback = Math::abs(axis.y) < 0.9 ? Vector3(0, -1, 0) : Vector3(0, 0, -1);
		pole_dir = fallback - axis * fallback.dot(axis);
	}
	return foot + pole_dir.normalized() * (real_t)h;
}

// SkaterArmRig._pose_bone, for a non-degenerate span.
Transform3D pose_bone(const Vector3 &a, const Vector3 &b, const Vector3 &thickness) {
	const Vector3 span = b - a;
	const double length = span.length();
	const Vector3 center = (a + b) * 0.5;
	Vector3 bone_scale = thickness;
	const Vector3 dir = span / (real_t)length;
	bone_scale.z = (real_t)length;
	return Transform3D(Basis::looking_at(dir, up_for_look_at(dir)).scaled_local(bone_scale), center);
}

// CheckStanceRules.load_offset(side_load(lead, side), side, half_width).
Vector3 check_load_offset(double lead, double side, double half_width) {
	const double load = Math::max(lead * side, 0.0);
	if (load <= 0.0) {
		return Vector3();
	}
	const double reach = half_width * Math::min(load, 1.0);
	return Vector3((real_t)(-side * 0.30 * reach), (real_t)(-0.22 * reach), (real_t)(-0.45 * reach));
}

// CheckStanceRules.tucked_pole(pole, side_load(lead, side)).
Vector3 tucked_pole(const Vector3 &pole, double lead, double side) {
	const double load = Math::max(lead * side, 0.0);
	if (load <= 0.0) {
		return pole;
	}
	return pole.lerp(Vector3((real_t)SIGN(pole.x) * (real_t)0.12, pole.y, (real_t)0.55),
			(real_t)Math::min(load, 1.0));
}

} // namespace

void NativeArmRig::bind(Object *p_skeleton, Object *p_upper_body, const PackedInt32Array &p_bones) {
	ERR_FAIL_COND(p_bones.size() != 6);
	skeleton_id = p_skeleton != nullptr ? ObjectID(p_skeleton->get_instance_id()) : ObjectID();
	upper_body_id = p_upper_body != nullptr ? ObjectID(p_upper_body->get_instance_id()) : ObjectID();
	bone_upper = p_bones[0];
	bone_forearm = p_bones[1];
	bone_cuff = p_bones[2];
	bone_elbow = p_bones[3];
	bone_glove = p_bones[4];
	bone_spine = p_bones[5];
}

void NativeArmRig::configure(const Vector3 &p_thick_upper, const Vector3 &p_thick_forearm,
		const Vector3 &p_thick_cuff, const Vector3 &p_thick_elbow, const Vector3 &p_thick_glove,
		const Vector3 &p_cap_rest_pole, double p_cap_follow, int32_t p_cap_bone,
		const Vector3 &p_cap_pos, const Vector3 &p_cap_scale, const Transform3D &p_cap_state) {
	thick_upper = p_thick_upper;
	thick_forearm = p_thick_forearm;
	thick_cuff = p_thick_cuff;
	thick_elbow = p_thick_elbow;
	thick_glove = p_thick_glove;
	cap_rest_pole = p_cap_rest_pole;
	cap_follow = p_cap_follow;
	bone_cap = p_cap_bone;
	cap_pos = p_cap_pos;
	cap_scale = p_cap_scale;
	cap = p_cap_state.basis;
	girdle = p_cap_state.origin;
}

bool NativeArmRig::pose(const Vector3 &marker, const Vector3 &hand, const Basis &trunk_texture,
		const Vector3 &pole, const Vector4 &lengths, const Vector3 &load) {
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
	Node3D *upper_body = Object::cast_to<Node3D>(ObjectDB::get_instance(upper_body_id));
	if (skeleton == nullptr || upper_body == nullptr || bone_cap < 0) {
		return false;
	}
	const double lead = load.x;
	const double half_width = load.y;
	const double cuff_back = load.z;
	const double upper_len = lengths.x;
	const double forearm_len = lengths.y;
	const double side = SIGN(marker.x);
	const Transform3D spine = skeleton->get_bone_global_pose(bone_spine);
	const Vector3 hand_s = upper_body->get_transform().xform(hand);

	// _textured_shoulder, then arm_root.
	const Vector3 rooted = spine.xform(
			trunk_texture.xform(marker + check_load_offset(lead, side, half_width)));
	const Vector3 shoulder_s = reach_root(rooted, hand_s, lengths.z, lengths.w);
	const Vector3 elbow_s = solve_elbow(shoulder_s, hand_s, upper_len, forearm_len,
			spine.basis.xform(tucked_pole(pole, lead, side)));
	const Vector3 forearm_span = hand_s - elbow_s;
	const double forearm_length = forearm_span.length();
	// The GDScript path's held-pose branches (any degenerate part) read the
	// skeleton, so the rig takes it for this arm.
	if ((elbow_s - shoulder_s).length() < 0.0001 || forearm_length < 0.0001
			|| forearm_span.length_squared() < 0.0001) {
		return false;
	}
	const Basis to_untextured = trunk_texture.transposed();
	girdle = to_untextured.xform(spine.basis.inverse().xform(shoulder_s - rooted));
	skeleton->set_bone_pose(bone_upper, pose_bone(shoulder_s, elbow_s, thick_upper));
	skeleton->set_bone_pose(bone_forearm, pose_bone(elbow_s, hand_s, thick_forearm));

	// _pose_cuff.
	const Vector3 dir = forearm_span / (real_t)forearm_length;
	const Basis twist(Vector3(1, 0, 0), Math_PI * 0.5);
	const Basis along = Basis::looking_at(dir, up_for_look_at(dir)) * twist;
	skeleton->set_bone_pose(bone_cuff,
			Transform3D(along.scaled_local(thick_cuff), hand_s - dir * (real_t)cuff_back));
	// _pose_ball.
	skeleton->set_bone_pose(bone_elbow, Transform3D(Basis().scaled(thick_elbow), elbow_s));
	// _pose_glove (its direction is normalized(), the same unit vector).
	const Vector3 glove_dir = forearm_span.normalized();
	const Basis glove_basis = Basis::looking_at(glove_dir, up_for_look_at(glove_dir)) * twist;
	skeleton->set_bone_pose(bone_glove, Transform3D(glove_basis.scaled_local(thick_glove), hand_s));

	// _orient_shoulder_cap: an invalid direction keeps the last stable roll.
	const Transform3D to_spine = spine.affine_inverse();
	const Vector3 arm_dir = to_untextured.xform(to_spine.xform(elbow_s) - to_spine.xform(shoulder_s));
	if (arm_dir.length_squared() >= 0.0001) {
		Vector3 rest = cap_rest_pole.normalized();
		rest.x *= (real_t)side;
		const Vector3 cap_pole = -rest.slerp(arm_dir.normalized(), (real_t)cap_follow);
		Vector3 x_axis = Vector3(1, 0, 0) - cap_pole * cap_pole.x;
		if (x_axis.length_squared() >= 0.01) {
			x_axis = x_axis.normalized();
			cap = Basis(x_axis, cap_pole, x_axis.cross(cap_pole)).orthonormalized();
		}
	}
	// repose_bone for a cap.
	const Vector3 origin = cap_pos + check_load_offset(lead, SIGN(cap_pos.x), half_width) + girdle;
	skeleton->set_bone_pose(bone_cap,
			Transform3D(trunk_texture, Vector3()) * Transform3D(cap.scaled_local(cap_scale), origin));
	return true;
}

void NativeArmRig::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "skeleton", "upper_body", "bones"), &NativeArmRig::bind);
	ClassDB::bind_method(D_METHOD("configure", "thick_upper", "thick_forearm", "thick_cuff",
								 "thick_elbow", "thick_glove", "cap_rest_pole", "cap_follow",
								 "cap_bone", "cap_pos", "cap_scale", "cap_state"),
			&NativeArmRig::configure);
	ClassDB::bind_method(D_METHOD("pose", "marker", "hand", "trunk_texture", "pole", "lengths",
								 "load"),
			&NativeArmRig::pose);
	ClassDB::bind_method(D_METHOD("get_cap_state"), &NativeArmRig::get_cap_state);
}

} // namespace mitts
