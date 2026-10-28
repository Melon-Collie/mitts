#include "native_arm_rig.h"

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

// TwoBoneIK.bend_direction.
Vector3 bend_direction(const Vector3 &shoulder, const Vector3 &hand, const Vector3 &pole_world) {
	const Vector3 d_vec = hand - shoulder;
	const double d = d_vec.length();
	if (d < 0.0001) {
		return Vector3();
	}
	const Vector3 axis = d_vec / (real_t)d;
	Vector3 pole_dir = pole_world - axis * pole_world.dot(axis);
	if (pole_dir.length() < 0.0001) {
		const Vector3 fallback = Math::abs(axis.y) < 0.9 ? Vector3(0, -1, 0) : Vector3(0, 0, -1);
		pole_dir = fallback - axis * fallback.dot(axis);
	}
	return pole_dir.normalized();
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
	return foot + bend_direction(shoulder, hand, pole_world) * (real_t)h;
}

// SkaterArmRig.swing.
Basis swing(const Vector3 &from, const Vector3 &to) {
	Vector3 axis = from.cross(to);
	const double s = axis.length();
	const double c = from.dot(to);
	if (s < 1e-6) {
		if (c > 0.0) {
			return Basis();
		}
		axis = from.cross(Math::abs(from.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, -1));
		return Basis(axis.normalized(), Math_PI);
	}
	return Basis(axis / (real_t)s, (real_t)Math::atan2(s, c));
}

// SkaterMeshBuilder.CAP_TO_PRISM.
const Basis CAP_TO_PRISM(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0));

// SkaterArmRig._arm_frame.
Basis arm_frame(const Basis &cap, const Vector3 &span) {
	const Basis prism = cap * CAP_TO_PRISM;
	if (span.length_squared() < 1e-8) {
		return prism;
	}
	return Basis(Quaternion(-cap.get_column(1).normalized(), span.normalized())) * prism;
}

// SkaterArmRig._pose_prism, for a non-degenerate span.
Transform3D pose_prism(const Vector3 &a, const Vector3 &b, const Vector3 &thickness,
		const Basis &prism_frame) {
	const Vector3 span = b - a;
	const double length = span.length();
	const Vector3 center = (a + b) * 0.5;
	Vector3 bone_scale = thickness;
	bone_scale.z = (real_t)length;
	return Transform3D(prism_frame.scaled_local(bone_scale), center);
}

// SkaterArmRig.glove_basis.
Basis glove_basis(const Vector3 &forearm_dir, const Vector3 &grip, double max_bend) {
	const Basis straight = Basis::looking_at(forearm_dir, up_for_look_at(forearm_dir))
			* Basis(Vector3(1, 0, 0), Math_PI * 0.5);
	if (grip == Vector3()) {
		return straight;
	}
	const double across = forearm_dir.dot(grip);
	Vector3 square = forearm_dir - grip * (real_t)across;
	if (square.length_squared() < 0.0001) {
		return straight;
	}
	square = square.normalized();
	Vector3 hand_axis = forearm_dir;
	const Vector3 hinge = forearm_dir.cross(square);
	if (hinge.length_squared() > 1e-8) {
		hand_axis = forearm_dir.rotated(hinge.normalized(),
				(real_t)Math::min(Math::asin(Math::clamp(Math::abs(across), 0.0, 1.0)), max_bend));
	}
	Vector3 knuckles = grip - hand_axis * grip.dot(hand_axis);
	if (knuckles.length_squared() < 0.0001) {
		return straight;
	}
	knuckles = knuckles.normalized();
	if (knuckles.dot(straight.get_column(0)) < 0.0) {
		knuckles = -knuckles;
	}
	return Basis(knuckles, -hand_axis, knuckles.cross(-hand_axis));
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

void NativeArmRig::bind(Object *p_skeleton, const PackedInt32Array &p_bones) {
	ERR_FAIL_COND(p_bones.size() != 6);
	skeleton_id = p_skeleton != nullptr ? ObjectID(p_skeleton->get_instance_id()) : ObjectID();
	bone_upper = p_bones[0];
	bone_forearm = p_bones[1];
	bone_cuff = p_bones[2];
	bone_elbow = p_bones[3];
	bone_glove = p_bones[4];
	bone_spine = p_bones[5];
}

void NativeArmRig::configure(const Vector3 &p_thick_upper, const Vector3 &p_thick_forearm,
		const Vector3 &p_thick_cuff, const Vector3 &p_thick_elbow, const Vector3 &p_thick_glove,
		int32_t p_cap_bone, const Vector3 &p_cap_pos, const Vector3 &p_cap_scale, const Transform3D &p_cap_state,
		double p_wrist_break_max, int32_t p_deltoid_bone, const Basis &p_cap_rest,
		double p_deltoid_share) {
	thick_upper = p_thick_upper;
	thick_forearm = p_thick_forearm;
	thick_cuff = p_thick_cuff;
	thick_elbow = p_thick_elbow;
	thick_glove = p_thick_glove;
	bone_cap = p_cap_bone;
	cap_pos = p_cap_pos;
	cap_scale = p_cap_scale;
	cap = p_cap_state.basis;
	girdle = p_cap_state.origin;
	wrist_break_max = p_wrist_break_max;
	bone_deltoid = p_deltoid_bone;
	cap_rest = p_cap_rest;
	deltoid_share = p_deltoid_share;
}

bool NativeArmRig::pose(const Vector3 &marker, const Vector3 &hand, const Vector3 &grip,
		const Transform3D &frame, const Basis &trunk_texture,
		const Vector3 &pole, const Vector4 &lengths, const Vector3 &load) {
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
	if (skeleton == nullptr || bone_cap < 0) {
		return false;
	}
	const double lead = load.x;
	const double half_width = load.y;
	const double cuff_back = load.z;
	const double upper_len = lengths.x;
	const double forearm_len = lengths.y;
	const double side = SIGN(marker.x);
	const Transform3D spine = skeleton->get_bone_global_pose(bone_spine);
	const Vector3 hand_s = frame.xform(hand);

	// _textured_shoulder, then arm_root.
	const Vector3 rooted = spine.xform(
			trunk_texture.xform(marker + check_load_offset(lead, side, half_width)));
	const Vector3 shoulder_s = reach_root(rooted, hand_s, lengths.z, lengths.w);
	const Vector3 pole_s = spine.basis.xform(tucked_pole(pole, lead, side));
	const Vector3 elbow_s = solve_elbow(shoulder_s, hand_s, upper_len, forearm_len, pole_s);
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

	// _orient_shoulder_cap: swung from the rest hang, no twist.
	const Transform3D to_spine = spine.affine_inverse();
	const Vector3 arm_dir = to_untextured.xform(to_spine.xform(elbow_s) - to_spine.xform(shoulder_s));
	if (arm_dir.length_squared() >= 0.0001) {
		cap = swing(-cap_rest.get_column(1), arm_dir.normalized()) * cap_rest;
	}
	// repose_bone for a cap and its deltoid.
	const Vector3 origin = cap_pos + check_load_offset(lead, SIGN(cap_pos.x), half_width) + girdle;
	const Basis half(cap_rest.get_quaternion().slerp(cap.get_quaternion(), (real_t)deltoid_share));
	skeleton->set_bone_pose(bone_deltoid,
			Transform3D(trunk_texture, Vector3()) * Transform3D(half.scaled_local(cap_scale), origin));
	skeleton->set_bone_pose(bone_cap,
			Transform3D(trunk_texture, Vector3()) * Transform3D(cap.scaled_local(cap_scale), origin));

	// _pose_arm_chain.
	const Basis cap_s = spine.basis.orthonormalized() * trunk_texture * cap;
	const Vector3 upper_span = elbow_s - shoulder_s;
	const Basis upper_frame = arm_frame(cap_s, upper_span);
	Quaternion bend;
	if (upper_span.length_squared() > 1e-8 && forearm_span.length_squared() > 1e-8) {
		bend = Quaternion(upper_span.normalized(), forearm_span.normalized());
	}
	skeleton->set_bone_pose(bone_upper, pose_prism(shoulder_s, elbow_s, thick_upper, upper_frame));
	skeleton->set_bone_pose(bone_forearm,
			pose_prism(elbow_s, hand_s, thick_forearm, Basis(bend) * upper_frame));
	skeleton->set_bone_pose(bone_elbow, Transform3D(
			(Basis(Quaternion().slerp(bend, 0.5)) * upper_frame).scaled_local(thick_elbow), elbow_s));

	// _pose_cuff.
	const Vector3 dir = forearm_span / (real_t)forearm_length;
	const Basis twist(Vector3(1, 0, 0), Math_PI * 0.5);
	const Basis along = Basis::looking_at(dir, up_for_look_at(dir)) * twist;
	skeleton->set_bone_pose(bone_cuff,
			Transform3D(along.scaled_local(thick_cuff), hand_s - dir * (real_t)cuff_back));
	// _pose_glove (its direction is normalized(), the same unit vector).
	const Basis glove = glove_basis(forearm_span.normalized(),
			frame.basis.xform(grip), wrist_break_max);
	skeleton->set_bone_pose(bone_glove, Transform3D(glove.scaled_local(thick_glove), hand_s));
	return true;
}

void NativeArmRig::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "skeleton", "bones"), &NativeArmRig::bind);
	ClassDB::bind_method(D_METHOD("configure", "thick_upper", "thick_forearm", "thick_cuff",
								 "thick_elbow", "thick_glove", "cap_bone", "cap_pos", "cap_scale", "cap_state", "wrist_break_max",
								 "deltoid_bone", "cap_rest", "deltoid_share"),
			&NativeArmRig::configure);
	ClassDB::bind_method(D_METHOD("pose", "marker", "hand", "grip", "frame", "trunk_texture", "pole",
								 "lengths", "load"),
			&NativeArmRig::pose);
	ClassDB::bind_method(D_METHOD("get_cap_state"), &NativeArmRig::get_cap_state);
}

} // namespace mitts
