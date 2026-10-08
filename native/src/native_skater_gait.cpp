#include "native_skater_gait.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cmath>

using namespace godot;

namespace mitts {

// GaitPose.THIGH_LEN / SHIN_LEN.
static constexpr double THIGH_LEN = 0.31;
static constexpr double SHIN_LEN = 0.45;
// SkaterLocomotion._FD_WINDOW_MAX.
static constexpr double FD_WINDOW_MAX = 0.1;
// SkaterSkatingCoordinator._PSI_RATE_EASE / _PSI_SMOOTH_EASE.
static constexpr double PSI_RATE_EASE = 10.0;
static constexpr double PSI_SMOOTH_EASE = 15.0;
// PivotRules.RELEASE_MARGIN.
static constexpr double PIVOT_RELEASE_MARGIN = 8.0 * Math_PI / 180.0;
// SkaterMovementRules.GRIP_MIN_SPEED.
static constexpr double GRIP_MIN_SPEED = 0.5;
// LocomotionRules._INTENT_MIN_SQ.
static constexpr double INTENT_MIN_SQ = 0.0025;

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
	stride_phase = 0.0;
	intensity = 0.0;
	effort = 0.0;
	turn_rate = 0.0;
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

void NativeSkaterGait::locomote(double delta, const Vector3 &velocity, const Vector2 &intent,
		const Basis &basis, int64_t flags, double hold) {
	sense(delta, velocity, intent, basis, (flags & FLAG_BRAKE) != 0,
			(flags & FLAG_STANCE) != 0, (flags & FLAG_PLANTED) != 0, hold);
	const double fwd = align_and_pivot(delta, velocity, basis);
	strokes(delta, fwd);
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
	loaded = lerpd(loaded, (stance_active && !planted) ? 1.0 : 0.0,
			c.locomotion_blend_speed * delta);

	// LocomotionRules.classify
	const Vector3 col_z = basis.get_column(2);
	const Vector2 facing(-col_z.x, -col_z.z);
	const Vector2 velocity2(vel.x, vel.z);
	target.clear();
	{
		Mix &out = target;
		const double speed = velocity2.length();
		const bool has_input = intent.length_squared() > INTENT_MIN_SQ;
		if (speed <= GRIP_MIN_SPEED) {
			if (!has_input) {
				out.glide = 1.0;
			} else {
				const Vector2 dir = intent.normalized();
				const double ahead = facing.dot(dir);
				const double across = facing.cross(dir);
				const double a = maxd(ahead, 0.0);
				const double b = maxd(-ahead, 0.0);
				out.stride = a * a;
				out.backward = b * b;
				out.shuffle = across * across;
				out.side = across != 0.0 ? sgn(across) : 1.0;
			}
		} else {
			const Vector2 travel = velocity2 / (real_t)speed;
			if (brake) {
				if (has_input) {
					const double steer = travel.angle_to(intent);
					out.side = steer != 0.0 ? sgn(steer) : 1.0;
				}
				out.stop = 1.0;
			} else if (!has_input) {
				out.glide = 1.0;
			} else {
				const double turn = travel.angle_to(intent);
				const double along = std::cos(turn);
				const double across_t = std::sin(turn);
				out.side = across_t != 0.0 ? sgn(across_t) : 1.0;
				const double back = maxd(-along, 0.0);
				out.skid = back * back;
				const double fore = maxd(along, 0.0);
				if (travel.dot(facing) < 0.0) {
					out.backward = fore * fore + across_t * across_t;
				} else {
					out.stride = fore * fore;
					if (stance_active) {
						out.tight = across_t * across_t;
					} else {
						out.crossover = across_t * across_t;
					}
				}
			}
		}
	}
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
	stop_yaw = mix.stop > 0.001
			? hockey_stop_yaw(local_vel, stop_side, deg_to_rad(c.hockey_stop_max_yaw_deg)) * mix.stop
			: 0.0;

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
	const double rate = (mix.stride + mix.backward) * stride_rate + mix.crossover * cross_rate + mix.shuffle * c.shuffle_cadence_rate;
	stride_phase = wrapd(stride_phase + rate * (1.0 - hold) * delta, 0.0, Math_TAU);
	if (mix.glide > 0.01) {
		glide_phase = wrapd(glide_phase + Math_TAU * c.glide_sway_hz * mix.glide * delta, 0.0, Math_TAU);
	}
	if (stroking < 0.001) {
		intensity = mind(intensity, 1.0);
	}
}

void NativeSkaterGait::strokes(double delta, double fwd) {
	const Config &c = cfg;
	clear_strokes();
	const double skew = clampd(c.stride_skew + c.glide_hold_skew * cruise_gear, 0.0, 0.95);
	const double s = std::sin(stride_phase - skew * std::sin(stride_phase));
	const double phase_opp = stride_phase + Math_PI;
	const double s_opp = std::sin(phase_opp - skew * std::sin(phase_opp));
	const double cs = std::cos(stride_phase - skew * std::sin(stride_phase)) * (1.0 - skew * std::cos(stride_phase)) / (1.0 + skew);
	const double cs_opp = std::cos(phase_opp - skew * std::sin(phase_opp)) * (1.0 - skew * std::cos(phase_opp)) / (1.0 + skew);
	const double ext_l = maxd(-s, 0.0);
	const double ext_r = maxd(-s_opp, 0.0);
	const double amp = intensity * push_scale;
	const double bias = c.stride_rear_bias;

	double w = mix.stride;
	if (w > 0.001) {
		const double push = deg_to_rad(c.stride_pitch_deg) * amp * (1.0 - c.dig_in_chop * start);
		stroke(w, push, deg_to_rad(c.stride_roll_deg) * amp, deg_to_rad(c.stride_abduction_deg) * amp,
				deg_to_rad(c.stride_knee_deg) * amp, s, s_opp, cs, cs_opp, ext_l, ext_r, bias);
	}

	w = mix.backward;
	if (w > 0.001) {
		const double push_b = -deg_to_rad(c.stride_back_pitch_deg) * amp * (1.0 - c.backpedal_pitch_fade);
		stroke(w, push_b,
				deg_to_rad(c.stride_roll_deg + c.backpedal_ccut_roll_deg) * amp,
				deg_to_rad(c.stride_abduction_deg + c.backpedal_ccut_sweep_deg) * amp,
				deg_to_rad(c.stride_knee_deg) * amp * (1.0 - c.backpedal_tuck_fade),
				s, s_opp, cs, cs_opp, ext_l, ext_r, bias);
		trunk_pitch += deg_to_rad(c.backpedal_chest_deg) * w;
	}

	w = mix.crossover;
	if (w > 0.001) {
		const double residual = 1.0 - c.carve_stride_fade;
		stroke(w, deg_to_rad(c.stride_pitch_deg) * amp * residual, 0.0, 0.0,
				deg_to_rad(c.stride_knee_deg) * amp * residual,
				s, s_opp, cs, cs_opp, ext_l, ext_r, bias);
		const double over = maxd(s, 0.0);
		const double under = maxd(-s, 0.0);
		const double over_roll = deg_to_rad(c.carve_over_roll_deg) * intensity * over * w;
		const double under_roll = deg_to_rad(c.carve_under_roll_deg) * intensity * under * w;
		const double over_pitch = deg_to_rad(c.carve_over_pitch_deg) * intensity * over * w;
		const double clearance = deg_to_rad(c.carve_clearance_knee_deg) * intensity * maxd(cs, 0.0) * w;
		if (cross_signed > 0.0) {
			l_roll += over_roll;
			l_pitch += over_pitch;
			l_tuck += clearance;
			r_roll -= under_roll;
			r_ext = maxd(r_ext, under * w);
		} else {
			r_roll -= over_roll;
			r_pitch += over_pitch;
			r_tuck += clearance;
			l_roll += under_roll;
			l_ext = maxd(l_ext, under * w);
		}
	}

	w = mix.shuffle;
	if (w > 0.001) {
		const double lean = mix.side * deg_to_rad(c.crossover_lean_deg) * intensity;
		const double scissor = deg_to_rad(c.crossover_scissor_deg) * amp;
		l_roll += w * (lean + s * scissor);
		r_roll += w * (lean + s_opp * scissor);
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

	w = mix.tight;
	if (w > 0.001) {
		const double split = deg_to_rad(c.tight_turn_split_deg) * w;
		if (mix.side * sgn(fwd) > 0.0) {
			r_pitch += split;
			l_pitch -= split;
		} else {
			l_pitch += split;
			r_pitch -= split;
		}
	}

	w = mix.stop;
	if (w > 0.001) {
		const double stop_split = deg_to_rad(c.hockey_stop_split_deg) * w * stop_side;
		l_pitch += stop_split;
		r_pitch -= stop_split;
		const double edge = deg_to_rad(c.hockey_stop_edge_deg) * w * stop_side;
		l_roll += edge;
		r_roll += edge;
	}

	w = mix.skid;
	if (w > 0.001) {
		const double plant = deg_to_rad(c.reversal_plant_deg) * w;
		l_roll -= plant;
		r_roll += plant;
	}

	stance_of(s);
	edge_floor = mix.stop + mix.tight;

	const double fore_aft = mix.stride + mix.backward + mix.crossover;
	const double s_fund = std::sin(stride_phase);
	trunk_roll += deg_to_rad(c.stride_sway_deg) * intensity * fore_aft * s_fund;
	const double shift_target = fore_aft * s_fund * intensity;
	const double shift_accel = c.weight_spring_stiffness * (shift_target - weight_shift) - c.weight_spring_damping * weight_shift_vel;
	weight_shift_vel += shift_accel * delta;
	weight_shift += weight_shift_vel * delta;
	trunk_roll += deg_to_rad(c.weight_shift_deg) * weight_shift;
	trunk_pitch += -deg_to_rad(c.stance_lean_deg) * loaded * (1.0 - mix.stop - mix.skid);
}

void NativeSkaterGait::stroke(double w, double push, double rock, double flare, double tuck,
		double s, double s_opp, double cs, double cs_opp,
		double ext_l, double ext_r, double bias) {
	l_pitch += w * (s - bias) * push;
	r_pitch += w * (s_opp - bias) * push;
	l_roll += w * (s * rock - flare * ext_l);
	r_roll += w * (s * rock + flare * ext_r);
	l_ext = maxd(l_ext, w * ext_l);
	r_ext = maxd(r_ext, w * ext_r);
	l_tuck += w * tuck * maxd(cs, 0.0);
	r_tuck += w * tuck * maxd(cs_opp, 0.0);
}

void NativeSkaterGait::stance_of(double s) {
	const Config &c = cfg;
	const double stroke_sit = clampd(intensity / maxd(c.stance_full_speed_fraction, 0.01), 0.0, 1.0) * clampd(1.0 + effort * c.stance_push_gain, 0.0, 1.35) * (1.0 + loaded * c.stance_sit_gain) * (1.0 + c.cadence_glide_stance_gain * cruise_gear);
	const double stride_sit = maxd(stroke_sit, c.dig_in_stance * start * (intensity > 0.01 ? 1.0 : 0.0));
	stance = (mix.stride + mix.backward + mix.shuffle) * stride_sit + mix.crossover * maxd(stroke_sit, c.carve_stance) + mix.glide * maxd(stroke_sit, c.glide_stance * speed_t) + mix.tight * c.tight_turn_stance + mix.stop * c.hockey_stop_stance + mix.skid * c.reversal_stance;
	stance = maxd(stance, loaded * c.stance_sit_floor);
	bob = c.stride_bob_m * intensity * (1.0 - s * s) * (mix.stride + mix.backward + mix.crossover);
}

void NativeSkaterGait::ease_mix(double delta) {
	const Config &c = cfg;
	const double k = mind(c.locomotion_blend_speed * delta, 1.0);
	const double kc = mind(c.crossover_commit_speed * delta, 1.0);
	mix.stride = lerpd(mix.stride, target.stride, k);
	cross_signed = lerpd(cross_signed, target.crossover * target.side, kc);
	mix.crossover = std::abs(cross_signed);
	mix.backward = lerpd(mix.backward, target.backward, k);
	mix.shuffle = lerpd(mix.shuffle, target.shuffle, k);
	mix.skid = lerpd(mix.skid, target.skid, k);
	mix.tight = lerpd(mix.tight, target.tight, k);
	mix.stop = lerpd(mix.stop, target.stop, k);
	double held = mix.stride + mix.crossover + mix.backward + mix.shuffle + mix.skid + mix.tight + mix.stop;
	if (held > 1.0) {
		const double scale = 1.0 / held;
		mix.stride *= scale;
		mix.crossover *= scale;
		cross_signed *= scale;
		mix.backward *= scale;
		mix.shuffle *= scale;
		mix.skid *= scale;
		mix.tight *= scale;
		mix.stop *= scale;
		held = 1.0;
	}
	mix.glide = 1.0 - held;
	if (target.tight > 0.0 || target.shuffle > 0.0) {
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
	l_pitch = 0.0;
	r_pitch = 0.0;
	l_roll = 0.0;
	r_roll = 0.0;
	l_ext = 0.0;
	r_ext = 0.0;
	l_tuck = 0.0;
	r_tuck = 0.0;
	trunk_pitch = 0.0;
	trunk_roll = 0.0;
	bob = 0.0;
	edge_floor = 0.0;
}

// ── SkaterSkatingCoordinator._align_to_travel ──

double NativeSkaterGait::align_and_pivot(double delta, const Vector3 &vel, const Basis &basis) {
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
	return -(local_vel.x * std::sin(travel_align_yaw) + local_vel.z * std::cos(travel_align_yaw));
}

// ── Outputs ──

Vector4 NativeSkaterGait::get_channels() const {
	return Vector4(stride_phase, stop_yaw, travel_align_yaw, pivot_blend);
}

double NativeSkaterGait::get_base_stance() const {
	return maxd(stance, cfg.pivot_stance * pivot_blend);
}

Vector4 NativeSkaterGait::get_stroke_legs() const {
	return Vector4(l_pitch, l_roll, r_pitch, r_roll);
}

Vector4 NativeSkaterGait::get_stroke_knees() const {
	return Vector4(l_ext, r_ext, l_tuck, r_tuck);
}

Vector4 NativeSkaterGait::get_stroke_body() const {
	return Vector4(bob, trunk_pitch, trunk_roll, edge_floor);
}

Vector4 NativeSkaterGait::get_stroke_drive() const {
	return Vector4(intensity, pivot_yaw_l, pivot_yaw_r, 0.0);
}

// GaitPose.solve_stance, seed_legs, solve_knees and seed_trunk, with no layer
// between them.
void NativeSkaterGait::solve(double p_stance) {
	const double hip = deg_to_rad(cfg.stance_hip_deg) * p_stance;
	const double stance_knee = hip + std::asin(clampd(THIGH_LEN / SHIN_LEN * std::sin(hip), -1.0, 1.0));
	const double stance_shin = stance_knee - hip;
	p_drop = leg_scale * (THIGH_LEN * (1.0 - std::cos(hip)) + SHIN_LEN * (1.0 - std::cos(stance_shin)));
	p_l_pitch = hip + l_pitch;
	p_l_roll = l_roll;
	p_r_pitch = hip + r_pitch;
	p_r_roll = r_roll;
	const double r = cfg.stance_knee_release * intensity;
	p_l_knee = -(stance_knee * (1.0 - r * l_ext) + l_tuck);
	p_r_knee = -(stance_knee * (1.0 - r * r_ext) + r_tuck);
	const double shin_frac = SHIN_LEN / (THIGH_LEN + SHIN_LEN);
	p_l_pitch += -(p_l_knee + stance_knee) * shin_frac;
	p_r_pitch += -(p_r_knee + stance_knee) * shin_frac;
	p_drop += bob;
	p_trunk_pitch = trunk_pitch;
	p_trunk_roll = trunk_roll;
	p_edge_l = clampd(maxd(l_ext * intensity, edge_floor), 0.0, 1.0);
	p_edge_r = clampd(maxd(r_ext * intensity, edge_floor), 0.0, 1.0);
}

Vector4 NativeSkaterGait::get_leg_l() const {
	return Vector4(p_l_pitch, p_l_roll, p_l_knee, pivot_yaw_l);
}

Vector4 NativeSkaterGait::get_leg_r() const {
	return Vector4(p_r_pitch, p_r_roll, p_r_knee, pivot_yaw_r);
}

Vector4 NativeSkaterGait::get_body() const {
	return Vector4(p_drop, p_trunk_pitch, p_trunk_roll, 0.0);
}

Vector2 NativeSkaterGait::get_edges() const {
	return Vector2(p_edge_l, p_edge_r);
}

PackedFloat64Array NativeSkaterGait::get_mix() const {
	PackedFloat64Array out;
	out.push_back(mix.glide);
	out.push_back(mix.stride);
	out.push_back(mix.crossover);
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
	ClassDB::bind_method(D_METHOD("get_base_stance"), &NativeSkaterGait::get_base_stance);
	ClassDB::bind_method(D_METHOD("get_stroke_legs"), &NativeSkaterGait::get_stroke_legs);
	ClassDB::bind_method(D_METHOD("get_stroke_knees"), &NativeSkaterGait::get_stroke_knees);
	ClassDB::bind_method(D_METHOD("get_stroke_body"), &NativeSkaterGait::get_stroke_body);
	ClassDB::bind_method(D_METHOD("get_stroke_drive"), &NativeSkaterGait::get_stroke_drive);
	ClassDB::bind_method(D_METHOD("solve", "stance"), &NativeSkaterGait::solve);
	ClassDB::bind_method(D_METHOD("get_leg_l"), &NativeSkaterGait::get_leg_l);
	ClassDB::bind_method(D_METHOD("get_leg_r"), &NativeSkaterGait::get_leg_r);
	ClassDB::bind_method(D_METHOD("get_body"), &NativeSkaterGait::get_body);
	ClassDB::bind_method(D_METHOD("get_edges"), &NativeSkaterGait::get_edges);
	ClassDB::bind_method(D_METHOD("get_mix"), &NativeSkaterGait::get_mix);
}

} // namespace mitts
