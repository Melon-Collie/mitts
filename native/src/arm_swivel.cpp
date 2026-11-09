#include "arm_swivel.h"

#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace mitts {

namespace {

// SkaterArmPoses._GOLDEN.
constexpr double GOLDEN = 0.6180339887;

} // namespace

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

// SkaterArmPoses._elbow_foot / _elbow_offset.
double elbow_foot(double d, double upper_len, double forearm_len) {
	const double span = Math::clamp(d, Math::abs(upper_len - forearm_len), upper_len + forearm_len);
	return (upper_len * upper_len - forearm_len * forearm_len + span * span) / (2.0 * span);
}

double elbow_offset(double d, double upper_len, double forearm_len) {
	const double foot = elbow_foot(d, upper_len, forearm_len);
	return Math::sqrt(Math::max(upper_len * upper_len - foot * foot, 0.0));
}

// SkaterArmPoses._parabola_floor.
double parabola_floor(double x0, double y0, double x1, double y1, double x2, double y2) {
	const double d0 = (y1 - y0) / (x1 - x0);
	const double d1 = (y2 - y1) / (x2 - x1);
	const double curve = (d1 - d0) / (x2 - x0);
	if (curve <= 0.0) {
		return x1;
	}
	return Math::clamp((x0 + x1) * 0.5 - d0 / (2.0 * curve), x0, x2);
}

// SkaterArmPoses.elbow_on_circle.
Vector3 elbow_on_circle(const Vector3 &shoulder, const Vector3 &hand, double upper_len,
		double forearm_len, const Vector3 &bend) {
	const Vector3 d_vec = hand - shoulder;
	const double d = d_vec.length();
	if (d < 0.0001) {
		return shoulder;
	}
	return shoulder + d_vec / (real_t)d * (real_t)elbow_foot(d, upper_len, forearm_len)
			+ bend * (real_t)elbow_offset(d, upper_len, forearm_len);
}

void ArmSwivel::configure_torso(const PackedVector2Array &profile, const PackedFloat64Array &sway,
		const PackedFloat64Array &depth, double x_scale, double z_scale, double p_sleeve_radius,
		double p_contact) {
	torso_profile = profile;
	torso_sway = sway;
	torso_depth = depth;
	torso_x_scale = x_scale;
	torso_z_scale = z_scale;
	sleeve_radius = p_sleeve_radius;
	contact = p_contact;
}

void ArmSwivel::configure(const PackedFloat64Array &weights) {
	ERR_FAIL_COND(weights.size() != 10);
	swivel_torso = weights[0];
	swivel_rest = weights[1];
	swivel_shoulder = weights[2];
	swivel_extension_max = weights[3];
	swivel_wrist = weights[4];
	swivel_hold = weights[5];
	swivel_upper_sample = weights[6];
	swivel_samples = MAX((int)weights[7], 1);
	swivel_golden_steps = (int)weights[8];
	swivel_free_dot = weights[9];
}

// SkaterMeshBuilder.torso_clearance.
double ArmSwivel::torso_clearance(const Vector3 &p) const {
	const int count = torso_profile.size();
	if (count == 0 || (double)p.y > (double)torso_profile[0].x + 0.0001) {
		return INFINITY;
	}
	const int last = count - 1;
	double radius = torso_profile[last].y;
	double sway = torso_sway[last];
	double deep = torso_depth[last];
	for (int i = 0; i < last; i++) {
		const Vector2 a = torso_profile[i];
		const Vector2 b = torso_profile[i + 1];
		if ((double)p.y >= (double)b.x) {
			const double t = ((double)a.x - (double)p.y) / ((double)a.x - (double)b.x);
			radius = Math::lerp((double)a.y, (double)b.y, t);
			sway = Math::lerp(torso_sway[i], torso_sway[i + 1], t);
			deep = Math::lerp(torso_depth[i], torso_depth[i + 1], t);
			break;
		}
	}
	const Vector2 q(p.x, (real_t)((double)p.z - sway));
	const double span = q.length();
	const double z_radius = radius * torso_z_scale * deep;
	if (span < 0.000001) {
		return -MIN(radius * torso_x_scale, z_radius);
	}
	const double e = Vector2((real_t)((double)q.x / (radius * torso_x_scale)),
			(real_t)((double)q.y / z_radius))
							 .length();
	return span * (1.0 - 1.0 / e);
}

// SkaterArmPoses._depth / _arm_depth.
double ArmSwivel::depth(const Vector3 &p, const Transform3D &to_torso, double unit) const {
	return sleeve_radius - contact - torso_clearance(to_torso.xform(p)) * unit;
}

double ArmSwivel::arm_depth(const Vector3 &shoulder, const Vector3 &elbow, const Vector3 &hand,
		const Transform3D &to_torso, double unit) const {
	return Math::max(depth(elbow, to_torso, unit),
			Math::max(depth(shoulder.lerp(elbow, (real_t)swivel_upper_sample), to_torso, unit),
					depth(elbow.lerp(hand, 0.4), to_torso, unit)));
}

// SkaterArmPoses.swivel_cost.
double ArmSwivel::swivel_cost(const Vector3 &shoulder, const Vector3 &elbow, const Vector3 &hand,
		const Vector3 &bend, double upper_len, const Vector3 &rest_n, const Vector3 &hold,
		const Vector3 &outward, const Vector3 &back, const Transform3D &to_torso, double unit,
		const Vector3 &shaft, const Vector3 &wrist) const {
	double cost = swivel_torso * Math::max(arm_depth(shoulder, elbow, hand, to_torso, unit), 0.0);
	cost += swivel_rest * (1.0 - (double)bend.dot(rest_n));
	const Vector3 upper = (elbow - shoulder) / (real_t)upper_len;
	const double behind = upper.dot(back);
	cost += swivel_shoulder * (Math::max(Math::asin(Math::clamp(behind, -1.0, 1.0)) - swivel_extension_max, 0.0)
			+ Math::max(behind, 0.0) * Math::max(-(double)upper.dot(outward), 0.0));
	if (shaft != Vector3()) {
		const Vector3 fore = hand - elbow;
		if (fore.length_squared() > 0.000001) {
			const double deviation = (double)fore.angle_to(shaft) - (double)wrist.x;
			cost += swivel_wrist * (Math::max(deviation - (double)wrist.z, 0.0)
					+ Math::max(-(double)wrist.y - deviation, 0.0));
		}
	}
	if (hold != Vector3()) {
		cost += swivel_hold * (1.0 - (double)bend.dot(hold));
	}
	return cost;
}

// SkaterArmPoses.swivel_bend.
Vector3 ArmSwivel::swivel_bend(const Vector3 &shoulder, const Vector3 &hand, double upper_len,
		double forearm_len, const Vector3 &rest, const Vector3 &held, const Vector3 &outward,
		const Vector3 &back, const Transform3D &torso, const Vector3 &shaft,
		const Vector3 &wrist) const {
	const Vector3 d_vec = hand - shoulder;
	const double d = d_vec.length();
	if (d < 0.0001) {
		return Vector3();
	}
	const Vector3 axis = d_vec / (real_t)d;
	const double h = elbow_offset(d, upper_len, forearm_len);
	const Vector3 foot = shoulder + axis * (real_t)elbow_foot(d, upper_len, forearm_len);
	Vector3 hold = held - axis * held.dot(axis);
	hold = hold.length_squared() > 0.000001 ? hold.normalized() : Vector3();
	const Vector3 ref = bend_direction(shoulder, hand, rest);
	const Transform3D to_torso = torso.affine_inverse();
	const double unit = torso.basis.get_scale().x;
	const Vector3 rest_n = rest.normalized();
	const double rest_cost = swivel_rest * (1.0 - (double)ref.dot(rest_n));
	if (swivel_cost(shoulder, foot + ref * (real_t)h, hand, ref, upper_len, rest_n, Vector3(), outward,
				back, to_torso, unit, shaft, wrist) <= rest_cost
			&& Math::abs((double)rest_n.dot(axis)) <= swivel_free_dot) {
		return ref;
	}
	const double step = Math_TAU / swivel_samples;
	int best = 0;
	double best_cost = INFINITY;
	for (int k = 0; k < swivel_samples; k++) {
		const Vector3 bend = ref.rotated(axis, (real_t)(step * k));
		const double cost = swivel_cost(shoulder, foot + bend * (real_t)h, hand, bend, upper_len, rest_n,
				hold, outward, back, to_torso, unit, shaft, wrist);
		if (cost < best_cost) {
			best_cost = cost;
			best = k;
		}
	}
	double a = step * (best - 1);
	double b = step * (best + 1);
	double c = b - GOLDEN * (b - a);
	double e = a + GOLDEN * (b - a);
	Vector3 bend_c = ref.rotated(axis, (real_t)c);
	Vector3 bend_e = ref.rotated(axis, (real_t)e);
	double cost_c = swivel_cost(shoulder, foot + bend_c * (real_t)h, hand, bend_c, upper_len, rest_n,
			Vector3(), outward, back, to_torso, unit, shaft, wrist);
	double cost_e = swivel_cost(shoulder, foot + bend_e * (real_t)h, hand, bend_e, upper_len, rest_n,
			Vector3(), outward, back, to_torso, unit, shaft, wrist);
	for (int i = 0; i < swivel_golden_steps; i++) {
		if (cost_c < cost_e) {
			b = e;
			e = c;
			cost_e = cost_c;
			c = b - GOLDEN * (b - a);
			bend_c = ref.rotated(axis, (real_t)c);
			cost_c = swivel_cost(shoulder, foot + bend_c * (real_t)h, hand, bend_c, upper_len, rest_n,
					Vector3(), outward, back, to_torso, unit, shaft, wrist);
		} else {
			a = c;
			c = e;
			cost_c = cost_e;
			e = a + GOLDEN * (b - a);
			bend_e = ref.rotated(axis, (real_t)e);
			cost_e = swivel_cost(shoulder, foot + bend_e * (real_t)h, hand, bend_e, upper_len, rest_n,
					Vector3(), outward, back, to_torso, unit, shaft, wrist);
		}
	}
	const double m = (a + b) * 0.5;
	const Vector3 bend_m = ref.rotated(axis, (real_t)m);
	const double cost_m = swivel_cost(shoulder, foot + bend_m * (real_t)h, hand, bend_m, upper_len, rest_n,
			Vector3(), outward, back, to_torso, unit, shaft, wrist);
	return ref.rotated(axis, (real_t)parabola_floor(c, cost_c, m, cost_m, e, cost_e));
}

} // namespace mitts
