#include "native_hem_flaps.h"

#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/quaternion.hpp>

using namespace godot;

namespace mitts {

void NativeHemFlaps::bind(Object *p_skeleton, const PackedInt32Array &p_bones) {
	skeleton_id = p_skeleton != nullptr ? ObjectID(p_skeleton->get_instance_id()) : ObjectID();
	ERR_FAIL_COND(p_bones.size() != 8);
	bone_torso = p_bones[0];
	bone_tail = p_bones[1];
	bone_pelvis = p_bones[2];
	bone_leg[0] = p_bones[3];
	bone_leg[1] = p_bones[4];
	bone_thigh[0] = p_bones[5];
	bone_thigh[1] = p_bones[6];
	bone_columns = p_bones[7];
}

void NativeHemFlaps::configure(const PackedVector3Array &p_drape, const PackedFloat32Array &p_hips,
		const PackedFloat32Array &p_tuck, const PackedFloat64Array &p_pelvis,
		const PackedFloat64Array &p_tunables, const PackedInt32Array &p_counts) {
	ERR_FAIL_COND(p_tunables.size() != 10 || p_counts.size() != 2);
	columns = (int)p_hips.size();
	ERR_FAIL_COND(columns == 0 || p_drape.size() != STATIONS * columns || p_tuck.size() != columns
			|| p_pelvis.size() % 3 != 0);
	rest.assign(p_drape.ptr(), p_drape.ptr() + p_drape.size());
	hips_share.assign(p_hips.ptr(), p_hips.ptr() + columns);
	tuck_share.assign(p_tuck.ptr(), p_tuck.ptr() + columns);
	pelvis_profile.assign(p_pelvis.ptr(), p_pelvis.ptr() + p_pelvis.size());
	gravity = p_tunables[0];
	shape_hz = p_tunables[1];
	ring_stiffness = p_tunables[2];
	damping_per_s = p_tunables[3];
	margin = p_tunables[4];
	max_step = p_tunables[5];
	thigh_length = p_tunables[6];
	thigh_radius_m = p_tunables[7];
	pelvis_xs = p_tunables[8];
	pelvis_zs = p_tunables[9];
	iterations = p_counts[0];
	colliding_iterations = p_counts[1];
	anchor.assign(columns, Vector3());
	started = false;
}

Vector3 NativeHemFlaps::rest_bend(int k, const Basis &drape) const {
	return anchor[k] + drape.xform(rest_at(BEND, k) - rest_at(0, k));
}

Vector3 NativeHemFlaps::rest_hem(int k, const Basis &drape) const {
	return anchor[k] + drape.xform(rest_at(HEM, k) - rest_at(0, k));
}

// SkaterHemColliders._closest_on_thigh.
Vector3 NativeHemFlaps::closest_on_thigh(int i, const Vector3 &p) const {
	const Vector3 a = thigh_top[i];
	const Vector3 ab = thigh_bottom[i] - a;
	const double t = Math::clamp((double)(p - a).dot(ab) / Math::max((double)ab.length_squared(), 1e-8),
			0.0, 1.0);
	return a + ab * (real_t)t;
}

void NativeHemFlaps::pelvis_ring(double y, float &r_radius, float &r_sway) const {
	// Stations are (y, radius) as the profile's Vector2 holds them, so in single
	// precision, and the sway as its Array[float] does.
	for (size_t i = 0; i + 1 < pelvis_profile.size() / 3; ++i) {
		const double *hi = &pelvis_profile[i * 3];
		const double *lo = &pelvis_profile[(i + 1) * 3];
		if (y <= hi[0] && y >= lo[0]) {
			const double t = (hi[0] - y) / Math::max(hi[0] - lo[0], 1e-6);
			r_radius = (float)(hi[1] + (lo[1] - hi[1]) * t);
			r_sway = (float)(hi[2] + (lo[2] - hi[2]) * t);
			return;
		}
	}
	r_radius = -1.0f;
	r_sway = 0.0f;
}

// SkaterHemColliders.push_out, at the solver's margin.
Vector3 NativeHemFlaps::push_out(Vector3 p) const {
	for (int i = 0; i < 2; ++i) {
		const Vector3 c = closest_on_thigh(i, p);
		const Vector3 d = p - c;
		const double reach = (double)thigh_radius[i] + margin;
		if ((double)d.length_squared() < reach * reach) {
			const double dist = d.length();
			p = c + (dist > 1e-6 ? d / (real_t)dist : Vector3(0, 0, -1)) * (real_t)reach;
		}
	}
	const Vector3 q = pelvis_inv.xform(p);
	float ring_r = 0.0f;
	float ring_sway = 0.0f;
	pelvis_ring(q.y, ring_r, ring_sway);
	if (ring_r > 0.0f) {
		const double r = (double)ring_r + margin;
		const double e = Math::pow((double)q.x / (r * pelvis_xs), 2.0)
				+ Math::pow(((double)q.z - (double)ring_sway) / (r * pelvis_zs), 2.0);
		if (e < 1.0 && e > 1e-8) {
			const double f = 1.0 / Math::sqrt(e);
			p = pelvis.xform(Vector3((real_t)(q.x * f), q.y,
					(real_t)((double)ring_sway + ((double)q.z - (double)ring_sway) * f)));
		}
	}
	return p;
}

void NativeHemFlaps::start(const Basis &drape) {
	bend.assign(columns, Vector3());
	hem.assign(columns, Vector3());
	for (int k = 0; k < columns; ++k) {
		bend[k] = rest_bend(k, drape);
		hem[k] = rest_hem(k, drape);
	}
	bend_prev = bend;
	hem_prev = hem;
	last_dt = 0.0;
	started = true;
}

// SkaterHemFlaps._relax and _spacing.
void NativeHemFlaps::relax(const Basis &drape, bool collide) {
	for (int k = 0; k < columns; ++k) {
		const Vector3 a = anchor[k];
		const double upper = drape.xform(rest_at(BEND, k) - rest_at(0, k)).length();
		bend[k] = a + (bend[k] - a).normalized() * (real_t)upper;
		const double lower = drape.xform(rest_at(HEM, k) - rest_at(BEND, k)).length();
		const Vector3 d = hem[k] - bend[k];
		const Vector3 fix = d * (real_t)(1.0 - lower / Math::max((double)d.length(), 1e-6)) * (real_t)0.5;
		bend[k] += fix;
		hem[k] -= fix;
	}
	for (int k = 0; k < columns; ++k) {
		const int n = (k + 1) % columns;
		const double bend_len = drape.xform(rest_at(BEND, n) - rest_at(BEND, k)).length();
		const Vector3 db = bend[n] - bend[k];
		const Vector3 fix_bend = db * (real_t)(1.0 - bend_len / Math::max((double)db.length(), 1e-6))
				* (real_t)0.5 * (real_t)ring_stiffness;
		bend[k] += fix_bend;
		bend[n] -= fix_bend;
		const double hem_len = drape.xform(rest_at(HEM, n) - rest_at(HEM, k)).length();
		const Vector3 dh = hem[n] - hem[k];
		const Vector3 fix_hem = dh * (real_t)(1.0 - hem_len / Math::max((double)dh.length(), 1e-6))
				* (real_t)0.5 * (real_t)ring_stiffness;
		hem[k] += fix_hem;
		hem[n] -= fix_hem;
	}
	if (!collide) {
		return;
	}
	for (int k = 0; k < columns; ++k) {
		const Vector3 a = anchor[k];
		bend[k] = push_out(bend[k]);
		hem[k] = push_out(hem[k]);
		Vector3 m = (a + bend[k]) * (real_t)0.5;
		bend[k] += (push_out(m) - m) * (real_t)2.0;
		m = (bend[k] + hem[k]) * (real_t)0.5;
		const Vector3 push = push_out(m) - m;
		bend[k] += push;
		hem[k] += push;
	}
	for (int k = 0; k < columns; ++k) {
		const int n = (k + 1) % columns;
		Vector3 m = (bend[k] + bend[n]) * (real_t)0.5;
		Vector3 push = push_out(m) - m;
		bend[k] += push;
		bend[n] += push;
		m = (hem[k] + hem[n]) * (real_t)0.5;
		push = push_out(m) - m;
		hem[k] += push;
		hem[n] += push;
	}
}

// SkaterHemFlaps.step.
void NativeHemFlaps::step(double p_delta, const Vector3 &p_g, bool p_write) {
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
	ERR_FAIL_NULL(skeleton);
	ERR_FAIL_COND(columns == 0);
	const double dt = Math::min(p_delta, max_step);
	if (dt <= 0.0) {
		return;
	}
	const Transform3D torso = skeleton->get_bone_global_pose(bone_torso);
	const Transform3D tail = skeleton->get_bone_global_pose(bone_tail);
	// SkaterHemColliders.update.
	for (int i = 0; i < 2; ++i) {
		const Transform3D leg = skeleton->get_bone_global_pose(bone_leg[i]);
		const Basis thigh = skeleton->get_bone_global_pose(bone_thigh[i]).basis;
		thigh_top[i] = leg.origin;
		thigh_bottom[i] = leg.xform(Vector3(0, (real_t)-thigh_length, 0));
		thigh_radius[i] = (float)(thigh_radius_m * (double)thigh.get_column(0).length());
	}
	pelvis = skeleton->get_bone_global_pose(bone_pelvis);
	pelvis_inv = pelvis.affine_inverse();
	for (int k = 0; k < columns; ++k) {
		anchor[k] = torso.xform(rest_at(0, k)).lerp(tail.xform(rest_at(0, k)), hips_share[k]);
	}
	const Basis drape = tail.basis;
	if (!started) {
		start(drape);
	}
	const Vector3 drive = (p_g + drape.get_column(1).normalized() * (real_t)gravity) * (real_t)dt * (real_t)dt;
	const double carry = Math::exp(-damping_per_s * dt) * (last_dt > 0.0 ? dt / last_dt : 1.0);
	const double pull = Math::min(Math::pow(Math_TAU * shape_hz * dt, 2.0), 1.0);
	for (int k = 0; k < columns; ++k) {
		const Vector3 b = bend[k];
		bend[k] += (b - bend_prev[k]) * (real_t)carry + drive;
		bend[k] += (rest_bend(k, drape) - bend[k]) * (real_t)pull;
		bend_prev[k] = b;
		const Vector3 h = hem[k];
		hem[k] += (h - hem_prev[k]) * (real_t)carry + drive;
		hem[k] += (rest_hem(k, drape) - hem[k]) * (real_t)pull;
		hem_prev[k] = h;
	}
	last_dt = dt;
	for (int it = 0; it < iterations; ++it) {
		relax(drape, it >= iterations - colliding_iterations);
	}
	for (int k = 0; k < columns; ++k) {
		const float t = tuck_share[k];
		if (t > 0.0f) {
			bend[k] = bend[k].lerp(rest_bend(k, drape), t);
			hem[k] = hem[k].lerp(rest_hem(k, drape), t);
		}
	}
	if (!p_write) {
		return;
	}
	// SkaterHemFlaps._write_bones / _write_segment.
	for (int k = 0; k < columns; ++k) {
		for (int joint = 0; joint < 2; ++joint) {
			const Vector3 top = joint == 0 ? anchor[k] : bend[k];
			const Vector3 bottom = joint == 0 ? bend[k] : hem[k];
			const Vector3 &rest_top = rest_at(joint == 0 ? 0 : BEND, k);
			const Vector3 &rest_bottom = rest_at(joint == 0 ? BEND : HEM, k);
			const Vector3 from = drape.xform(rest_bottom - rest_top).normalized();
			const Vector3 to = (bottom - top).normalized();
			Basis turn;
			if (from.dot(to) < 0.99999) {
				turn = Basis(Quaternion(from, to));
			}
			const Basis basis = turn * drape;
			skeleton->set_bone_pose(bone_columns + k * 2 + joint,
					Transform3D(basis, top - basis.xform(rest_top)));
		}
	}
}

PackedVector3Array NativeHemFlaps::get_points() const {
	PackedVector3Array out;
	for (size_t k = 0; k < bend.size(); ++k) {
		const size_t n = (k + 1) % bend.size();
		out.append(bend[k]);
		out.append(hem[k]);
		out.append((anchor[k] + bend[k]) * (real_t)0.5);
		out.append((bend[k] + hem[k]) * (real_t)0.5);
		out.append((bend[k] + bend[n]) * (real_t)0.5);
		out.append((hem[k] + hem[n]) * (real_t)0.5);
	}
	return out;
}

PackedVector3Array NativeHemFlaps::get_state() const {
	PackedVector3Array out;
	for (const std::vector<Vector3> *part : { &bend, &hem, &bend_prev, &hem_prev }) {
		for (const Vector3 &v : *part) {
			out.append(v);
		}
	}
	return out;
}

void NativeHemFlaps::set_state(const PackedVector3Array &p_state, double p_last_dt) {
	ERR_FAIL_COND(columns == 0 || p_state.size() != 4 * columns);
	const Vector3 *s = p_state.ptr();
	bend.assign(s, s + columns);
	hem.assign(s + columns, s + 2 * columns);
	bend_prev.assign(s + 2 * columns, s + 3 * columns);
	hem_prev.assign(s + 3 * columns, s + 4 * columns);
	last_dt = p_last_dt;
	started = true;
}

void NativeHemFlaps::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "skeleton", "bones"), &NativeHemFlaps::bind);
	ClassDB::bind_method(D_METHOD("configure", "drape", "hips", "tuck", "pelvis", "tunables", "counts"),
			&NativeHemFlaps::configure);
	ClassDB::bind_method(D_METHOD("step", "delta", "g", "write"), &NativeHemFlaps::step);
	ClassDB::bind_method(D_METHOD("get_points"), &NativeHemFlaps::get_points);
	ClassDB::bind_method(D_METHOD("get_state"), &NativeHemFlaps::get_state);
	ClassDB::bind_method(D_METHOD("set_state", "state", "last_dt"), &NativeHemFlaps::set_state);
}

} // namespace mitts
