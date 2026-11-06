#include "native_evade_read.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <limits>

using namespace godot;

namespace mitts {

namespace {

constexpr double TAU_D = 6.28318530717958647692;

// A coordinate the GDScript holds in a Vector3, whose components are float.
inline double f32(double v) {
	return (double)(float)v;
}

} // namespace

void NativeEvadeRead::set_kinematics(double p_maneuver_accel, double p_stick_reach,
		double p_ref_speed, double p_reaction_s, double p_free_shed, double p_shed_decel,
		double p_reversal_brake, double p_power_knee, double p_efficiency,
		double p_safe_margin) {
	maneuver_accel = p_maneuver_accel;
	stick_reach = p_stick_reach;
	ref_speed = p_ref_speed;
	reaction_s = p_reaction_s;
	free_shed = p_free_shed;
	shed_decel = p_shed_decel;
	reversal_brake = p_reversal_brake;
	power_knee = p_power_knee;
	efficiency = p_efficiency;
	safe_margin = p_safe_margin;
}

void NativeEvadeRead::set_rink(double p_inner_half_width, double p_inner_half_length,
		double p_corner_radius, double p_corner_center_x, double p_corner_center_z) {
	inner_half_width = p_inner_half_width;
	inner_half_length = p_inner_half_length;
	corner_radius = p_corner_radius;
	corner_center_x = p_corner_center_x;
	corner_center_z = p_corner_center_z;
}

void NativeEvadeRead::set_sweep(double p_horizon_s, int64_t p_angles,
		const PackedFloat64Array &p_rings, double p_saturated_m, double p_poke_contact,
		double p_dwell_half_band) {
	horizon_s = p_horizon_s;
	angles = (int)p_angles;
	rings.resize(p_rings.size());
	for (int64_t i = 0; i < p_rings.size(); i++) {
		rings[i] = p_rings[i];
	}
	saturated_m = p_saturated_m;
	poke_contact = p_poke_contact;
	dwell_half_band = p_dwell_half_band;
}

// AICarrySpace.board_gap_m.
double NativeEvadeRead::board_gap(double x, double z) const {
	const double ax = std::fabs(x);
	const double az = std::fabs(z);
	if (ax > corner_center_x && az > corner_center_z) {
		const double dx = ax - corner_center_x;
		const double dz = az - corner_center_z;
		return corner_radius - std::sqrt(dx * dx + dz * dz);
	}
	return std::fmin(inner_half_width - ax, inner_half_length - az);
}

// AIStrideRamp.distance_in.
double NativeEvadeRead::distance_in(double v0, double time, double vmax, double accel) const {
	const double a = std::fmax(accel * efficiency, 0.001);
	const double p = a * power_knee;
	const double knee = std::fmin(power_knee, vmax);
	double v = v0 < 0.0 ? 0.0 : (v0 > vmax ? vmax : v0);
	double tau = std::fmax(time, 0.0);
	double d = 0.0;
	if (v < knee) {
		const double t_a = (knee - v) / a;
		if (tau <= t_a) {
			return v * tau + 0.5 * a * tau * tau;
		}
		d += (knee * knee - v * v) / (2.0 * a);
		tau -= t_a;
		v = knee;
	}
	if (v < vmax) {
		const double t_b = (vmax * vmax - v * v) / (2.0 * p);
		if (tau <= t_b) {
			const double v_end = std::sqrt(v * v + 2.0 * p * tau);
			return d + (v_end * v_end * v_end - v * v * v) / (3.0 * p);
		}
		d += (vmax * vmax * vmax - v * v * v) / (3.0 * p);
		tau -= t_b;
	}
	return d + vmax * tau;
}

// AICarrySpace._committed_clearance.
double NativeEvadeRead::committed_clearance(double point_x, double point_z, double tau,
		double px, double pz, double vx, double vz, double accel, double stick, double vmax,
		double lateral_grip) const {
	const double dx = point_x - px;
	const double dz = point_z - pz;
	const double dist = std::sqrt(dx * dx + dz * dz);
	double d = 0.0;
	if (tau > 0.0 && dist > 0.001) {
		const double inv = 1.0 / dist;
		const double v_along = (vx * dx + vz * dz) * inv;
		const double v_perp = std::fabs((vx * dz - vz * dx) * inv);
		const double grip = std::fmax(lateral_grip, 0.001);
		double tau_p = tau - std::fmax(0.0, v_perp - free_shed * grip) / (shed_decel * grip);
		if (tau_p > 0.0) {
			double v0 = v_along;
			if (v0 < 0.0) {
				const double t_b = std::fmin(-v0 / reversal_brake, tau_p);
				d = v0 * t_b + 0.5 * reversal_brake * t_b * t_b;
				v0 += reversal_brake * t_b;
				tau_p -= t_b;
			}
			d += distance_in(v0, tau_p, vmax, accel);
		}
	}
	return dist - d - stick;
}

// AICarrySpace.reach_clearance with the whole window committed, no escape gate
// and no chase: the evade read's own call.
double NativeEvadeRead::reach_clearance(double px, double pz, double time,
		const std::vector<Defender> &defs, double abort_below) const {
	const double inf = std::numeric_limits<double>::infinity();
	double worst = inf;
	for (const Defender &o : defs) {
		const double speed_ub = std::fmax(o.vmax, std::fabs(o.vx) + std::fabs(o.vz));
		const double need = worst + speed_ub * time + o.stick;
		if (need <= 0.0) {
			continue;
		}
		const double sdx = px - o.x;
		const double sdz = pz - o.z;
		if (sdx * sdx + sdz * sdz >= need * need) {
			continue;
		}
		// _reach_clearance_one, w = time.
		const double tau = std::fmax(0.0, std::fmin(time, time) - reaction_s);
		const double coast = time - tau;
		const double clear = committed_clearance(px, pz, tau, o.x + o.vx * coast,
				o.z + o.vz * coast, o.vx, o.vz, o.accel, o.stick, o.vmax, o.grip);
		if (clear < worst) {
			worst = clear;
			if (worst < abort_below) {
				return worst;
			}
		}
	}
	return worst;
}

// AIEvadeRead._clearance_bound.
double NativeEvadeRead::clearance_bound(double px, double pz,
		const std::vector<Defender> &defs) const {
	double bound = std::numeric_limits<double>::infinity();
	for (const Defender &o : defs) {
		const double dx = px - o.bound_x;
		const double dz = pz - o.bound_z;
		bound = std::fmin(bound, std::sqrt(dx * dx + dz * dz) + o.bound_slack);
	}
	return bound;
}

// AICarrySpace.clearance_to_safety.
double NativeEvadeRead::clearance_to_safety(double clearance) const {
	const double s = (clearance - (poke_contact - dwell_half_band)) / (2.0 * dwell_half_band);
	return s < 0.0 ? 0.0 : (s > 1.0 ? 1.0 : s);
}

double NativeEvadeRead::evade_safety(const Vector3 &carrier_pos, const Vector3 &carrier_vel,
		const Array &opponents, const Array &opponent_vels, double handle_reach,
		const PackedFloat64Array &caps) const {
	const double inf = std::numeric_limits<double>::infinity();
	const int64_t n = opponents.size();
	const double proj_x = (double)carrier_pos.x + (double)carrier_vel.x * horizon_s;
	const double proj_z = (double)carrier_pos.z + (double)carrier_vel.z * horizon_s;
	const double cx = f32(proj_x);
	const double cz = f32(proj_z);
	// reach_clearance: nothing to evade reads fully clear.
	if (n == 0 || opponent_vels.size() != n) {
		return safe_margin >= saturated_m ? 1.0 : clearance_to_safety(safe_margin);
	}
	const bool has_caps = caps.size() == n * 4;
	const double tau = std::fmax(0.0, horizon_s - reaction_s);
	const double coast = horizon_s - tau;
	std::vector<Defender> defs((size_t)n);
	for (int64_t i = 0; i < n; i++) {
		const Vector3 p = opponents[i];
		const Vector3 v = opponent_vels[i];
		Defender &o = defs[(size_t)i];
		o.x = p.x;
		o.z = p.z;
		o.vx = v.x;
		o.vz = v.z;
		o.accel = maneuver_accel;
		o.stick = stick_reach;
		o.vmax = ref_speed;
		o.grip = 1.0;
		if (has_caps) {
			o.accel = caps[i * 4];
			o.stick = caps[i * 4 + 1];
			o.vmax = caps[i * 4 + 2];
			o.grip = caps[i * 4 + 3];
		}
		// _fill_clearance_bounds.
		const double speed = std::sqrt(o.vx * o.vx + o.vz * o.vz);
		double least = -speed * speed / (2.0 * reversal_brake);
		if (speed <= free_shed * std::fmax(o.grip, 0.001)) {
			const double t_b = std::fmin(speed / reversal_brake, tau);
			least = -speed * t_b + 0.5 * reversal_brake * t_b * t_b
					+ distance_in(0.0, tau - t_b, o.vmax, o.accel);
		}
		o.bound_x = o.x + o.vx * coast;
		o.bound_z = o.z + o.vz * coast;
		o.bound_slack = -least - o.stick;
	}
	double best_clear = reach_clearance(cx, cz, horizon_s, defs, -inf);
	if (best_clear >= saturated_m) {
		return 1.0;
	}
	const double env = 0.5 * maneuver_accel * horizon_s * horizon_s + handle_reach;
	std::vector<double> bound((size_t)angles);
	std::vector<double> sx((size_t)angles);
	std::vector<double> sz((size_t)angles);
	for (int ring = (int)rings.size() - 1; ring >= 0; ring--) {
		const double radius = env * rings[(size_t)ring];
		if (clearance_bound(cx, cz, defs) + radius <= best_clear) {
			continue;
		}
		int top = -1;
		for (int k = 0; k < angles; k++) {
			const double ang = TAU_D * (double)k / (double)angles;
			sx[k] = f32(proj_x + std::cos(ang) * radius);
			sz[k] = f32(proj_z + std::sin(ang) * radius);
			const double ub = board_gap(sx[k], sz[k]) < 0.0 ? -inf
					: clearance_bound(sx[k], sz[k], defs);
			bound[k] = ub;
			if (ub > best_clear && (top < 0 || ub > bound[top])) {
				top = k;
			}
		}
		if (top < 0) {
			continue;
		}
		for (int read_top = 0; read_top < 2; read_top++) {
			for (int k = 0; k < angles; k++) {
				if ((read_top == 0) != (k == top) || bound[k] <= best_clear) {
					continue;
				}
				const double c = reach_clearance(sx[k], sz[k], horizon_s, defs, best_clear);
				if (c > best_clear) {
					best_clear = c;
					if (best_clear >= saturated_m) {
						return 1.0;
					}
				}
			}
		}
	}
	return clearance_to_safety(best_clear);
}

void NativeEvadeRead::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_kinematics", "maneuver_accel", "stick_reach",
								 "ref_speed", "reaction_s", "free_shed", "shed_decel",
								 "reversal_brake", "power_knee", "efficiency", "safe_margin"),
			&NativeEvadeRead::set_kinematics);
	ClassDB::bind_method(D_METHOD("set_rink", "inner_half_width", "inner_half_length",
								 "corner_radius", "corner_center_x", "corner_center_z"),
			&NativeEvadeRead::set_rink);
	ClassDB::bind_method(D_METHOD("set_sweep", "horizon_s", "angles", "rings", "saturated_m",
								 "poke_contact", "dwell_half_band"),
			&NativeEvadeRead::set_sweep);
	ClassDB::bind_method(D_METHOD("evade_safety", "carrier_pos", "carrier_vel", "opponents",
								 "opponent_vels", "handle_reach", "caps"),
			&NativeEvadeRead::evade_safety);
}

} // namespace mitts
