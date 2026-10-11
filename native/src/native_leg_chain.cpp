#include "native_leg_chain.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cmath>

using namespace godot;

namespace mitts {

// The longest knee walk the samples are held for; configure's step count must
// stay within it.
static constexpr int MAX_WALK = 32;

// ── GDScript @GlobalScope semantics (double precision) ──

static inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

static inline double maxd(double a, double b) {
	return a > b ? a : b;
}

static inline double mind(double a, double b) {
	return a < b ? a : b;
}

static inline bool equal_approx(double a, double b) {
	if (a == b) {
		return true;
	}
	double tolerance = CMP_EPSILON * std::abs(a);
	if (tolerance < CMP_EPSILON) {
		tolerance = CMP_EPSILON;
	}
	return std::abs(a - b) < tolerance;
}

static inline bool zero_approx(double s) {
	return std::abs(s) < CMP_EPSILON;
}

// ── Binding surface ──

void NativeLegChain::configure(const Vector3 &p_toe, const Vector3 &p_heel, const Vector4 &p_walk,
		double p_shin_frac) {
	runner_toe = p_toe;
	runner_heel = p_heel;
	slack = p_walk.x;
	fold_limit = p_walk.y;
	first_step = p_walk.z;
	walk_steps = (int)p_walk.w;
	ERR_FAIL_COND_MSG(walk_steps > MAX_WALK, "NativeLegChain: the knee walk is longer than MAX_WALK.");
	shin_frac = p_shin_frac;
}

void NativeLegChain::set_side(int64_t side, const Vector3 &p_leg_pos, const Vector3 &p_shin_pos,
		const Vector3 &p_foot_pos, const Basis &p_foot_basis, const Vector3 &p_foot_scale,
		const Vector3 &p_shin_base) {
	ERR_FAIL_INDEX(side, 2);
	Side &s = sides[side];
	s.leg_pos = p_leg_pos;
	s.shin_pos = p_shin_pos;
	s.foot_pos = p_foot_pos;
	s.foot_basis = p_foot_basis;
	s.foot_scale = p_foot_scale;
	s.shin_base = p_shin_base;
}

void NativeLegChain::set_pose(const Vector3 &p_leg_l, double p_knee_l, const Vector3 &p_leg_r,
		double p_knee_r) {
	sides[0].gait_leg = p_leg_l;
	sides[0].gait_knee = p_knee_l;
	sides[1].gait_leg = p_leg_r;
	sides[1].gait_knee = p_knee_r;
}

void NativeLegChain::set_ankles(double p_ankle_l, double p_ankle_r, double p_level_l, double p_level_r,
		const Basis &p_ice) {
	sides[0].ankle = p_ankle_l;
	sides[1].ankle = p_ankle_r;
	sides[0].level = p_level_l;
	sides[1].level = p_level_r;
	ice = p_ice;
}

// ── SkaterLegRig ──

Transform3D NativeLegChain::foot_pose(int64_t side, const Vector3 &leg, double knee, double weight,
		double level) const {
	ERR_FAIL_INDEX_V(side, 2, Transform3D());
	const Side &s = sides[side];
	if (weight <= 0.0 && level <= 0.0) {
		return Transform3D(s.foot_basis.scaled_local(s.foot_scale), s.foot_pos);
	}
	const Basis shin = Basis::from_euler(Vector3(knee, s.shin_base.y, s.shin_base.z));
	const Basis posed = Basis::from_euler(leg) * shin;
	Basis target = posed;
	if (level > 0.0) {
		const Vector3 heading = (ice * Basis(Vector3(0, 1, 0), leg.y)).xform(Vector3(0, 0, -1));
		const Vector3 along(heading.x, 0.0, heading.z);
		Vector3 down = (ice * posed).xform(Vector3(0, -1, 0));
		down -= along * down.dot(along) / (real_t)maxd(along.length_squared(), 1e-12);
		if (along.length_squared() > 1e-8 && down.length_squared() > 1e-8) {
			const Basis laid = Basis::looking_at(along, -down);
			target = posed.slerp(ice.inverse() * laid, level);
		}
	}
	if (weight > 0.0) {
		const Basis square = Basis::from_euler(Vector3(0.0, leg.y, 0.0)) * Basis::from_euler(Vector3(0.0, s.shin_base.y, s.shin_base.z));
		target = target.slerp(square, weight);
	}
	const Basis give_back = (posed.inverse() * target).orthonormalized();
	const Basis basis = give_back * s.foot_basis;
	return Transform3D(basis.scaled_local(s.foot_scale), s.foot_pos);
}

Transform3D NativeLegChain::chain(int side, double ext) const {
	const Side &s = sides[side];
	const Vector3 leg = s.gait_leg - Vector3(ext * shin_frac, 0.0, 0.0);
	const double knee = s.gait_knee + ext;
	return Transform3D(Basis::from_euler(leg), s.leg_pos) * Transform3D(Basis::from_euler(Vector3(knee, s.shin_base.y, s.shin_base.z)), s.shin_pos) * foot_pose(side, leg, knee, s.ankle, s.level);
}

double NativeLegChain::low(const Transform3D &hips_body, int side, double ext) const {
	const Transform3D boot = hips_body * chain(side, ext);
	return mind(boot.xform(runner_toe).y, boot.xform(runner_heel).y);
}

double NativeLegChain::chain_low(const Transform3D &hips_body, int64_t side, double ext) const {
	ERR_FAIL_INDEX_V(side, 2, 0.0);
	return low(hips_body, (int)side, ext);
}

Vector2 NativeLegChain::plant(const Transform3D &hips_body, double plant_l, double plant_r) const {
	// _plant is a PackedFloat32Array, and _plant_ext holds the answer in one.
	const float plants[2] = { (float)plant_l, (float)plant_r };
	float ext[2] = { 0.0f, 0.0f };
	const double h_l = low(hips_body, 0, 0.0);
	const double h_r = low(hips_body, 1, 0.0);
	const int sup = h_l <= h_r ? 0 : 1;
	const int other = 1 - sup;
	const double h_sup = mind(h_l, h_r);
	const double h_other = maxd(h_l, h_r);
	if (plants[other] <= 0.0f || h_other - h_sup <= slack) {
		return Vector2(0.0, 0.0);
	}
	const double e_other = solve_knee(hips_body, other, h_sup, h_other, 1.0);
	const double reached = low(hips_body, other, e_other);
	double e_sup = 0.0;
	if (reached - h_sup > slack) {
		e_sup = solve_knee(hips_body, sup, reached, h_sup, -1.0);
	}
	ext[other] = (float)(e_other * plants[other]);
	ext[sup] = (float)(e_sup * plants[sup]);
	return Vector2(ext[0], ext[1]);
}

double NativeLegChain::solve_knee(const Transform3D &hips_body, int side, double target, double h_start,
		double dir) const {
	const double knee = sides[side].gait_knee;
	const double bound = dir > 0.0 ? maxd(-knee, 0.0) : mind(-fold_limit - knee, 0.0);
	double best_e = 0.0;
	double best_err = std::abs(h_start - target);
	int best_i = 0;
	float es[MAX_WALK];
	float hs[MAX_WALK];
	es[0] = 0.0f;
	hs[0] = (float)h_start;
	int count = 1;
	double step = first_step;
	double e = 0.0;
	while (e != bound && count < walk_steps && count < MAX_WALK) {
		e = clampd(e + dir * step, mind(bound, 0.0), maxd(bound, 0.0));
		const double h = low(hips_body, side, e);
		const double prev_e = es[count - 1];
		const double prev_h = hs[count - 1];
		if ((prev_h - target) * (h - target) <= 0.0) {
			return refine(hips_body, side, target, prev_e, prev_h, e, h);
		}
		es[count] = (float)e;
		hs[count] = (float)h;
		count++;
		if (std::abs(h - target) < best_err) {
			best_err = std::abs(h - target);
			best_e = e;
			best_i = count - 1;
		}
		step *= 2.0;
	}
	if (best_i <= 0 || best_i >= count - 1) {
		return best_e;
	}
	return extremum(hips_body, side, target, es[best_i - 1], hs[best_i - 1],
			best_e, hs[best_i], es[best_i + 1], hs[best_i + 1]);
}

double NativeLegChain::extremum(const Transform3D &hips_body, int side, double target,
		double a, double h_a, double b, double h_b, double c, double h_c) const {
	const double den = (b - a) * (h_b - h_c) - (b - c) * (h_b - h_a);
	if (zero_approx(den)) {
		return b;
	}
	double v = b - 0.5 * ((b - a) * (b - a) * (h_b - h_c) - (b - c) * (b - c) * (h_b - h_a)) / den;
	v = clampd(v, mind(a, c), maxd(a, c));
	const double h_v = low(hips_body, side, v);
	return std::abs(h_v - target) < std::abs(h_b - target) ? v : b;
}

double NativeLegChain::refine(const Transform3D &hips_body, int side, double target,
		double a, double h_a, double b, double h_b) const {
	for (int step = 0; step < 4; step++) {
		if (equal_approx(h_a, h_b)) {
			break;
		}
		const double e = a + (target - h_a) * (b - a) / (h_b - h_a);
		const double h = low(hips_body, side, e);
		if (std::abs(h - target) < slack) {
			return e;
		}
		if ((h_a - target) * (h - target) <= 0.0) {
			b = e;
			h_b = h;
		} else {
			a = e;
			h_a = h;
		}
	}
	return std::abs(h_b - target) < std::abs(h_a - target) ? b : a;
}

void NativeLegChain::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "toe", "heel", "walk", "shin_frac"), &NativeLegChain::configure);
	ClassDB::bind_method(D_METHOD("set_side", "side", "leg_pos", "shin_pos", "foot_pos", "foot_basis",
								 "foot_scale", "shin_base"),
			&NativeLegChain::set_side);
	ClassDB::bind_method(D_METHOD("set_pose", "leg_l", "knee_l", "leg_r", "knee_r"), &NativeLegChain::set_pose);
	ClassDB::bind_method(D_METHOD("set_ankles", "ankle_l", "ankle_r", "level_l", "level_r", "ice"),
			&NativeLegChain::set_ankles);
	ClassDB::bind_method(D_METHOD("foot_pose", "side", "leg", "knee", "weight", "level"), &NativeLegChain::foot_pose);
	ClassDB::bind_method(D_METHOD("chain_low", "hips_body", "side", "ext"), &NativeLegChain::chain_low);
	ClassDB::bind_method(D_METHOD("plant", "hips_body", "plant_l", "plant_r"), &NativeLegChain::plant);
}

} // namespace mitts
