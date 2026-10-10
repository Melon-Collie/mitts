#include "native_skater_gait.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cmath>

using namespace godot;

namespace mitts {

// GaitPose's leg geometry and reach limits.
static constexpr double THIGH_LEN = 0.31;
static constexpr double SHIN_LEN = 0.45;
static constexpr double FOOT_FWD = 0.10;
static constexpr double HIP_HALF_WIDTH = 0.13;
static constexpr double HIP_DROP = 0.13;
static constexpr double PLANT_STROKE_BAND = 0.2;
static constexpr double REACH_MAX = 0.99;
static constexpr double REACH_EASE_M = 0.06;
static constexpr double DEPTH_EASE_M = 0.02;
static constexpr double DEPTH_SPARE_M = 0.01;
// SkaterMeshBuilder.BLADE_ICE_Z (0.080 + SKATE_LIFT_M).
static constexpr double BLADE_ICE_Z = 0.080 + 0.04;
// SkaterLocomotion._FD_WINDOW_MAX.
static constexpr double FD_WINDOW_MAX = 0.1;
// SkaterSkatingCoordinator._PSI_RATE_EASE / _PSI_SMOOTH_EASE.
static constexpr double PSI_RATE_EASE = 10.0;
static constexpr double PSI_SMOOTH_EASE = 15.0;
// PivotRules.RELEASE_MARGIN.
static constexpr double PIVOT_RELEASE_MARGIN = 8.0 * Math_PI / 180.0;
// SkaterMovementRules.GRIP_MIN_SPEED.
static constexpr double GRIP_MIN_SPEED = 0.5;
// LocomotionRules._INTENT_MIN_SQ / DRIVE_FULL.
static constexpr double INTENT_MIN_SQ = 0.0025;
static constexpr double DRIVE_FULL = 0.5;

// ── GDScript @GlobalScope semantics (double precision) ──

static inline double deg_to_rad(double d) {
	return d * (Math_PI / 180.0);
}

static inline double sgn(double v) {
	return v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0);
}

static inline double lerpd(double a, double b, double t) {
	return a + (b - a) * t;
}

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

// The engine's double wrapf (godot-cpp's Math::wrapf is single precision).
static inline double wrapd(double value, double lo, double hi) {
	const double range = hi - lo;
	if (std::abs(range) < CMP_EPSILON) {
		return lo;
	}
	const double result = value - (range * std::floor((value - lo) / range));
	if (equal_approx(result, hi)) {
		return lo;
	}
	return result;
}

static inline double angle_diff(double from, double to) {
	const double difference = std::fmod(to - from, Math_TAU);
	return std::fmod(2.0 * difference, Math_TAU) - difference;
}

static inline double smoothstep01(double s) {
	s = clampd(s, 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

// ── Pure rules ──

// HockeyStopRules.stop_yaw
static double hockey_stop_yaw(const Vector3 &local_velocity, double side, double max_yaw) {
	const double fwd = -local_velocity.z;
	const double lat = local_velocity.x;
	if (Vector2(lat, fwd).length() < 0.01) {
		return 0.0;
	}
	const double travel_angle = std::atan2(lat, fwd);
	const double legs_angle = wrapd(travel_angle + side * Math_PI * 0.5, -Math_PI, Math_PI);
	return clampd(-legs_angle, -max_yaw, max_yaw);
}

// CarveRules.turn_rate
static double carve_turn_rate(const Vector2 &prev_vel_xz, const Vector2 &vel_xz,
		double delta, double min_speed) {
	if (delta <= 0.0) {
		return 0.0;
	}
	if (prev_vel_xz.length() < min_speed || vel_xz.length() < min_speed) {
		return 0.0;
	}
	return prev_vel_xz.angle_to(vel_xz) / delta;
}

// PivotRules
static bool pivot_should_engage(double abs_psi, double abs_psi_rate, double ground_speed,
		double band_lo, double band_hi, double rate_min, double min_speed) {
	return ground_speed >= min_speed && abs_psi_rate >= rate_min &&
			abs_psi > band_lo && abs_psi < band_hi;
}

static bool pivot_should_release(double abs_psi, double ground_speed,
		double band_lo, double band_hi, double min_speed) {
	return ground_speed < min_speed ||
			abs_psi <= band_lo - PIVOT_RELEASE_MARGIN ||
			abs_psi >= band_hi + PIVOT_RELEASE_MARGIN;
}

static double pivot_latch_sense(double abs_psi, double band_lo, double band_hi) {
	return abs_psi < 0.5 * (band_lo + band_hi) ? 1.0 : -1.0;
}

static double pivot_hold_depth(double abs_psi, double band_lo, double ramp) {
	return clampd((abs_psi - band_lo) / maxd(ramp, 0.001), 0.0, 1.0);
}

static double pivot_phase(double abs_psi, double sense, double band_lo, double band_hi) {
	const double p = clampd((abs_psi - band_lo) / maxd(band_hi - band_lo, 0.001), 0.0, 1.0);
	return sense > 0.0 ? p : 1.0 - p;
}

static double pivot_yaw_law(double psi, double sense, double p, double step_begin) {
	const double along = -psi;
	const double anti = -psi + Math_PI * sgn(psi);
	double t = 0.0;
	if (p > step_begin) {
		t = (p - step_begin) / maxd(1.0 - step_begin, 0.001);
		t = t * t * (3.0 - 2.0 * t);
	}
	if (sense > 0.0) {
		return lerpd(along, anti, t);
	}
	return lerpd(anti, along, t);
}

// SkaterLocomotion._in_legs
static Vector2 in_legs(const Vector2 &travel, double yaw) {
	const double cy = std::cos(yaw);
	const double sy = std::sin(yaw);
	return Vector2(travel.x * cy + travel.y * sy, travel.x * sy - travel.y * cy);
}

// GaitPose.reach_hip
static double reach_hip(double out) {
	const double leg = REACH_MAX * (THIGH_LEN + SHIN_LEN);
	const double depth = std::sqrt(maxd(leg * leg - (out + REACH_EASE_M) * (out + REACH_EASE_M), 1e-6));
	return std::acos(clampd((depth * depth - SHIN_LEN * SHIN_LEN + THIGH_LEN * THIGH_LEN) / (2.0 * depth * THIGH_LEN), -1.0, 1.0));
}

// GaitPose.plant_share
static double plant_share(double p_intensity, double p_edge_floor) {
	return maxd(smoothstep01(1.0 - p_intensity / PLANT_STROKE_BAND), clampd(p_edge_floor, 0.0, 1.0));
}

// GaitPose._ease_into
static double ease_into(double value, double limit, double band) {
	if (value <= limit - band) {
		return value;
	}
	return limit - band * std::exp((limit - band - value) / band);
}

// GaitPose._runner_depth, with `ice` the hips' frame against it.
template <typename L>
static double runner_depth(const L &leg, const Basis &ice) {
	const Basis posed = ice * Basis::from_euler(Vector3(leg.pitch, leg.yaw, leg.roll)) * Basis(Vector3(1, 0, 0), leg.knee);
	const Vector3 along = posed.xform(Vector3(0, 0, -1));
	const Vector3 down = posed.xform(Vector3(0, -1, 0));
	const Vector3 heading = (ice * Basis(Vector3(0, 1, 0), leg.yaw)).xform(Vector3(0, 0, -1));
	const double flat = std::sqrt((double)heading.x * heading.x + (double)heading.z * heading.z);
	double edge = 0.0;
	if (flat > 1e-6) {
		edge = ((double)down.x * heading.z - (double)down.z * heading.x) / flat;
	}
	const double upright = -(double)down.y / maxd(std::sqrt(edge * edge + (double)down.y * down.y), 1e-6);
	return -(double)along.y * FOOT_FWD + upright * BLADE_ICE_Z;
}

// LegIK.place
template <typename L>
static void leg_place(L &leg, double thigh, double shin) {
	const double vy = -thigh - shin * std::cos(leg.knee);
	const double vz = -shin * std::sin(leg.knee);
	const double x = -vy * std::sin(leg.roll);
	const double y = vy * std::cos(leg.roll);
	const double cp = std::cos(leg.pitch);
	const double sp = std::sin(leg.pitch);
	const double y2 = y * cp - vz * sp;
	const double z2 = y * sp + vz * cp;
	leg.x = x * std::cos(leg.yaw) + z2 * std::sin(leg.yaw);
	leg.y = y2;
	leg.z = -x * std::sin(leg.yaw) + z2 * std::cos(leg.yaw);
}

// LegIK.solve
template <typename L>
static void leg_solve(L &leg, double thigh, double shin) {
	const double cw = std::cos(leg.yaw);
	const double sw = std::sin(leg.yaw);
	double qx = leg.x * cw - leg.z * sw;
	double qy = leg.y;
	double qz = leg.x * sw + leg.z * cw;
	const double d = std::sqrt(qx * qx + qy * qy + qz * qz);
	const double c = (d * d - thigh * thigh - shin * shin) / (2.0 * thigh * shin);
	leg.knee = -std::acos(clampd(c, -1.0, 1.0));
	const double vy = -thigh - shin * std::cos(leg.knee);
	const double vz = -shin * std::sin(leg.knee);
	if (d < 1e-9) {
		leg.pitch = 0.0;
		leg.roll = 0.0;
		return;
	}
	const double reach = std::sqrt(vy * vy + vz * vz) / d;
	qx *= reach;
	qy *= reach;
	qz *= reach;
	leg.roll = vy < 0.0 ? std::asin(clampd(qx / maxd(-vy, 1e-9), -1.0, 1.0)) : 0.0;
	leg.pitch = wrapd(std::atan2(qz, qy) - std::atan2(vz, vy * std::cos(leg.roll)), -Math_PI, Math_PI);
}

// ── Binding surface ──

String NativeSkaterGait::configure(Object *controller) {
	ERR_FAIL_NULL_V(controller, String("null controller"));
	String missing;
#define X(name)                                                    \
	{                                                              \
		const Variant v = controller->get(StringName(#name));      \
		if (v.get_type() == Variant::NIL) {                        \
			missing += #name " ";                                  \
		} else {                                                   \
			cfg.name = (double)v;                                  \
		}                                                          \
	}
	MITTS_GAIT_TUNABLES(X)
#undef X
	return missing;
}

void NativeSkaterGait::reset() {
	// SkaterLocomotion.reset
	mix.clear();
	mix.glide = 1.0;
	cross_signed = 0.0;
	carve_signed = 0.0;
	tight_signed = 0.0;
	stride_phase = 0.0;
	intensity = 0.0;
	effort = 0.0;
	turn_rate = 0.0;
	turning = 0.0;
	loaded = 0.0;
	stop_yaw = 0.0;
	stop_latched = false;
	have_prev_velocity = false;
	fd_time = 0.0;
	fd_effort_target = 0.0;
	fd_turn = 0.0;
	glide_phase = 0.0;
	weight_shift = 0.0;
	weight_shift_vel = 0.0;
	clear_strokes();
	// SkaterSkatingCoordinator.reset_to_rest, alignment and pivot
	travel_align_yaw = 0.0;
	hip_align_yaw = 0.0;
	prev_psi = 0.0;
	have_prev_psi = false;
	psi_smooth = 0.0;
	psi_rate = 0.0;
	pivot_engaged = false;
	pivot_sense = 1.0;
	pivot_blend = 0.0;
	pivot_dwell = 0.0;
	pivot_yaw_l = 0.0;
	pivot_yaw_r = 0.0;
}

Vector2 NativeSkaterGait::locomote(double delta, const Vector3 &velocity, const Vector2 &intent,
		const Basis &basis, int64_t flags, double hold) {
	sense(delta, velocity, intent, basis, (flags & FLAG_BRAKE) != 0,
			(flags & FLAG_STANCE) != 0, (flags & FLAG_PLANTED) != 0, hold);
	strokes(delta, align_and_pivot(delta, velocity, basis));
	// SkaterSkatingCoordinator.apply: the pivot's sit, then the reach sit.
	double base = maxd(stance, cfg.pivot_stance * pivot_blend);
	if (authored > 0.001) {
		const double reach_sit = mind(reach_hip(push_reach), deg_to_rad(cfg.stride_sit_max_deg)) / deg_to_rad(cfg.stance_hip_deg);
		base = maxd(base, lerpd(base, reach_sit, authored));
	}
	return Vector2(base, authored);
}

// ── SkaterLocomotion ──

void NativeSkaterGait::sense(double delta, const Vector3 &vel, const Vector2 &intent,
		const Basis &basis, bool brake, bool stance_active, bool planted, double hold) {
	const Config &c = cfg;
	ground_speed = Vector2(vel.x, vel.z).length();
	speed_t = clampd(ground_speed / maxd(c.max_speed, 0.001), 0.0, 1.0);
	sample_velocity(delta, vel);
	effort = lerpd(effort, fd_effort_target, c.stride_effort_speed * delta);
	turn_rate = lerpd(turn_rate, fd_turn, c.carve_engage_speed * delta);
	turning = clampd(ground_speed * turn_rate / maxd(c.turn_accel * c.lateral_grip, 0.001), -1.0, 1.0);
	loaded = lerpd(loaded, (stance_active && !planted) ? 1.0 : 0.0,
			c.locomotion_blend_speed * delta);

	// LocomotionRules.classify
	const Vector3 col_z = basis.get_column(2);
	const Vector2 facing(-col_z.x, -col_z.z);
	const Vector2 velocity2(vel.x, vel.z);
	target.clear();
	do {
		Mix &out = target;
		const double speed = velocity2.length();
		const bool has_input = intent.length_squared() > INTENT_MIN_SQ;
		if (speed <= GRIP_MIN_SPEED) {
			if (!has_input) {
				out.glide = 1.0;
				break;
			}
			const Vector2 dir = intent.normalized();
			const double ahead = facing.dot(dir);
			const double across = facing.cross(dir);
			const double a = maxd(ahead, 0.0);
			const double b = maxd(-ahead, 0.0);
			out.stride = a * a;
			out.backward = b * b;
			out.shuffle = across * across;
			out.side = across != 0.0 ? sgn(across) : 1.0;
			break;
		}
		const Vector2 travel = velocity2 / (real_t)speed;
		if (brake) {
			if (has_input) {
				const double steer = travel.angle_to(intent);
				out.side = steer != 0.0 ? sgn(steer) : 1.0;
			}
			out.stop = 1.0;
			break;
		}
		if (!has_input) {
			out.glide = 1.0;
			break;
		}
		const double turn = travel.angle_to(intent);
		const double along = std::cos(turn);
		const double across_t = std::sin(turn);
		out.side = across_t != 0.0 ? sgn(across_t) : 1.0;
		if (travel.dot(facing) < 0.0) {
			const double back = maxd(-along, 0.0);
			out.skid = back * back;
			out.backward = 1.0 - out.skid;
			break;
		}
		const double stick = mind(intent.length(), 1.0);
		out.skid = maxd(-along, 0.0) * stick;
		const double moving = 1.0 - out.skid;
		const double push = moving * smoothstep01(maxd(along, 0.0) * stick / DRIVE_FULL);
		const double coast = moving - push;
		const double t = clampd(std::abs(turning), 0.0, 1.0);
		if (turning != 0.0) {
			out.side = sgn(turning);
		}
		out.stride = push * (1.0 - t);
		out.glide = coast * (1.0 - t);
		if (stance_active) {
			out.tight = moving * t;
		} else {
			out.crossover = push * t;
			out.carve = coast * t;
		}
	} while (false);
	if (ground_speed < c.hockey_stop_min_speed) {
		target.glide += target.stop;
		target.stop = 0.0;
	}
	if (ground_speed < c.carve_min_speed) {
		target.stride += target.crossover;
		target.crossover = 0.0;
	}
	if (planted) {
		target.clear();
		target.glide = 1.0;
	}
	ease_mix(delta);

	const Vector3 local_vel = basis.inverse().xform(vel);
	if (target.stop > 0.5 && !stop_latched) {
		stop_latched = true;
		stop_side = local_vel.x >= 0.0 ? 1.0 : -1.0;
	} else if (target.stop < 0.1) {
		stop_latched = false;
	}
	stop_yaw_full = hockey_stop_yaw(local_vel, stop_side, deg_to_rad(c.hockey_stop_max_yaw_deg));
	stop_yaw = mix.stop > 0.001 ? stop_yaw_full * mix.stop : 0.0;

	start = clampd(1.0 - ground_speed / maxd(c.dig_in_fade_speed, 0.001), 0.0, 1.0);
	const double stroking = mix.stride + mix.crossover + mix.backward + mix.shuffle;
	double target_intensity = 0.0;
	if (target.stride + target.crossover + target.backward + target.shuffle > 0.01) {
		target_intensity = maxd(speed_t, maxd(c.dig_in_intensity * start * (mix.stride + mix.backward),
				c.shuffle_intensity * mix.shuffle));
	}
	intensity = lerpd(intensity, target_intensity * (1.0 - hold), c.stride_intensity_speed * delta);

	push_scale = clampd(1.0 + effort * c.stride_push_gain, c.stride_glide_floor, c.stride_push_ceiling) * (1.0 + loaded * c.stance_stride_gain);
	cruise_gear = speed_t * (1.0 - clampd(effort, 0.0, 1.0));

	const double ceiling = maxd(c.stride_cadence_max_rate, 0.001);
	double stride_rate = ceiling * std::tanh(ground_speed * c.stride_cadence / ceiling) * (1.0 - c.cadence_cruise_falloff * cruise_gear);
	stride_rate = maxd(stride_rate, c.dig_in_cadence_rate * start);
	const double cross_rate = maxd(std::abs(turn_rate) * c.crossover_phase_per_turn, stride_rate);
	double rate = 0.0;
	if (stroking > 0.001) {
		rate = ((mix.stride + mix.backward) * stride_rate + mix.crossover * cross_rate + mix.shuffle * c.shuffle_cadence_rate) / stroking;
	}
	stride_phase = wrapd(stride_phase + rate * (1.0 - hold) * delta, 0.0, Math_TAU);
	if (mix.glide > 0.01) {
		glide_phase = wrapd(glide_phase + Math_TAU * c.glide_sway_hz * mix.glide * delta, 0.0, Math_TAU);
	}
	if (stroking < 0.001) {
		intensity = mind(intensity, 1.0);
	}
}

void NativeSkaterGait::strokes(double delta, const Vector2 &travel) {
	const Config &c = cfg;
	clear_strokes();
	const double fwd = travel.y;
	const double along = clampd(fwd / maxd(ground_speed, 0.1), -1.0, 1.0);
	const double skew = clampd(c.stride_skew + c.glide_hold_skew * cruise_gear, 0.0, 0.95);
	const double s = std::sin(stride_phase - skew * std::sin(stride_phase));
	const double phase_opp = stride_phase + Math_PI;
	const double s_opp = std::sin(phase_opp - skew * std::sin(phase_opp));
	const double cs = std::cos(stride_phase - skew * std::sin(stride_phase)) * (1.0 - skew * std::cos(stride_phase)) / (1.0 + skew);
	const double cs_opp = std::cos(phase_opp - skew * std::sin(phase_opp)) * (1.0 - skew * std::cos(phase_opp)) / (1.0 + skew);
	const double amp = intensity * push_scale;

	double w = mix.stride;
	if (w > 0.001) {
		stride_path(w, amp * (1.0 - c.dig_in_chop * start), s, s_opp, cs, cs_opp);
	}

	w = mix.backward;
	if (w > 0.001) {
		ccut_path(w, amp, s, s_opp, cs, cs_opp);
		trunk_pitch += deg_to_rad(c.backpedal_chest_deg) * w;
	}

	w = mix.crossover;
	if (w > 0.001) {
		crossover_path(w, sgn(cross_signed), amp, s, s_opp, cs, cs_opp);
	}

	w = mix.shuffle;
	if (w > 0.001) {
		shuffle_path(w, mix.side, amp, s, s_opp, cs, cs_opp);
	}

	w = mix.glide * speed_t;
	if (w > 0.001) {
		const double sway = std::sin(glide_phase) * deg_to_rad(c.glide_sway_deg) * w;
		trunk_roll += sway;
		l_roll += sway * 0.5;
		r_roll += sway * 0.5;
		const double curve = clampd(std::abs(turn_rate) / maxd(c.carve_ref_turn_rate, 0.001), 0.0, 1.0);
		const double inside_tuck = deg_to_rad(c.glide_inside_tuck_deg) * curve * w;
		if (turn_rate > 0.0) {
			r_tuck += inside_tuck;
		} else {
			l_tuck += inside_tuck;
		}
	}

	const double tight_in = tight_signed * along;
	if (std::abs(tight_in) > 0.001) {
		const double split = 0.5 * c.tight_turn_lead_m * tight_in;
		r_dz -= split;
		l_dz += split;
		push_reach = maxd(push_reach, 0.5 * c.tight_turn_lead_m);
	}

	const double carve_in = carve_signed * along;
	if (std::abs(carve_in) > 0.001) {
		const double lead = 0.5 * c.carve_lead_m * carve_in;
		r_dz -= lead;
		l_dz += lead;
	}

	w = mix.stop;
	if (w > 0.001) {
		stop_path(w, in_legs(travel, stop_yaw), in_legs(travel, stop_yaw_full));
	}

	w = mix.skid;
	if (w > 0.001) {
		skid_path(w, Vector2(travel.x, -travel.y));
	}

	stance_of(s);
	edge_floor = mix.stop + mix.tight + mix.carve;
	sliding = mix.stop + mix.skid;
	authored = 1.0 - mix.glide;

	const double fore_aft = mix.stride + mix.backward + mix.crossover;
	const double s_fund = std::sin(stride_phase);
	trunk_roll += deg_to_rad(c.stride_sway_deg) * intensity * fore_aft * s_fund;
	const double shift_target = fore_aft * s_fund * intensity;
	const double shift_accel = c.weight_spring_stiffness * (shift_target - weight_shift) - c.weight_spring_damping * weight_shift_vel;
	weight_shift_vel += shift_accel * delta;
	weight_shift += weight_shift_vel * delta;
	trunk_roll += deg_to_rad(c.weight_shift_deg) * weight_shift;
}

void NativeSkaterGait::stride_path(double w, double a, double s, double s_opp, double cs, double cs_opp) {
	const Config &c = cfg;
	const double rock = c.stride_rock_m * a * s;
	const double p_l = 0.5 * (1.0 - s);
	const double p_r = 0.5 * (1.0 - s_opp);
	const double out = c.stride_push_out_m * a;
	const double land = -c.stride_land_fwd_m * a;
	const double travel = (c.stride_push_back_m + c.stride_land_fwd_m) * a;
	const double lift = c.stride_lift_m * a;
	const double toe = deg_to_rad(c.stride_toe_out_deg) * mind(a, 1.0);
	l_dx += w * (rock - out * p_l);
	r_dx += w * (rock + out * p_r);
	l_dz += w * (land + travel * p_l);
	r_dz += w * (land + travel * p_r);
	l_dy += w * lift * maxd(cs, 0.0);
	r_dy += w * lift * maxd(cs_opp, 0.0);
	l_yaw += w * toe * p_l;
	r_yaw -= w * toe * p_r;
	l_push = maxd(l_push, w * maxd(-s, 0.0));
	r_push = maxd(r_push, w * maxd(-s_opp, 0.0));
	push_reach = maxd(push_reach, Vector2(out, c.stride_push_back_m * a).length());
}

void NativeSkaterGait::crossover_path(double w, double side, double a, double s, double s_opp,
		double cs, double cs_opp) {
	const Config &c = cfg;
	const double e = engaged();
	const double cross = c.crossover_cross_m * e;
	const double out = c.crossover_out_m * e;
	const double lands = c.crossover_side_m * e;
	const double under = c.crossover_under_m * e;
	const double land = -c.crossover_land_fwd_m * a;
	const double travel = (c.crossover_back_m + c.crossover_land_fwd_m) * a;
	const double lift = c.crossover_lift_m * e;
	const double clear = c.crossover_pass_m * e;
	const double p_l = 0.5 * (1.0 - s);
	const double p_r = 0.5 * (1.0 - s_opp);
	const double up_l = maxd(cs, 0.0);
	const double up_r = maxd(cs_opp, 0.0);
	const bool left_out = side > 0.0;
	const double l_from = left_out ? cross : lands;
	const double l_to = left_out ? out : under;
	const double r_from = left_out ? lands : cross;
	const double r_to = left_out ? under : out;
	l_dx += w * side * (l_from * (1.0 - p_l) - l_to * p_l);
	r_dx += w * side * (r_from * (1.0 - p_r) - r_to * p_r);
	l_dz += w * (land + travel * p_l + clear * up_l * (left_out ? -1.0 : 1.0));
	r_dz += w * (land + travel * p_r + clear * up_r * (left_out ? 1.0 : -1.0));
	l_dy += w * lift * up_l;
	r_dy += w * lift * up_r;
	l_push = maxd(l_push, w * maxd(-s, 0.0));
	r_push = maxd(r_push, w * maxd(-s_opp, 0.0));
	push_reach = maxd(push_reach, maxd(Vector2(cross, c.crossover_land_fwd_m * a).length(),
			maxd(Vector2(out, c.crossover_back_m * a).length(),
					Vector2(under, c.crossover_back_m * a).length())));
}

void NativeSkaterGait::stop_path(double w, const Vector2 &along, const Vector2 &turned) {
	const Config &c = cfg;
	if (along.length_squared() < 1e-6) {
		return;
	}
	const Vector2 t = along.normalized();
	const double spread = c.hockey_stop_spread_m;
	const double lead = c.hockey_stop_lead_m;
	const double front = -stop_side;
	const double stagger = c.hockey_stop_stagger_m;
	l_dx += w * (t.x * lead - spread);
	r_dx += w * (t.x * lead + spread);
	l_dz += w * (t.y * lead + stagger * front);
	r_dz += w * (t.y * lead - stagger * front);
	const Vector2 u = turned.length_squared() > 1e-6 ? turned.normalized() : t;
	const Vector2 across = stop_side > 0.0 ? Vector2(-u.y, u.x) : Vector2(u.y, -u.x);
	const double square = clampd(std::atan2((double)-across.x, (double)-across.y), -Math_PI * 0.5, Math_PI * 0.5);
	l_yaw += w * square;
	r_yaw += w * square;
	push_reach = maxd(push_reach, Vector2(spread + lead, stagger).length());
}

void NativeSkaterGait::skid_path(double w, const Vector2 &along) {
	const Config &c = cfg;
	const Vector2 t = along.length_squared() > 1e-6 ? along.normalized() : Vector2(0.0, -1.0);
	const double spread = c.reversal_spread_m;
	const double lead = c.reversal_lead_m;
	l_dx += w * (t.x * lead - spread);
	r_dx += w * (t.x * lead + spread);
	l_dz += w * t.y * lead;
	r_dz += w * t.y * lead;
	const double toe_in = deg_to_rad(c.reversal_toe_in_deg);
	l_yaw -= w * toe_in;
	r_yaw += w * toe_in;
	push_reach = maxd(push_reach, Vector2(spread + lead, 0.0).length());
}

void NativeSkaterGait::ccut_path(double w, double a, double s, double s_opp, double cs, double cs_opp) {
	const Config &c = cfg;
	const double out = c.ccut_out_m * a;
	const double front = c.ccut_front_m * a;
	const double toe = deg_to_rad(c.ccut_toe_deg) * mind(a, 1.0);
	const double p_l = 0.5 * (1.0 - s);
	const double p_r = 0.5 * (1.0 - s_opp);
	const double bulge_l = std::sin(Math_PI * p_l) * (cs <= 0.0 ? 1.0 : c.ccut_return_share);
	const double bulge_r = std::sin(Math_PI * p_r) * (cs_opp <= 0.0 ? 1.0 : c.ccut_return_share);
	l_dx -= w * out * bulge_l;
	r_dx += w * out * bulge_r;
	l_dz -= w * front * p_l;
	r_dz -= w * front * p_r;
	l_yaw += w * toe * std::cos(Math_PI * p_l);
	r_yaw -= w * toe * std::cos(Math_PI * p_r);
	l_push = maxd(l_push, w * maxd(-cs, 0.0));
	r_push = maxd(r_push, w * maxd(-cs_opp, 0.0));
	push_reach = maxd(push_reach, Vector2(out, front).length());
}

void NativeSkaterGait::shuffle_path(double w, double side, double a, double s, double s_opp,
		double cs, double cs_opp) {
	const Config &c = cfg;
	const double step = c.shuffle_step_m * a;
	const double lift = c.shuffle_lift_m * a;
	l_dx += w * side * step * s;
	r_dx += w * side * step * s_opp;
	l_dy += w * lift * maxd(cs, 0.0);
	r_dy += w * lift * maxd(cs_opp, 0.0);
	l_push = maxd(l_push, w * maxd(-cs, 0.0));
	r_push = maxd(r_push, w * maxd(-cs_opp, 0.0));
	push_reach = maxd(push_reach, step);
}

double NativeSkaterGait::engaged() const {
	return clampd(intensity / maxd(cfg.stance_full_speed_fraction, 0.01), 0.0, 1.0);
}

void NativeSkaterGait::stance_of(double s) {
	const Config &c = cfg;
	const double stroke_sit = engaged() * clampd(1.0 + effort * c.stance_push_gain, 0.0, 1.35) * (1.0 + loaded * c.stance_sit_gain) * (1.0 + c.cadence_glide_stance_gain * cruise_gear);
	const double stride_sit = maxd(stroke_sit, c.dig_in_stance * start * (intensity > 0.01 ? 1.0 : 0.0));
	stance = (mix.stride + mix.backward + mix.shuffle) * stride_sit + mix.crossover * maxd(stroke_sit, c.carve_stance) + mix.glide * maxd(stroke_sit, c.glide_stance * speed_t) + mix.carve * c.carve_stance + mix.tight * c.tight_turn_stance + mix.stop * c.hockey_stop_stance + mix.skid * c.reversal_stance;
	bob = c.stride_bob_m * intensity * (1.0 - s * s) * (mix.stride + mix.backward + mix.crossover);
}

void NativeSkaterGait::ease_mix(double delta) {
	const Config &c = cfg;
	const double k = mind(c.locomotion_blend_speed * delta, 1.0);
	const double kc = mind(c.crossover_commit_speed * delta, 1.0);
	mix.stride = lerpd(mix.stride, target.stride, k);
	cross_signed = lerpd(cross_signed, target.crossover * target.side, kc);
	mix.crossover = std::abs(cross_signed);
	const double uncommitted = maxd(target.crossover - mix.crossover, 0.0);
	carve_signed = lerpd(carve_signed, (target.carve + uncommitted) * target.side, k);
	mix.carve = std::abs(carve_signed);
	mix.backward = lerpd(mix.backward, target.backward, k);
	mix.shuffle = lerpd(mix.shuffle, target.shuffle, k);
	mix.skid = lerpd(mix.skid, target.skid, k);
	tight_signed = lerpd(tight_signed, target.tight * target.side, k);
	mix.tight = std::abs(tight_signed);
	mix.stop = lerpd(mix.stop, target.stop, k);
	double held = mix.stride + mix.crossover + mix.carve + mix.backward + mix.shuffle + mix.skid + mix.tight + mix.stop;
	if (held > 1.0) {
		const double scale = 1.0 / held;
		mix.stride *= scale;
		mix.crossover *= scale;
		mix.carve *= scale;
		cross_signed *= scale;
		carve_signed *= scale;
		mix.backward *= scale;
		mix.shuffle *= scale;
		mix.skid *= scale;
		mix.tight *= scale;
		tight_signed *= scale;
		mix.stop *= scale;
		held = 1.0;
	}
	mix.glide = 1.0 - held;
	if (target.tight > 0.0 || target.shuffle > 0.0 || target.carve > 0.0 || target.crossover > 0.0) {
		mix.side = target.side;
	}
}

void NativeSkaterGait::sample_velocity(double delta, const Vector3 &vel) {
	fd_time += delta;
	if (!have_prev_velocity) {
		prev_velocity = vel;
		have_prev_velocity = true;
		fd_time = 0.0;
		return;
	}
	if (vel == prev_velocity && fd_time < FD_WINDOW_MAX) {
		return;
	}
	const Vector3 accel = (vel - prev_velocity) / (real_t)fd_time;
	const Vector2 travel(vel.x, vel.z);
	fd_effort_target = 0.0;
	if (travel.length() > 0.1) {
		fd_effort_target = clampd(Vector2(accel.x, accel.z).dot(travel.normalized()) / maxd(cfg.stride_effort_ref_accel, 0.001), -1.0, 1.0);
	}
	fd_turn = carve_turn_rate(Vector2(prev_velocity.x, prev_velocity.z), travel, fd_time, cfg.carve_min_speed);
	prev_velocity = vel;
	fd_time = 0.0;
}

void NativeSkaterGait::clear_strokes() {
	l_roll = 0.0;
	r_roll = 0.0;
	l_tuck = 0.0;
	r_tuck = 0.0;
	l_dx = 0.0;
	l_dy = 0.0;
	l_dz = 0.0;
	l_yaw = 0.0;
	r_dx = 0.0;
	r_dy = 0.0;
	r_dz = 0.0;
	r_yaw = 0.0;
	l_push = 0.0;
	r_push = 0.0;
	push_reach = 0.0;
	authored = 0.0;
	sliding = 0.0;
	trunk_pitch = 0.0;
	trunk_roll = 0.0;
	bob = 0.0;
	edge_floor = 0.0;
}

// ── SkaterSkatingCoordinator._align_to_travel ──

Vector2 NativeSkaterGait::align_and_pivot(double delta, const Vector3 &vel, const Basis &basis) {
	const Config &c = cfg;
	const double curve = clampd(std::abs(turn_rate) / maxd(c.carve_ref_turn_rate, 0.001), 0.0, 1.0);
	const Vector3 local_vel = basis.inverse().xform(vel);
	const double fwd = -local_vel.z;
	double align_target = 0.0;
	double psi = prev_psi;
	if (ground_speed > 0.1) {
		psi = std::atan2((double)local_vel.x, fwd);
		const double align_engage = clampd(intensity / maxd(c.stance_full_speed_fraction, 0.01), 0.0, 1.0);
		align_target = clampd(-psi, -deg_to_rad(c.hip_align_max_deg), deg_to_rad(c.hip_align_max_deg)) * align_engage;
	}
	if (!have_prev_psi) {
		psi_smooth = psi;
	} else {
		psi_smooth = wrapd(psi_smooth + angle_diff(psi_smooth, psi) * mind(PSI_SMOOTH_EASE * delta, 1.0), -Math_PI, Math_PI);
	}
	const double abs_psi = std::abs(psi_smooth);
	const double band_lo = deg_to_rad(c.pivot_band_lo_deg);
	const double band_hi = deg_to_rad(c.pivot_band_hi_deg);
	align_target *= 1.0 - maxd(mix.backward, mix.shuffle);
	align_target *= 1.0 - clampd((abs_psi - Math_PI * 0.5) / maxd(band_hi - Math_PI * 0.5, 0.001), 0.0, 1.0);

	double psi_rate_raw = 0.0;
	if (have_prev_psi) {
		psi_rate_raw = angle_diff(prev_psi, psi) / delta;
	}
	prev_psi = psi;
	have_prev_psi = true;
	psi_rate = lerpd(psi_rate, psi_rate_raw, mind(PSI_RATE_EASE * delta, 1.0));
	if (pivot_engaged) {
		if (pivot_should_release(abs_psi, ground_speed, band_lo, band_hi, c.pivot_min_speed)) {
			pivot_engaged = false;
		}
	} else if (pivot_should_engage(abs_psi, std::abs(psi_rate), ground_speed,
					   band_lo, band_hi, c.pivot_rate_min, c.pivot_min_speed)) {
		pivot_engaged = true;
		pivot_sense = pivot_latch_sense(abs_psi, band_lo, band_hi);
	}
	double pivot_target_blend = 0.0;
	if (pivot_engaged) {
		pivot_dwell += delta;
		pivot_target_blend = pivot_hold_depth(abs_psi, band_lo, deg_to_rad(c.pivot_depth_ramp_deg)) * clampd(pivot_dwell / maxd(c.pivot_commit_time, 0.001), 0.0, 1.0) * (1.0 - curve);
	} else {
		pivot_dwell = 0.0;
	}
	pivot_blend = lerpd(pivot_blend, pivot_target_blend, c.pivot_blend_speed * delta);
	double align_speed = c.hip_align_speed;
	pivot_yaw_l = 0.0;
	pivot_yaw_r = 0.0;
	if (pivot_blend > 0.001) {
		const double pivot_p = pivot_phase(abs_psi, pivot_sense, band_lo, band_hi);
		const double pivot_target = pivot_yaw_law(psi_smooth, pivot_sense, pivot_p, c.pivot_step_begin);
		const double v_open = deg_to_rad(c.pivot_mohawk_deg) * pivot_blend * std::sin(Math_PI * pivot_p);
		const double step_sign = sgn(psi_smooth) * pivot_sense;
		if (step_sign > 0.0) {
			pivot_yaw_l = v_open;
		} else if (step_sign < 0.0) {
			pivot_yaw_r = -v_open;
		}
		align_target = lerpd(align_target, pivot_target, pivot_blend);
		align_speed = lerpd(align_speed, c.pivot_yaw_speed, pivot_blend);
	}
	hip_align_yaw = lerpd(hip_align_yaw, align_target, align_speed * delta);
	travel_align_yaw = hip_align_yaw * (1.0 - mix.stop);
	const double ct = std::cos(travel_align_yaw);
	const double st = std::sin(travel_align_yaw);
	return Vector2(local_vel.x * ct - local_vel.z * st, -(local_vel.x * st + local_vel.z * ct));
}

// ── GaitPose ──

void NativeSkaterGait::place(Leg &leg, double pitch, double yaw, double roll, double knee) const {
	leg.pitch = pitch;
	leg.yaw = yaw;
	leg.roll = roll;
	leg.knee = knee;
	leg_place(leg, leg_scale * THIGH_LEN, leg_scale * SHIN_LEN);
}

// GaitPose._reach
void NativeSkaterGait::reach(Leg &leg, double dx, double dy, double dz, double yaw, double level,
		double side) const {
	const double thigh = leg_scale * THIGH_LEN;
	const double shin = leg_scale * SHIN_LEN;
	leg.yaw = yaw;
	if (level <= 0.0) {
		leg.x += dx * leg_scale;
		leg.y += dy * leg_scale;
		leg.z += dz * leg_scale;
		leg_solve(leg, thigh, shin);
		return;
	}
	const Basis frame = Basis().slerp(ice, level);
	const Basis frame_inv = frame.inverse();
	const Basis ice_inv = ice.inverse();
	const double limit = reach_for(frame.xform(Vector3(leg.x, leg.y, leg.z)));
	const double depth = runner_depth(leg, ice);
	const double above = depth - leg.y + HIP_DROP * leg_scale;
	const Vector3 pivot(side * HIP_HALF_WIDTH, -HIP_DROP * leg_scale, 0.0);
	const Vector3 up(0.0, above, 0.0);
	const Vector3 shift = (lean.xform(up) - up) * (real_t)gripping;
	const Vector3 aim(leg.x + dx * leg_scale, leg.y + dy * leg_scale, leg.z + dz * leg_scale);
	double lift = 0.0;
	for (int pass = 0; pass < 3; pass++) {
		const Vector3 on_ice = aim + Vector3(0.0, lift, 0.0);
		Vector3 target = on_ice.lerp(ice_inv.xform(pivot + on_ice - shift) - pivot, level);
		target = frame_inv.xform(within(frame.xform(target), limit));
		leg.x = target.x;
		leg.y = target.y;
		leg.z = target.z;
		leg_solve(leg, thigh, shin);
		lift = (runner_depth(leg, ice) - depth) * level;
	}
}

// GaitPose._reach_for
double NativeSkaterGait::reach_for(const Vector3 &ankle) const {
	return maxd(REACH_MAX * leg_scale * (THIGH_LEN + SHIN_LEN), maxd(
			-(double)ankle.y + (DEPTH_SPARE_M + DEPTH_EASE_M) * leg_scale,
			Vector2(Vector2(ankle.x, ankle.z).length() + REACH_EASE_M * leg_scale, ankle.y).length()));
}

// GaitPose._within
Vector3 NativeSkaterGait::within(const Vector3 &target, double limit) const {
	const double y = -ease_into(-(double)target.y, limit - DEPTH_SPARE_M * leg_scale, DEPTH_EASE_M * leg_scale);
	const double out = Vector2(target.x, target.z).length();
	double keep = 1.0;
	if (out > 0.0) {
		keep = ease_into(out, std::sqrt(maxd(limit * limit - y * y, 0.0)), REACH_EASE_M * leg_scale) / out;
	}
	return Vector3(target.x * keep, y, target.z * keep);
}

// GaitPose.solve_stance, seed_legs and seed_trunk, with no layer between them.
void NativeSkaterGait::solve(double p_stance, double p_width, const Basis &p_lean, const Basis &p_ice) {
	lean = p_lean;
	ice = p_ice;
	stance_hip = deg_to_rad(cfg.stance_hip_deg) * p_stance;
	stance_knee = stance_hip + std::asin(clampd(THIGH_LEN / SHIN_LEN * std::sin(stance_hip), -1.0, 1.0));
	stance_shin = stance_knee - stance_hip;
	drop = leg_scale * (THIGH_LEN * (1.0 - std::cos(stance_hip)) + SHIN_LEN * (1.0 - std::cos(stance_shin)));

	const double shin_frac = SHIN_LEN / (THIGH_LEN + SHIN_LEN);
	const double knee_l = -(stance_knee + l_tuck);
	const double knee_r = -(stance_knee + r_tuck);
	place(leg_l, stance_hip - (knee_l + stance_knee) * shin_frac, pivot_yaw_l, l_roll, knee_l);
	place(leg_r, stance_hip - (knee_r + stance_knee) * shin_frac, pivot_yaw_r, r_roll, knee_r);
	foot_level = authored > 0.001 ? authored : 0.0;
	gripping = foot_level > 0.0 ? clampd(1.0 - sliding / foot_level, 0.0, 1.0) : 1.0;
	reach(leg_l, l_dx - p_width, l_dy, l_dz, pivot_yaw_l + l_yaw, foot_level, -1.0);
	reach(leg_r, r_dx + p_width, r_dy, r_dz, pivot_yaw_r + r_yaw, foot_level, 1.0);
	plant = plant_share(intensity, edge_floor);

	edge_l = clampd(maxd(l_push * intensity, edge_floor), 0.0, 1.0);
	edge_r = clampd(maxd(r_push * intensity, edge_floor), 0.0, 1.0);
}

// ── Outputs ──

Vector4 NativeSkaterGait::get_channels() const {
	return Vector4(stride_phase, stop_yaw, travel_align_yaw, pivot_blend);
}

Vector4 NativeSkaterGait::get_leg_l() const {
	return Vector4(leg_l.pitch, leg_l.roll, leg_l.knee, leg_l.yaw);
}

Vector4 NativeSkaterGait::get_leg_r() const {
	return Vector4(leg_r.pitch, leg_r.roll, leg_r.knee, leg_r.yaw);
}

Vector4 NativeSkaterGait::get_stance() const {
	return Vector4(stance_hip, stance_knee, stance_shin, drop);
}

Vector4 NativeSkaterGait::get_seed() const {
	return Vector4(foot_level, plant, edge_l, edge_r);
}

Vector4 NativeSkaterGait::get_trunk() const {
	return Vector4(bob, trunk_pitch, trunk_roll, 0.0);
}

Vector4 NativeSkaterGait::get_push() const {
	return Vector4(l_push, r_push,
			intensity * push_scale * (mix.stride + mix.crossover + mix.backward + mix.shuffle), 0.0);
}

PackedFloat64Array NativeSkaterGait::get_mix() const {
	PackedFloat64Array out;
	out.push_back(mix.glide);
	out.push_back(mix.stride);
	out.push_back(mix.crossover);
	out.push_back(mix.carve);
	out.push_back(mix.backward);
	out.push_back(mix.shuffle);
	out.push_back(mix.skid);
	out.push_back(mix.tight);
	out.push_back(mix.stop);
	out.push_back(mix.side);
	return out;
}

void NativeSkaterGait::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "controller"), &NativeSkaterGait::configure);
	ClassDB::bind_method(D_METHOD("set_leg_scale", "leg_scale"), &NativeSkaterGait::set_leg_scale);
	ClassDB::bind_method(D_METHOD("reset"), &NativeSkaterGait::reset);
	ClassDB::bind_method(D_METHOD("locomote", "delta", "velocity", "intent", "basis", "flags", "hold"),
			&NativeSkaterGait::locomote);
	ClassDB::bind_method(D_METHOD("get_channels"), &NativeSkaterGait::get_channels);
	ClassDB::bind_method(D_METHOD("solve", "stance", "width", "lean", "ice"), &NativeSkaterGait::solve);
	ClassDB::bind_method(D_METHOD("get_leg_l"), &NativeSkaterGait::get_leg_l);
	ClassDB::bind_method(D_METHOD("get_leg_r"), &NativeSkaterGait::get_leg_r);
	ClassDB::bind_method(D_METHOD("get_stance"), &NativeSkaterGait::get_stance);
	ClassDB::bind_method(D_METHOD("get_seed"), &NativeSkaterGait::get_seed);
	ClassDB::bind_method(D_METHOD("get_trunk"), &NativeSkaterGait::get_trunk);
	ClassDB::bind_method(D_METHOD("get_push"), &NativeSkaterGait::get_push);
	ClassDB::bind_method(D_METHOD("get_mix"), &NativeSkaterGait::get_mix);
}

} // namespace mitts
