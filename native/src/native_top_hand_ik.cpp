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

	// CLOSE regime: see top_hand_ik.gd for why the aim is clamped to the same
	// angular ROM the FAR regime enforces, and why hand_y_max is the inner
	// boundary of a long stick's reachable region. The hand sits its floor out
	// along the aim (forward_floor), so the stick spans what is left.
	double floor_m = forward_floor(r, to_forehand(aim_dir, blade_side_sign));
	if (r - floor_m < stick_horiz_at_rest) {
		aim_dir = clamp_aim_to_rom(aim_dir, blade_side_sign);
		const double tf = to_forehand(aim_dir, blade_side_sign);
		floor_m = forward_floor(r, tf);
		const double span_min = stick_horiz_for(stick_length, hand_y_max, blade_y);
		const double d = r - floor_m >= span_min ? r : blade_for_span(span_min, tf);
		const Vector2 close_blade_xz = shoulder_xz + aim_dir * (real_t)d;
		return Vector3(close_blade_xz.x, blade_y, close_blade_xz.y);
	}

	// FAR regime: hand displaces toward the target in XZ, clamped to the
	// asymmetric ROM; the blade sits stick_horiz_at_rest farther along the
	// clamped direction.
	const Vector2 disp = aim_dir * (real_t)(r - stick_horiz_at_rest);

	// Forehand-signed polar (see top_hand_ik.gd for the handedness reasoning).
	const double angle_raw = Math::atan2((double)disp.x, (double)-disp.y);
	double angle_to_forehand = angle_raw * blade_side_sign;
	double radius = disp.length();

	angle_to_forehand = CLAMP(
			angle_to_forehand, -rom_backhand_angle_max, rom_forehand_angle_max);

	radius = CLAMP(radius, 0.0, rim_reach(angle_to_forehand));

	// Clamped world angle, not hand_to_target — holds the blade at the ROM
	// limit instead of wrapping when the cursor moves further past it.
	const double world_angle = angle_to_forehand * blade_side_sign;
	const Vector2 blade_dir(Math::sin(world_angle), -Math::cos(world_angle));
	const Vector2 blade_xz = shoulder_xz + blade_dir * (real_t)(radius + stick_horiz_at_rest);
	return Vector3(blade_xz.x, blade_y, blade_xz.y);
}

void NativeTopHandIK::solve(
		const Vector3 &shoulder,
		const Vector2 &desired_blade_xz,
		double blade_side_sign) {
	blade = project_blade(shoulder, desired_blade_xz, blade_side_sign);

	// Hand reconstructed from the blade — colinear from the shoulder with a
	// rigid stick, so blade distance fully determines the hand (inverts exactly
	// even when the close-regime hand_y was clamped).
	const Vector2 shoulder_xz(shoulder.x, shoulder.z);
	const Vector2 from_shoulder = Vector2(blade.x, blade.z) - shoulder_xz;
	const double d = from_shoulder.length();
	const double stick_horiz_at_rest = stick_horiz_for(stick_length, hand_rest_y, blade_y);
	const Vector2 dir = d > 0.0001 ? from_shoulder / (real_t)d : Vector2(0.0, -1.0);
	const double reach = floored_reach(d, stick_horiz_at_rest, to_forehand(dir, blade_side_sign));
	const Vector2 hand_xz = shoulder_xz + dir * (real_t)reach;
	// TopHandIK._hand_y_on_stick.
	const double horiz = d - reach;
	double hand_y = hand_rest_y;
	if (horiz < stick_horiz_at_rest) {
		hand_y = blade_y + Math::sqrt(MAX(stick_length * stick_length - horiz * horiz, 0.0));
	}
	hand = Vector3(hand_xz.x, hand_y, hand_xz.y);
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

// The ROM rim: two quarter-ellipses sharing the forward semi-axis (see
// TopHandIK.rim_reach).
double NativeTopHandIK::rim_reach(double angle_to_forehand) const {
	const double side = angle_to_forehand > 0.0 ? rom_forehand_reach_max : rom_backhand_reach_max;
	const double c = Math::cos(angle_to_forehand);
	if (c <= 0.0) {
		return side;
	}
	const double s = Math::sin(angle_to_forehand);
	const double denom = Math::sqrt(side * side * c * c
			+ rom_forward_reach_max * rom_forward_reach_max * s * s);
	return denom > 0.000001 ? rom_forward_reach_max * side / denom : 0.0;
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

// The engine's smoothstep, which GDScript calls (godot-cpp's differs at equal
// bounds).
static double smoothstep_gd(double from, double to, double x) {
	if (Math::is_equal_approx(from, to)) {
		if (from <= to) {
			return x <= from ? 0.0 : 1.0;
		}
		return x <= to ? 1.0 : 0.0;
	}
	const double t = CLAMP((x - from) / (to - from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

double NativeTopHandIK::forward_floor(double d, double tf) const {
	if (hand_forward <= 0.0) {
		return 0.0;
	}
	return hand_forward * smoothstep_gd(hand_forward_none, hand_forward_full, d)
			* smoothstep_gd(hand_forward_none_angle, hand_forward_full_angle, tf);
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

double NativeTopHandIK::floored_reach(double d, double rest_horiz, double tf) const {
	const double floor_m = forward_floor(d, tf);
	return floor_m + hand_reach(d - floor_m, rest_horiz);
}

double NativeTopHandIK::blade_for_span(double span, double tf) const {
	double d = span + hand_forward;
	for (int i = 0; i < FLOOR_ITERATIONS; i++) {
		d = span + forward_floor(d, tf);
	}
	return d;
}

double NativeTopHandIK::to_forehand(const Vector2 &dir, double blade_side_sign) {
	return Math::atan2((double)dir.x, -(double)dir.y) * blade_side_sign;
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
	ClassDB::bind_method(D_METHOD("set_hand_forward", "v"), &NativeTopHandIK::set_hand_forward);
	ClassDB::bind_method(D_METHOD("get_hand_forward"), &NativeTopHandIK::get_hand_forward);
	ClassDB::bind_method(D_METHOD("set_hand_forward_none", "v"), &NativeTopHandIK::set_hand_forward_none);
	ClassDB::bind_method(D_METHOD("get_hand_forward_none"), &NativeTopHandIK::get_hand_forward_none);
	ClassDB::bind_method(D_METHOD("set_hand_forward_full", "v"), &NativeTopHandIK::set_hand_forward_full);
	ClassDB::bind_method(D_METHOD("get_hand_forward_full"), &NativeTopHandIK::get_hand_forward_full);
	ClassDB::bind_method(D_METHOD("set_hand_forward_none_angle", "v"),
			&NativeTopHandIK::set_hand_forward_none_angle);
	ClassDB::bind_method(D_METHOD("get_hand_forward_none_angle"),
			&NativeTopHandIK::get_hand_forward_none_angle);
	ClassDB::bind_method(D_METHOD("set_hand_forward_full_angle", "v"),
			&NativeTopHandIK::set_hand_forward_full_angle);
	ClassDB::bind_method(D_METHOD("get_hand_forward_full_angle"),
			&NativeTopHandIK::get_hand_forward_full_angle);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hand_forward"), "set_hand_forward", "get_hand_forward");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hand_forward_none"),
			"set_hand_forward_none", "get_hand_forward_none");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hand_forward_full"),
			"set_hand_forward_full", "get_hand_forward_full");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hand_forward_none_angle"),
			"set_hand_forward_none_angle", "get_hand_forward_none_angle");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hand_forward_full_angle"),
			"set_hand_forward_full_angle", "get_hand_forward_full_angle");
}

} // namespace mitts
