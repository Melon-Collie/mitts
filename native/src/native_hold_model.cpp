#include "native_hold_model.h"

#include <cmath>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

namespace mitts {

namespace {

// BottomHandIK.reachable_grip, in GDScript's Vector2.
Vector2 reachable_grip(const Vector3 &shoulder, const Vector3 &top, const Vector3 &blade, double grip,
		double reach, double spacing) {
	const Vector3 u = blade - top;
	const Vector3 w = top - shoulder;
	const double a = u.length_squared();
	if (a < 0.000001) {
		return Vector2((real_t)grip, (real_t)Math::max((double)w.length() - reach, 0.0));
	}
	const double floor_g = Math::min(spacing / Math::sqrt(a), 1.0);
	const double b = u.dot(w);
	const double c = (double)w.length_squared() - reach * reach;
	const double disc = b * b - a * c;
	if (disc >= 0.0) {
		const double root = Math::sqrt(disc);
		const double lo = Math::max((-b - root) / a, floor_g);
		const double hi = Math::min((-b + root) / a, 1.0);
		if (lo <= hi) {
			return Vector2((real_t)Math::clamp(grip, lo, hi), 0.0);
		}
	}
	const double nearest = Math::clamp(-b / a, floor_g, 1.0);
	return Vector2((real_t)nearest,
			(real_t)Math::max((double)(w + u * (real_t)nearest).length() - reach, 0.0));
}

} // namespace

double NativeHoldModel::Report::total() const {
	return fist + fold + high + knob + shaft + top.reach_past + top.sleeve + bottom.reach_past
			+ bottom.sleeve;
}

void NativeHoldModel::configure_torso(const PackedVector2Array &profile, const PackedFloat64Array &sway,
		const PackedFloat64Array &depth, double x_scale, double z_scale, double p_sleeve_radius,
		double p_contact) {
	swivel.configure_torso(profile, sway, depth, x_scale, z_scale, p_sleeve_radius, p_contact);
}

void NativeHoldModel::configure_swivel(const PackedFloat64Array &weights) {
	swivel.configure(weights);
}

void NativeHoldModel::configure_hold(const PackedFloat64Array &constants) {
	ERR_FAIL_COND(constants.size() != 9);
	shaft_samples = MAX((int)constants[0], 2);
	shaft_from = constants[1];
	shaft_to = constants[2];
	shaft_radius = constants[3];
	project_steps = (int)constants[4];
	project_settled = constants[5];
	project_lie = constants[6];
	normal_step = constants[7];
	clearance_cap = constants[8];
}

bool NativeHoldModel::set_body(const PackedVector3Array &vectors, const Transform3D &p_torso,
		const PackedFloat64Array &scalars) {
	ERR_FAIL_COND_V(vectors.size() != 9 || scalars.size() != 11, false);
	shoulders[0] = vectors[0];
	shoulders[1] = vectors[1];
	rest_poles[0] = vectors[2];
	rest_poles[1] = vectors[3];
	outward[0] = vectors[4];
	outward[1] = vectors[5];
	back = vectors[6];
	wrists[0] = vectors[7];
	wrists[1] = vectors[8];
	torso = p_torso;
	to_torso = p_torso.affine_inverse();
	unit = p_torso.basis.get_scale().x;
	upper_len = scalars[0];
	forearm_len = scalars[1];
	reach = scalars[2];
	slack = scalars[3];
	elbow_flex_max = scalars[4];
	fist_radius = scalars[5];
	knob_extend = scalars[6];
	knob_radius = scalars[7];
	spacing = scalars[8];
	grip = scalars[9];
	hand_below_shoulder = scalars[10];
	return true;
}

// SkaterHoldModel._clearance / _capped.
double NativeHoldModel::clearance(const Vector3 &p) const {
	return swivel.torso_clearance(to_torso.xform(p)) * unit;
}

double NativeHoldModel::capped(const Vector3 &p) const {
	return Math::min(clearance(p), clearance_cap);
}

// SkaterHoldModel._arm.
void NativeHoldModel::arm(int which, const Vector3 &hand, const Vector3 &shaft, ArmHold &out) const {
	const Vector3 root = reach_root(shoulders[which], hand, reach, slack);
	out.reach_past = Math::max((double)root.distance_to(hand) - upper_len - forearm_len, 0.0);
	const Vector3 wrist = wrists[which];
	const Vector3 bend = swivel.swivel_bend(root, hand, upper_len, forearm_len, rest_poles[which],
			Vector3(), outward[which], back, torso, shaft, wrist);
	out.elbow = elbow_on_circle(root, hand, upper_len, forearm_len, bend);
	out.sleeve = Math::max(swivel.arm_depth(root, out.elbow, hand, to_torso, unit), 0.0);
	out.slip = 0.0;
	const Vector3 fore = hand - out.elbow;
	if (fore.length_squared() > 0.000001) {
		const double deviation = (double)fore.angle_to(shaft) - (double)wrist.x;
		out.slip = Math::max(deviation - (double)wrist.z, 0.0) + Math::max(-(double)wrist.y - deviation, 0.0);
	}
}

// SkaterHoldModel.evaluate.
void NativeHoldModel::score(const Vector3 &hand, const Vector3 &blade, Report &out) const {
	const Vector3 span = blade - hand;
	const double length = span.length();
	const Vector3 shaft = length > 0.0001 ? span / (real_t)length : Vector3(0, -1, 0);
	const double contact = swivel.contact;

	out.fist = Math::max(fist_radius - contact - clearance(hand), 0.0);
	out.knob = Math::max(knob_radius - contact - clearance(hand - shaft * (real_t)knob_extend), 0.0);
	out.shaft = 0.0;
	for (int k = 0; k < shaft_samples; k++) {
		const double t = Math::lerp(shaft_from, shaft_to, (double)k / (shaft_samples - 1));
		out.shaft = Math::max(out.shaft, shaft_radius - contact - clearance(hand + span * (real_t)t));
	}

	const Vector3 top = shoulders[0];
	const double folded = Math::sqrt(upper_len * upper_len + forearm_len * forearm_len
			- 2.0 * upper_len * forearm_len * Math::cos(Math_PI - elbow_flex_max));
	out.fold = Math::max(folded - (double)top.distance_to(hand), 0.0);
	out.high = std::isinf(hand_below_shoulder)
			? 0.0
			: Math::max((double)hand.y - ((double)top.y - hand_below_shoulder), 0.0);
	arm(0, hand, shaft, out.top);

	const Vector2 held = reachable_grip(shoulders[1], hand, blade, grip, reach + slack, spacing);
	out.bottom_grip = held.x;
	out.bottom_hand = hand + span * held.x;
	arm(1, out.bottom_hand, shaft, out.bottom);
	out.bottom.reach_past = held.y;
}

// SkaterHoldModel._out_of_jersey.
Vector3 NativeHoldModel::out_of_jersey(const Vector3 &p) const {
	const real_t e = (real_t)normal_step;
	const Vector3 g((real_t)(capped(p + Vector3(e, 0, 0)) - capped(p - Vector3(e, 0, 0))),
			(real_t)(capped(p + Vector3(0, e, 0)) - capped(p - Vector3(0, e, 0))),
			(real_t)(capped(p + Vector3(0, 0, e)) - capped(p - Vector3(0, 0, e))));
	return g.length_squared() > 0.0 ? g.normalized() : Vector3();
}

// SkaterHoldModel._push.
Vector3 NativeHoldModel::push(const Vector3 &hand, const Vector3 &blade, const Report &held) const {
	const Vector3 span = blade - hand;
	const Vector3 shaft = span.normalized();
	Vector3 out;
	if (held.fist > 0.0) {
		out += out_of_jersey(hand) * (real_t)held.fist;
	}
	if (held.knob > 0.0) {
		out += out_of_jersey(hand - shaft * (real_t)knob_extend) * (real_t)held.knob;
	}
	if (held.shaft > 0.0) {
		const double contact = swivel.contact;
		double worst = 0.0;
		double at = shaft_from;
		for (int k = 0; k < shaft_samples; k++) {
			const double t = Math::lerp(shaft_from, shaft_to, (double)k / (shaft_samples - 1));
			const double d = shaft_radius - contact - clearance(hand + span * (real_t)t);
			if (d > worst) {
				worst = d;
				at = t;
			}
		}
		out += out_of_jersey(hand + span * (real_t)at) * (real_t)(worst / (1.0 - at));
	}
	const Vector3 off_shoulder = (hand - shoulders[0]).normalized();
	out += off_shoulder * (real_t)(held.fold - held.top.reach_past);
	out += Vector3(0, -1, 0) * (real_t)held.high;
	if (held.top.sleeve > 0.0) {
		out += out_of_jersey(held.top.elbow) * (real_t)held.top.sleeve;
	}
	const double lever = Math::max(1.0 - held.bottom_grip, 0.2);
	if (held.bottom.reach_past > 0.0) {
		out += (shoulders[1] - held.bottom_hand).normalized() * (real_t)(held.bottom.reach_past / lever);
	}
	if (held.bottom.sleeve > 0.0) {
		out += out_of_jersey(held.bottom.elbow) * (real_t)(held.bottom.sleeve / lever);
	}
	return out;
}

// SkaterHoldModel._on_sphere.
Vector3 NativeHoldModel::on_sphere(const Vector3 &blade, const Vector3 &p, double length, double lie0) const {
	const Vector3 dir = p - blade;
	Vector2 flat(dir.x, dir.z);
	if (flat.length_squared() < 0.000001) {
		return blade + dir.normalized() * (real_t)length;
	}
	const double lie = Math::clamp(Math::atan2((double)dir.y, (double)flat.length()), lie0 - project_lie,
			lie0 + project_lie);
	flat = flat.normalized() * (real_t)Math::cos(lie);
	return blade + Vector3(flat.x, (real_t)Math::sin(lie), flat.y) * (real_t)length;
}

// SkaterHoldModel.project.
Vector3 NativeHoldModel::project(const PackedVector3Array &vectors, const Transform3D &p_torso,
		const PackedFloat64Array &scalars, const Vector3 &anchor, const Vector3 &blade, double lie) {
	if (!set_body(vectors, p_torso, scalars)) {
		return anchor;
	}
	const double length = anchor.distance_to(blade);
	if (length < 0.0001) {
		return anchor;
	}
	Vector3 hand = on_sphere(blade, anchor, length, lie);
	if (!hand.is_finite()) {
		return anchor;
	}
	Report held;
	for (int i = 0; i < project_steps; i++) {
		score(hand, blade, held);
		if (held.total() <= 0.0) {
			break;
		}
		const Vector3 next = on_sphere(blade, hand + push(hand, blade, held), length, lie);
		if (!next.is_finite()) {
			return anchor;
		}
		const double moved = next.distance_to(hand);
		hand = next;
		if (moved < project_settled) {
			break;
		}
	}
	return hand;
}

PackedFloat64Array NativeHoldModel::evaluate(const PackedVector3Array &vectors, const Transform3D &p_torso,
		const PackedFloat64Array &scalars, const Vector3 &hand, const Vector3 &blade) {
	PackedFloat64Array out;
	if (!set_body(vectors, p_torso, scalars)) {
		return out;
	}
	Report r;
	score(hand, blade, r);
	out.resize(11);
	out.set(0, r.fist);
	out.set(1, r.fold);
	out.set(2, r.high);
	out.set(3, r.knob);
	out.set(4, r.shaft);
	out.set(5, r.top.reach_past);
	out.set(6, r.top.sleeve);
	out.set(7, r.bottom.reach_past);
	out.set(8, r.bottom.sleeve);
	out.set(9, r.bottom_grip);
	out.set(10, r.total());
	return out;
}

void NativeHoldModel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure_torso", "profile", "sway", "depth", "x_scale", "z_scale",
								 "sleeve_radius", "contact"),
			&NativeHoldModel::configure_torso);
	ClassDB::bind_method(D_METHOD("configure_swivel", "weights"), &NativeHoldModel::configure_swivel);
	ClassDB::bind_method(D_METHOD("configure_hold", "constants"), &NativeHoldModel::configure_hold);
	ClassDB::bind_method(D_METHOD("project", "vectors", "torso", "scalars", "anchor", "blade", "lie"),
			&NativeHoldModel::project);
	ClassDB::bind_method(D_METHOD("evaluate", "vectors", "torso", "scalars", "hand", "blade"),
			&NativeHoldModel::evaluate);
}

} // namespace mitts
