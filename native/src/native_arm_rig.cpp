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

// SkaterArmPoses.glove_basis: the shaft across the palm at the grip angle,
// leaving past the thumb toward the blade, the wrist deviating within its
// range; `roll` turns the fist round the shaft.
Basis glove_basis(const Vector3 &forearm_dir, const Vector3 &shaft, double grip_angle,
		double ulnar_max, double radial_max, double roll) {
	const Basis straight = Basis::looking_at(forearm_dir, up_for_look_at(forearm_dir))
			* Basis(Vector3(1, 0, 0), Math_PI * 0.5);
	if (shaft == Vector3()) {
		return straight;
	}
	Vector3 across = forearm_dir - shaft * forearm_dir.dot(shaft);
	if (across.length_squared() < 0.000001) {
		return straight;
	}
	across = across.normalized();
	const double opening = forearm_dir.angle_to(shaft);
	const double held = opening - Math::clamp(opening - grip_angle, -ulnar_max, radial_max);
	Vector3 hand_axis = shaft * (real_t)Math::cos(held) + across * (real_t)Math::sin(held);
	Vector3 thumb = (shaft - hand_axis * shaft.dot(hand_axis)).normalized();
	if (roll != 0.0) {
		hand_axis = hand_axis.rotated(shaft, (real_t)roll);
		thumb = thumb.rotated(shaft, (real_t)roll);
	}
	return Basis(thumb, -hand_axis, thumb.cross(-hand_axis));
}

// SkaterArmPoses.forearm_twist.
double forearm_twist(const Vector3 &forearm_dir, const Vector3 &thumb, const Vector3 &neutral) {
	const Vector3 across = thumb - forearm_dir * thumb.dot(forearm_dir);
	if (across.length_squared() < 0.000001) {
		return 0.0;
	}
	return across.angle_to(neutral);
}

// SkaterArmPoses.neutral_thumb.
Vector3 neutral_thumb(const Vector3 &shoulder, const Vector3 &elbow, const Vector3 &hand) {
	Vector3 line = hand - shoulder;
	Vector3 fore = hand - elbow;
	if (line.length_squared() < 0.000001 || fore.length_squared() < 0.000001) {
		return Vector3();
	}
	line = line.normalized();
	fore = fore.normalized();
	const Vector3 bend = (elbow - shoulder) - line * (elbow - shoulder).dot(line);
	const Vector3 away = -(bend - fore * bend.dot(fore));
	return away.length_squared() > 0.000001 ? away.normalized() : Vector3();
}

// SkaterArmPoses._ROLL_BISECTIONS / _STEER_BISECTIONS.
constexpr int ROLL_BISECTIONS = 8;
constexpr int STEER_BISECTIONS = 6;

// SkaterArmPoses.grip_roll.
double grip_roll(const Vector3 &forearm_dir, const Vector3 &shaft, double grip_angle,
		double ulnar_max, double radial_max, const Vector3 &neutral, double twist_max,
		double flex_max, double way) {
	if (shaft == Vector3() || neutral == Vector3()) {
		return 0.0;
	}
	const Basis base = glove_basis(forearm_dir, shaft, grip_angle, ulnar_max, radial_max, 0.0);
	const Vector3 thumb = base.get_column(0);
	double twist = forearm_twist(forearm_dir, thumb, neutral);
	if (twist <= twist_max) {
		return 0.0;
	}
	const double off_plane = Math::sin((double)(-base.get_column(1)).angle_to(shaft));
	const double reach = off_plane <= Math::sin(flex_max) ? Math_PI * 0.5
														   : Math::asin(Math::sin(flex_max) / off_plane);
	if (way == 0.0) {
		way = forearm_twist(forearm_dir, thumb.rotated(shaft, (real_t)reach), neutral)
						<= forearm_twist(forearm_dir, thumb.rotated(shaft, (real_t)-reach), neutral)
				? 1.0
				: -1.0;
	}
	const double at_reach = forearm_twist(forearm_dir, thumb.rotated(shaft, (real_t)(way * reach)), neutral);
	if (at_reach > twist_max) {
		return way * reach;
	}
	double lo = 0.0;
	double hi = reach;
	double twist_hi = at_reach;
	for (int i = 0; i < ROLL_BISECTIONS; i++) {
		const double mid = (lo + hi) * 0.5;
		const double t = forearm_twist(forearm_dir, thumb.rotated(shaft, (real_t)(way * mid)), neutral);
		if (t > twist_max) {
			lo = mid;
			twist = t;
		} else {
			hi = mid;
			twist_hi = t;
		}
	}
	return way * Math::lerp(lo, hi, (twist - twist_max) / Math::max(twist - twist_hi, 0.000001));
}

// SkaterArmPoses._elbow_foot / _elbow_offset.
double elbow_foot(double d, double upper_len, double forearm_len) {
	const double span = Math::clamp(d, Math::abs(upper_len - forearm_len), upper_len + forearm_len);
	return (upper_len * upper_len - forearm_len * forearm_len + span * span) / (2.0 * span);
}

double elbow_offset(double d, double upper_len, double forearm_len) {
	const double foot = elbow_foot(d, upper_len, forearm_len);
	return Math::sqrt(Math::max(upper_len * upper_len - foot * foot, 0.0));
}

// SkaterArmPoses.turned_elbow.
Vector3 turned_elbow(const Vector3 &shoulder, const Vector3 &hand, double upper_len,
		double forearm_len, const Vector3 &pole, double turn) {
	const Vector3 d_vec = hand - shoulder;
	const double d = d_vec.length();
	if (d < 0.0001) {
		return shoulder;
	}
	const Vector3 axis = d_vec / (real_t)d;
	return shoulder + axis * (real_t)elbow_foot(d, upper_len, forearm_len)
			+ bend_direction(shoulder, hand, pole).rotated(axis, (real_t)turn)
			* (real_t)elbow_offset(d, upper_len, forearm_len);
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
	ERR_FAIL_COND(p_bones.size() != 7);
	skeleton_id = p_skeleton != nullptr ? ObjectID(p_skeleton->get_instance_id()) : ObjectID();
	bone_upper = p_bones[0];
	bone_forearm = p_bones[1];
	bone_cuff = p_bones[2];
	bone_elbow = p_bones[3];
	bone_glove = p_bones[4];
	bone_spine = p_bones[5];
	bone_torso = p_bones[6];
}

void NativeArmRig::configure(const Vector3 &p_thick_upper, const Vector3 &p_thick_forearm,
		const Vector3 &p_thick_cuff, const Vector3 &p_thick_elbow, const Vector3 &p_thick_glove,
		double p_grip_angle, const Vector4 &wrist, double p_steer_omega) {
	thick_upper = p_thick_upper;
	thick_forearm = p_thick_forearm;
	thick_cuff = p_thick_cuff;
	thick_elbow = p_thick_elbow;
	thick_glove = p_thick_glove;
	grip_angle = p_grip_angle;
	ulnar_max = wrist.x;
	radial_max = wrist.y;
	flex_max = wrist.z;
	twist_max = wrist.w;
	steer_omega = p_steer_omega;
}

void NativeArmRig::configure_torso(const PackedVector2Array &profile, const PackedFloat64Array &sway,
		double x_scale, double z_scale, double p_sleeve_radius, double p_steer_contact) {
	torso_profile = profile;
	torso_sway = sway;
	torso_x_scale = x_scale;
	torso_z_scale = z_scale;
	sleeve_radius = p_sleeve_radius;
	steer_contact = p_steer_contact;
}

// SkaterMeshBuilder.torso_clearance.
double NativeArmRig::torso_clearance(const Vector3 &p) const {
	const int count = torso_profile.size();
	if (count == 0 || (double)p.y > (double)torso_profile[0].x + 0.0001) {
		return INFINITY;
	}
	const int last = count - 1;
	double radius = torso_profile[last].y;
	double sway = torso_sway[last];
	for (int i = 0; i < last; i++) {
		const Vector2 a = torso_profile[i];
		const Vector2 b = torso_profile[i + 1];
		if ((double)p.y >= (double)b.x) {
			const double t = ((double)a.x - (double)p.y) / ((double)a.x - (double)b.x);
			radius = Math::lerp((double)a.y, (double)b.y, t);
			sway = Math::lerp(torso_sway[i], torso_sway[i + 1], t);
			break;
		}
	}
	const Vector2 q(p.x, (real_t)((double)p.z - sway));
	const double span = q.length();
	if (span < 0.000001) {
		return -radius * torso_z_scale;
	}
	const double e = Vector2((real_t)((double)q.x / (radius * torso_x_scale)),
			(real_t)((double)q.y / (radius * torso_z_scale)))
							 .length();
	return span * (1.0 - 1.0 / e);
}

// SkaterArmPoses._depth / _arm_depth.
double NativeArmRig::depth(const Vector3 &p, const Transform3D &to_torso, double unit) const {
	return sleeve_radius - steer_contact - torso_clearance(to_torso.xform(p)) * unit;
}

double NativeArmRig::arm_depth(const Vector3 &shoulder, const Vector3 &elbow, const Vector3 &hand,
		const Transform3D &to_torso, double unit) const {
	return Math::max(depth(elbow, to_torso, unit), Math::max(depth((shoulder + elbow) * 0.5, to_torso, unit),
														   depth(elbow.lerp(hand, 0.4), to_torso, unit)));
}

// SkaterArmPoses.steer_turn.
double NativeArmRig::steer_turn(const Vector3 &shoulder, const Vector3 &hand, double upper_len,
		double forearm_len, const Vector3 &pole, const Vector3 &outward, const Transform3D &torso) const {
	const Vector3 d_vec = hand - shoulder;
	const double d = d_vec.length();
	if (d < 0.0001) {
		return 0.0;
	}
	const Vector3 axis = d_vec / (real_t)d;
	const double h = elbow_offset(d, upper_len, forearm_len);
	const Vector3 foot = shoulder + axis * (real_t)elbow_foot(d, upper_len, forearm_len);
	const Vector3 bend = bend_direction(shoulder, hand, pole);
	const Transform3D to_torso = torso.affine_inverse();
	const double unit = torso.basis.get_scale().x;
	double depth_lo = arm_depth(shoulder, foot + bend * (real_t)h, hand, to_torso, unit);
	if (depth_lo <= 0.0) {
		return 0.0;
	}
	const Vector3 out = outward - axis * outward.dot(axis);
	if (out.length_squared() < 0.000001 || h < 0.0001) {
		return 0.0;
	}
	const double full = bend.signed_angle_to(out.normalized(), axis);
	double depth_hi = arm_depth(shoulder, foot + bend.rotated(axis, (real_t)full) * (real_t)h, hand,
			to_torso, unit);
	if (depth_hi > 0.0) {
		return full;
	}
	double lo = 0.0;
	double hi = 1.0;
	for (int i = 0; i < STEER_BISECTIONS; i++) {
		const double mid = (lo + hi) * 0.5;
		const double dep = arm_depth(shoulder, foot + bend.rotated(axis, (real_t)(full * mid)) * (real_t)h,
				hand, to_torso, unit);
		if (dep > 0.0) {
			lo = mid;
			depth_lo = dep;
		} else {
			hi = mid;
			depth_hi = dep;
		}
	}
	return full * Math::lerp(lo, hi, depth_lo / (depth_lo - depth_hi));
}

// SkaterArmRig._ease through BalanceRules.spring_step, in GDScript's Vector2.
double NativeArmRig::ease(Vector2 &held, double delta, double target) {
	if (delta < 0.0) {
		held = Vector2((real_t)target, 0.0);
		return target;
	}
	const Vector2 x(held.x, 0.0);
	const Vector2 v(held.y, 0.0);
	const Vector2 tgt((real_t)target, 0.0);
	const Vector2 dv = x - tgt;
	const Vector2 c = v + dv * (real_t)steer_omega;
	const double e = Math::exp(-steer_omega * delta);
	const Vector2 x1 = tgt + (dv + c * (real_t)delta) * (real_t)e;
	const Vector2 v1 = (v - c * (real_t)(steer_omega * delta)) * (real_t)e;
	held = Vector2(x1.x, v1.x);
	if (Math::abs((double)x1.x - target) > 0.0001 || Math::abs((double)v1.x) > 0.001) {
		settling = true;
	}
	return x1.x;
}

int NativeArmRig::pose(const Vector3 &marker, const Vector3 &hand, const Vector3 &grip,
		const Transform3D &frame, const Basis &trunk_texture,
		const Vector3 &pole, const Vector4 &lengths, const Vector3 &load, const Vector3 &motion) {
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
	if (skeleton == nullptr || bone_upper < 0) {
		return DEGENERATE;
	}
	settling = false;
	const double lead = load.x;
	const double half_width = load.y;
	const double cuff_back = load.z;
	const double upper_len = lengths.x;
	const double forearm_len = lengths.y;
	const double delta = motion.x;
	const double roll_way = motion.y;
	const double pole_sign = motion.z;
	const double side = SIGN(marker.x);
	const Transform3D spine = skeleton->get_bone_global_pose(bone_spine);
	const Vector3 hand_s = frame.xform(hand);

	// _textured_shoulder, then arm_root.
	const Vector3 rooted = spine.xform(
			trunk_texture.xform(marker + check_load_offset(lead, side, half_width)));
	const Vector3 shoulder_s = reach_root(rooted, hand_s, lengths.z, lengths.w);
	const Vector3 pole_s = spine.basis.xform(tucked_pole(pole, lead, side));
	const double turn = ease(steer, delta, steer_turn(shoulder_s, hand_s, upper_len, forearm_len, pole_s,
			spine.basis.xform(Vector3((real_t)pole_sign, 0.0, 0.0)),
			skeleton->get_bone_global_pose(bone_torso)));
	const Vector3 elbow_s = turned_elbow(shoulder_s, hand_s, upper_len, forearm_len, pole_s, turn);
	const Vector3 forearm_span = hand_s - elbow_s;
	const double forearm_length = forearm_span.length();
	// The GDScript path's held-pose branches (any degenerate part) read the
	// skeleton, so the rig takes it for this arm.
	if ((elbow_s - shoulder_s).length() < 0.0001 || forearm_length < 0.0001
			|| forearm_span.length_squared() < 0.0001) {
		return DEGENERATE;
	}
	skeleton->set_bone_pose(bone_upper, pose_bone(shoulder_s, elbow_s, thick_upper));
	skeleton->set_bone_pose(bone_forearm, pose_bone(elbow_s, hand_s, thick_forearm));

	// _pose_cuff.
	const Vector3 dir = forearm_span / (real_t)forearm_length;
	const Basis twist(Vector3(1, 0, 0), Math_PI * 0.5);
	const Basis along = Basis::looking_at(dir, up_for_look_at(dir)) * twist;
	skeleton->set_bone_pose(bone_cuff,
			Transform3D(along.scaled_local(thick_cuff), hand_s - dir * (real_t)cuff_back));
	// _pose_elbow, its pole the elbow's own bend.
	const Vector3 out = bend_direction(shoulder_s, hand_s, elbow_s - shoulder_s);
	const Vector3 arm_axis = (hand_s - shoulder_s).normalized();
	const Basis pad = out == Vector3() ? Basis() : Basis(arm_axis, out, arm_axis.cross(out));
	skeleton->set_bone_pose(bone_elbow, Transform3D(pad.scaled_local(thick_elbow), elbow_s));
	// _pose_glove, the top fist rolled (its direction is normalized(), the same
	// unit vector).
	const Vector3 shaft_s = frame.basis.xform(grip);
	const Vector3 forearm_dir = forearm_span.normalized();
	double roll_angle = 0.0;
	if (roll_way != 0.0) {
		double target = 0.0;
		if (shaft_s != Vector3()) {
			target = grip_roll(forearm_dir, shaft_s, grip_angle, ulnar_max, radial_max,
					neutral_thumb(shoulder_s, elbow_s, hand_s), twist_max, flex_max, roll_way);
		}
		roll_angle = ease(roll, delta, target);
	}
	const Basis glove = glove_basis(forearm_dir, shaft_s, grip_angle, ulnar_max, radial_max, roll_angle);
	skeleton->set_bone_pose(bone_glove, Transform3D(glove.scaled_local(thick_glove), hand_s));
	return settling ? SETTLING : POSED;
}

void NativeArmRig::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "skeleton", "bones"), &NativeArmRig::bind);
	ClassDB::bind_method(D_METHOD("configure", "thick_upper", "thick_forearm", "thick_cuff",
								 "thick_elbow", "thick_glove", "grip_angle", "wrist", "steer_omega"),
			&NativeArmRig::configure);
	ClassDB::bind_method(D_METHOD("configure_torso", "profile", "sway", "x_scale", "z_scale",
								 "sleeve_radius", "steer_contact"),
			&NativeArmRig::configure_torso);
	ClassDB::bind_method(D_METHOD("pose", "marker", "hand", "grip", "frame", "trunk_texture", "pole",
								 "lengths", "load", "motion"),
			&NativeArmRig::pose);
}

} // namespace mitts
