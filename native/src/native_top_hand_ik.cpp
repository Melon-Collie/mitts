#include "native_top_hand_ik.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace mitts {

Vector3 NativeTopHandIK::project_blade(
		const Vector3 &shoulder,
		const Vector2 &desired_blade_xz,
		double blade_side_sign) const {
	const double stick_horiz_at_rest = stick_horiz_for(stick_length, hand_rest_y, blade_y);

	const Vector2 shoulder_xz(shoulder.x, shoulder.z);
	const Vector2 delta = desired_blade_xz - shoulder_xz;
	double r = delta.length();
	Vector2 aim_dir = r > 0.0001 ? delta / (real_t)r : Vector2(0.0, -1.0);
	// Obstacle cap (the boards) on the desired DISTANCE, before the regime split
	// — see top_hand_ik.gd for why it lands here and not on the solved pose.
	r = MIN(r, MAX(max_blade_reach, 0.0));
	aim_dir = clamp_aim_to_rom(aim_dir, blade_side_sign);
	const Vector2 target = shoulder_xz + aim_dir * (real_t)r;

	// CLOSE regime: hand_y_max's floor round the pivot pushes the blade out
	// along the aim, eased over REGIME_BAND_M (see top_hand_ik.gd).
	if (r < stick_horiz_at_rest) {
		const Vector2 pivot = pivot_xz(shoulder_xz, blade_side_sign);
		const double min_horiz = stick_horiz_for(stick_length, hand_y_max, blade_y);
		const Vector2 w = shoulder_xz - pivot;
		const double wa = w.dot(aim_dir);
		const double disc = wa * wa - (double)w.length_squared() + min_horiz * min_horiz;
		if (disc < 0.0 || r <= -wa - Math::sqrt(disc)) {
			return Vector3(target.x, blade_y, target.y);
		}
		const double floor_k = -wa + Math::sqrt(disc);
		const Vector2 out_xz = shoulder_xz + aim_dir * (real_t)(floor_k + hand_reach(r, floor_k));
		return Vector3(out_xz.x, blade_y, out_xz.y);
	}

	// FAR regime: the hand displaces toward the target as far as the rim in its
	// direction; the blade sits stick_horiz_at_rest farther along the aim.
	const double radius = MIN(r - stick_horiz_at_rest, max_reach_for_angle(
			Math::atan2((double)aim_dir.x, (double)-aim_dir.y) * blade_side_sign));
	const Vector2 blade_xz = shoulder_xz + aim_dir * (real_t)(radius + stick_horiz_at_rest);
	return Vector3(blade_xz.x, blade_y, blade_xz.y);
}

void NativeTopHandIK::solve(
		const Vector3 &shoulder,
		const Vector2 &desired_blade_xz,
		double blade_side_sign) {
	blade = project_blade(shoulder, desired_blade_xz, blade_side_sign);
	// The hand from the blade (hand_xz_for); its height the rigid stick's over
	// the span left between them.
	const Vector2 blade_xz(blade.x, blade.z);
	const Vector2 hand_xz = hand_xz_for(Vector2(shoulder.x, shoulder.z), blade_xz, blade_y,
			blade_side_sign, stick_length, hand_rest_y);
	const double horiz = blade_xz.distance_to(hand_xz);
	hand = Vector3(hand_xz.x,
			blade_y + Math::sqrt(MAX(stick_length * stick_length - horiz * horiz, 0.0)), hand_xz.y);
}

// TopHandIK.max_reach_for_angle / rim_reach.
double NativeTopHandIK::max_reach_for_angle(double angle_to_forehand) const {
	const double side = angle_to_forehand > 0.0 ? rom_forehand_reach_max : rom_backhand_reach_max;
	const double c = Math::cos(angle_to_forehand);
	if (c <= 0.0) {
		return side;
	}
	const double sn = Math::sin(angle_to_forehand);
	const double denom = Math::sqrt(side * side * c * c
			+ rom_forward_reach_max * rom_forward_reach_max * sn * sn);
	return denom > 0.000001 ? rom_forward_reach_max * side / denom : 0.0;
}

// TopHandIK.pivot_share.
double NativeTopHandIK::pivot_share(double reach, const Vector2 &dir, double blade_side_sign) const {
	if (reach <= 0.0) {
		return 1.0;
	}
	const double angle = CLAMP(Math::atan2((double)dir.x, (double)-dir.y) * blade_side_sign,
			-rom_backhand_angle_max, rom_forehand_angle_max);
	const double span = PIVOT_FADE_SHARE * max_reach_for_angle(angle);
	if (span <= 0.0) {
		return 0.0;
	}
	const double t = CLAMP(reach / span, 0.0, 1.0);
	return 1.0 - t * t * (3.0 - 2.0 * t);
}

// TopHandIK.hand_xz_for, with the stick's length and rest height given.
Vector2 NativeTopHandIK::hand_xz_for(const Vector2 &shoulder_xz, const Vector2 &blade_xz,
		double p_blade_y, double blade_side_sign, double p_stick_length, double p_hand_rest_y) const {
	const double rest_horiz = stick_horiz_for(p_stick_length, p_hand_rest_y, p_blade_y);
	const Vector2 from_shoulder = blade_xz - shoulder_xz;
	const double d = from_shoulder.length();
	const double reach = hand_reach(d, rest_horiz);
	const Vector2 dir = d > 0.0001 ? from_shoulder / (real_t)d : Vector2(0.0, -1.0);
	const double share = pivot_share(reach, dir, blade_side_sign);
	Vector2 hand = pivot_at(shoulder_xz + dir * (real_t)reach, blade_side_sign,
			pivot_forward * share, pivot_inward * share);
	const Vector2 to_hand = hand - blade_xz;
	const double span = to_hand.length();
	const double band = MIN(REGIME_BAND_M, (p_stick_length - rest_horiz) * 0.5);
	const double over = span - (rest_horiz + band);
	if (over > -band && band > 0.0) {
		const double eased = over >= band ? over : (over + band) * (over + band) / (4.0 * band);
		hand = blade_xz + to_hand * (real_t)((span - eased) / span);
	}
	return hand;
}

double NativeTopHandIK::hand_reach(double d, double rest_horiz) {
	const double x = d - rest_horiz;
	if (x >= REGIME_BAND_M) {
		return x;
	}
	if (x <= -REGIME_BAND_M) {
		return 0.0;
	}
	return (x + REGIME_BAND_M) * (x + REGIME_BAND_M) / (4.0 * REGIME_BAND_M);
}

Vector2 NativeTopHandIK::pivot_at(const Vector2 &shoulder_xz, double blade_side_sign,
		double forward, double inward) {
	return shoulder_xz + Vector2((real_t)(blade_side_sign * inward), (real_t)-forward);
}

void NativeTopHandIK::solve_on_ice(
		const Vector3 &shoulder,
		const Vector2 &desired_blade_xz,
		double blade_side_sign,
		double blade_y_base,
		double pitch,
		double roll,
		double p_max_blade_reach,
		double p_stick_length,
		double p_hand_y_max) {
	max_blade_reach = p_max_blade_reach;
	stick_length = p_stick_length;
	hand_y_max = p_hand_y_max;
	double cp = Math::cos(pitch);
	double cr = Math::cos(roll);
	if (cp < 0.001) {
		cp = 0.001;
	}
	if (cr < 0.001) {
		cr = 0.001;
	}
	const double sp = Math::sin(pitch);
	const double sr = Math::sin(roll);
	blade_y = blade_y_base;
	for (int pass = 0; pass < 3; pass++) {
		solve(shoulder, desired_blade_xz, blade_side_sign);
		blade_y = (blade_y_base + (double)blade.z * sp - (double)blade.x * sr * cp) / (cp * cr);
	}
}

Vector2 NativeTopHandIK::clamp_aim_to_rom(const Vector2 &aim_dir, double blade_side_sign) const {
	const double angle_to_forehand =
			Math::atan2((double)aim_dir.x, (double)-aim_dir.y) * blade_side_sign;
	const double clamped = CLAMP(
			angle_to_forehand, -rom_backhand_angle_max, rom_forehand_angle_max);
	if (clamped == angle_to_forehand) {
		return aim_dir;
	}
	const double world_angle = clamped * blade_side_sign;
	return Vector2(Math::sin(world_angle), -Math::cos(world_angle));
}

// TopHandIK._TWO_HAND_BISECTIONS.
static constexpr int TWO_HAND_BISECTIONS = 9;

Vector2 NativeTopHandIK::reachable_grip(const Vector3 &shoulder, const Vector3 &top,
		const Vector3 &blade, double grip, double reach, double spacing) {
	const Vector3 u = blade - top;
	const Vector3 w = top - shoulder;
	const double a = u.length_squared();
	if (a < 0.000001) {
		return Vector2(grip, MAX((double)w.length() - reach, 0.0));
	}
	const double floor_g = MIN(spacing / Math::sqrt(a), 1.0);
	const double b = u.dot(w);
	const double c = (double)w.length_squared() - reach * reach;
	const double disc = b * b - a * c;
	if (disc >= 0.0) {
		const double root = Math::sqrt(disc);
		const double lo = MAX((-b - root) / a, floor_g);
		const double hi = MIN((-b + root) / a, 1.0);
		if (lo <= hi) {
			return Vector2(CLAMP(grip, lo, hi), 0.0);
		}
	}
	const double nearest = CLAMP(-b / a, floor_g, 1.0);
	return Vector2(nearest, MAX((double)(w + u * (real_t)nearest).length() - reach, 0.0));
}

double NativeTopHandIK::two_hand_reach(
		const Vector3 &shoulder,
		const Vector2 &desired_blade_xz,
		double blade_side_sign,
		const Vector3 &bottom_shoulder,
		double grip,
		double bottom_reach,
		double spacing) {
	solve(shoulder, desired_blade_xz, blade_side_sign);
	if (reachable_grip(bottom_shoulder, hand, blade, grip, bottom_reach, spacing).y <= 0.0) {
		return INFINITY;
	}
	const double cap = max_blade_reach;
	double lo = 0.0;
	double hi = Vector2(blade.x - shoulder.x, blade.z - shoulder.z).length();
	for (int i = 0; i < TWO_HAND_BISECTIONS; i++) {
		const double mid = (lo + hi) * 0.5;
		max_blade_reach = mid;
		solve(shoulder, desired_blade_xz, blade_side_sign);
		if (reachable_grip(bottom_shoulder, hand, blade, grip, bottom_reach, spacing).y <= 0.0) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	max_blade_reach = cap;
	return lo;
}

double NativeTopHandIK::stick_horiz_for(double stick_length, double hand_y, double blade_y) {
	const double drop = hand_y - blade_y;
	const double sq = stick_length * stick_length - drop * drop;
	return Math::sqrt(MAX(sq, 0.0001));
}

void NativeTopHandIK::_bind_methods() {
	ClassDB::bind_method(D_METHOD("project_blade", "shoulder", "desired_blade_xz", "blade_side_sign"),
			&NativeTopHandIK::project_blade);
	ClassDB::bind_method(D_METHOD("solve", "shoulder", "desired_blade_xz", "blade_side_sign"),
			&NativeTopHandIK::solve);
	ClassDB::bind_method(D_METHOD("solve_on_ice", "shoulder", "desired_blade_xz", "blade_side_sign",
								 "blade_y_base", "pitch", "roll", "max_blade_reach", "stick_length", "hand_y_max"),
			&NativeTopHandIK::solve_on_ice);
	ClassDB::bind_method(D_METHOD("two_hand_reach", "shoulder", "desired_blade_xz", "blade_side_sign",
								 "bottom_shoulder", "grip", "bottom_reach", "spacing"),
			&NativeTopHandIK::two_hand_reach);
	ClassDB::bind_method(D_METHOD("get_hand"), &NativeTopHandIK::get_hand);
	ClassDB::bind_method(D_METHOD("get_blade"), &NativeTopHandIK::get_blade);

	ClassDB::bind_method(D_METHOD("set_stick_length", "v"), &NativeTopHandIK::set_stick_length);
	ClassDB::bind_method(D_METHOD("get_stick_length"), &NativeTopHandIK::get_stick_length);
	ClassDB::bind_method(D_METHOD("set_blade_y", "v"), &NativeTopHandIK::set_blade_y);
	ClassDB::bind_method(D_METHOD("get_blade_y"), &NativeTopHandIK::get_blade_y);
	ClassDB::bind_method(D_METHOD("set_hand_rest_y", "v"), &NativeTopHandIK::set_hand_rest_y);
	ClassDB::bind_method(D_METHOD("get_hand_rest_y"), &NativeTopHandIK::get_hand_rest_y);
	ClassDB::bind_method(D_METHOD("set_hand_y_max", "v"), &NativeTopHandIK::set_hand_y_max);
	ClassDB::bind_method(D_METHOD("get_hand_y_max"), &NativeTopHandIK::get_hand_y_max);
	ClassDB::bind_method(D_METHOD("set_rom_forehand_angle_max", "v"),
			&NativeTopHandIK::set_rom_forehand_angle_max);
	ClassDB::bind_method(D_METHOD("get_rom_forehand_angle_max"),
			&NativeTopHandIK::get_rom_forehand_angle_max);
	ClassDB::bind_method(D_METHOD("set_rom_backhand_angle_max", "v"),
			&NativeTopHandIK::set_rom_backhand_angle_max);
	ClassDB::bind_method(D_METHOD("get_rom_backhand_angle_max"),
			&NativeTopHandIK::get_rom_backhand_angle_max);
	ClassDB::bind_method(D_METHOD("set_rom_forward_reach_max", "v"),
			&NativeTopHandIK::set_rom_forward_reach_max);
	ClassDB::bind_method(D_METHOD("get_rom_forward_reach_max"),
			&NativeTopHandIK::get_rom_forward_reach_max);
	ClassDB::bind_method(D_METHOD("set_rom_forehand_reach_max", "v"),
			&NativeTopHandIK::set_rom_forehand_reach_max);
	ClassDB::bind_method(D_METHOD("get_rom_forehand_reach_max"),
			&NativeTopHandIK::get_rom_forehand_reach_max);
	ClassDB::bind_method(D_METHOD("set_rom_backhand_reach_max", "v"),
			&NativeTopHandIK::set_rom_backhand_reach_max);
	ClassDB::bind_method(D_METHOD("get_rom_backhand_reach_max"),
			&NativeTopHandIK::get_rom_backhand_reach_max);
	ClassDB::bind_method(D_METHOD("set_max_blade_reach", "v"),
			&NativeTopHandIK::set_max_blade_reach);
	ClassDB::bind_method(D_METHOD("get_max_blade_reach"),
			&NativeTopHandIK::get_max_blade_reach);
	ClassDB::bind_method(D_METHOD("set_pivot_forward", "v"), &NativeTopHandIK::set_pivot_forward);
	ClassDB::bind_method(D_METHOD("get_pivot_forward"), &NativeTopHandIK::get_pivot_forward);
	ClassDB::bind_method(D_METHOD("set_pivot_inward", "v"), &NativeTopHandIK::set_pivot_inward);
	ClassDB::bind_method(D_METHOD("get_pivot_inward"), &NativeTopHandIK::get_pivot_inward);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "stick_length"), "set_stick_length", "get_stick_length");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "blade_y"), "set_blade_y", "get_blade_y");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hand_rest_y"), "set_hand_rest_y", "get_hand_rest_y");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hand_y_max"), "set_hand_y_max", "get_hand_y_max");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rom_forehand_angle_max"),
			"set_rom_forehand_angle_max", "get_rom_forehand_angle_max");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rom_backhand_angle_max"),
			"set_rom_backhand_angle_max", "get_rom_backhand_angle_max");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rom_forward_reach_max"),
			"set_rom_forward_reach_max", "get_rom_forward_reach_max");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rom_forehand_reach_max"),
			"set_rom_forehand_reach_max", "get_rom_forehand_reach_max");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rom_backhand_reach_max"),
			"set_rom_backhand_reach_max", "get_rom_backhand_reach_max");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_blade_reach"),
			"set_max_blade_reach", "get_max_blade_reach");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "pivot_forward"),
			"set_pivot_forward", "get_pivot_forward");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "pivot_inward"),
			"set_pivot_inward", "get_pivot_inward");
}

} // namespace mitts
