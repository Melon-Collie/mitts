#include "native_carry_space.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <limits>

using namespace godot;

namespace mitts {

namespace {

constexpr double TAU_D = 6.28318530717958647692;
constexpr double INF_D = std::numeric_limits<double>::infinity();

// A coordinate the GDScript holds in a Vector3 or Vector2, whose components are
// float.
inline double f32(double v) {
	return (double)(float)v;
}

inline double clamp01(double v) {
	return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

} // namespace

void NativeCarrySpace::set_kinematics(double p_maneuver_accel, double p_stick_reach,
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

void NativeCarrySpace::set_rink(double p_inner_half_width, double p_inner_half_length,
		double p_corner_radius, double p_corner_center_x, double p_corner_center_z) {
	inner_half_width = p_inner_half_width;
	inner_half_length = p_inner_half_length;
	corner_radius = p_corner_radius;
	corner_center_x = p_corner_center_x;
	corner_center_z = p_corner_center_z;
}

void NativeCarrySpace::set_sweep(double p_horizon_s, int64_t p_angles,
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

void NativeCarrySpace::set_carry(double p_transit_strip, double p_transit_safe,
		double p_lunge_window_s, double p_protect_shift, double p_league_blade_reach) {
	transit_strip = p_transit_strip;
	transit_safe = p_transit_safe;
	lunge_window_s = p_lunge_window_s;
	protect_shift = p_protect_shift;
	league_blade_reach = p_league_blade_reach;
}

bool NativeCarrySpace::load(const Array &opponents, const Array &opponent_vels,
		const PackedFloat64Array &caps, std::vector<Defender> &defs) const {
	const int64_t n = opponents.size();
	const bool valid = n > 0 && opponent_vels.size() == n;
	const bool has_caps = caps.size() == n * CAPS_PER;
	defs.resize(valid ? (size_t)n : 0);
	if (!valid) {
		return false;
	}
	const double *c = has_caps ? caps.ptr() : nullptr;
	for (int64_t i = 0; i < n; i++) {
		const Vector3 p = opponents[i];
		const Vector3 v = opponent_vels[i];
		Defender &o = defs[(size_t)i];
		o.x = p.x;
		o.z = p.z;
		o.vx = v.x;
		o.vz = v.z;
		if (c != nullptr) {
			o.accel = c[i * CAPS_PER];
			o.stick = c[i * CAPS_PER + 1];
			o.vmax = c[i * CAPS_PER + 2];
			o.grip = c[i * CAPS_PER + 3];
			o.blade_reach = c[i * CAPS_PER + 4];
		} else {
			o.accel = maneuver_accel;
			o.stick = stick_reach;
			o.vmax = ref_speed;
			o.grip = 1.0;
			o.blade_reach = league_blade_reach;
		}
		o.bound_x = 0.0;
		o.bound_z = 0.0;
		o.bound_slack = 0.0;
	}
	return true;
}

// AICarrySpace.board_gap_m.
double NativeCarrySpace::board_gap(double x, double z) const {
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
double NativeCarrySpace::distance_in(double v0, double time, double vmax, double accel) const {
	const double a = std::fmax(accel * efficiency, 0.001);
	const double p = a * power_knee;
	const double knee = std::fmin(power_knee, vmax);
	double v = clampd(v0, 0.0, vmax);
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
double NativeCarrySpace::committed_clearance(double point_x, double point_z, double tau,
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

// AICarrySpace._stopped_clearance.
double NativeCarrySpace::stopped_clearance(double point_x, double point_z, double time,
		double w, const Defender &o, double accel, double pace_share) const {
	const double tau = std::fmax(0.0, std::fmin(time, w) - reaction_s);
	const double read = std::fmin(time - tau, reaction_s);
	const double speed = std::sqrt(o.vx * o.vx + o.vz * o.vz);
	const double brake = reversal_brake;
	const double t_b = std::fmin(speed / brake, time - tau - read);
	const double slide = speed * t_b - 0.5 * brake * t_b * t_b;
	const double left = (speed - brake * t_b) / speed;
	return committed_clearance(point_x, point_z, tau,
			o.x + o.vx * read + o.vx / speed * slide, o.z + o.vz * read + o.vz / speed * slide,
			o.vx * left, o.vz * left, accel * clamp01(1.0 - pace_share * left),
			o.stick, o.vmax, o.grip);
}

// AICarrySpace.reach_clearance, no chase (carried_from INF): every caller here.
double NativeCarrySpace::reach_clearance(double px, double pz, double time,
		const std::vector<Defender> &defs, bool valid, double maneuver_time, double carry_dx,
		double carry_dz, double carry_speed, double abort_below) const {
	if (!valid) {
		return safe_margin;
	}
	const double w = maneuver_time < 0.0 ? time : std::fmin(time, maneuver_time);
	const bool gated = carry_speed > 0.0;
	double worst = INF_D;
	for (const Defender &o : defs) {
		double accel = o.accel;
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
		double v_along_carry = 0.0;
		const double stride_accel = accel;
		if (gated) {
			v_along_carry = o.vx * carry_dx + o.vz * carry_dz;
			accel *= clamp01(1.0 - std::fmax(v_along_carry, 0.0) / carry_speed);
		}
		// _reach_clearance_one.
		const double tau = std::fmax(0.0, std::fmin(time, w) - reaction_s);
		const double coast = time - tau;
		double clear = committed_clearance(px, pz, tau, o.x + o.vx * coast,
				o.z + o.vz * coast, o.vx, o.vz, accel, o.stick, o.vmax, o.grip);
		if (v_along_carry > 0.0 && w < time) {
			clear = std::fmin(clear, stopped_clearance(px, pz, time, w, o, stride_accel,
					v_along_carry / carry_speed));
		}
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
double NativeCarrySpace::clearance_bound(double px, double pz,
		const std::vector<Defender> &defs) const {
	double bound = INF_D;
	for (const Defender &o : defs) {
		const double dx = px - o.bound_x;
		const double dz = pz - o.bound_z;
		bound = std::fmin(bound, std::sqrt(dx * dx + dz * dz) + o.bound_slack);
	}
	return bound;
}

// AICarrySpace.clearance_to_safety.
double NativeCarrySpace::clearance_to_safety(double clearance) const {
	return clamp01((clearance - (poke_contact - dwell_half_band)) / (2.0 * dwell_half_band));
}

// AICarrySpace.transit_clearance_to_safety.
double NativeCarrySpace::transit_clearance_to_safety(double clearance) const {
	return clamp01((clearance - transit_strip) / (transit_safe - transit_strip));
}

// AICarrySpace.carry_crossing_keep.
double NativeCarrySpace::crossing_keep(double fx, double fz, double tx, double tz,
		double arrival_time, const std::vector<Defender> &defs, bool valid) const {
	if (!valid || arrival_time <= 0.0) {
		return 1.0;
	}
	const double dx = tx - fx;
	const double dz = tz - fz;
	const double seg = std::sqrt(dx * dx + dz * dz);
	if (seg < 0.001) {
		return 1.0;
	}
	const double dirx = dx / seg;
	const double dirz = dz / seg;
	const double inv_t = 1.0 / arrival_time;
	const double pvx = dx * inv_t;
	const double pvz = dz * inv_t;
	const double pv_len = seg * inv_t;
	double worst_l = INF_D;
	double worst_r = INF_D;
	for (const Defender &o : defs) {
		const double span = o.blade_reach + poke_contact;
		const double r0x = fx - o.x;
		const double r0z = fz - o.z;
		const double rv_ub = pv_len + std::fabs(o.vx) + std::fabs(o.vz);
		const double far_need = span + protect_shift + rv_ub * arrival_time;
		if (r0x * r0x + r0z * r0z >= far_need * far_need) {
			continue;
		}
		const double rvx = pvx - o.vx;
		const double rvz = pvz - o.vz;
		const double rv_sq = rvx * rvx + rvz * rvz;
		if (rv_sq < 0.0001) {
			continue;
		}
		const double t_star = -(r0x * rvx + r0z * rvz) / rv_sq;
		if (t_star <= 0.0 || t_star >= arrival_time) {
			continue;
		}
		const double mx = r0x + rvx * t_star;
		const double mz = r0z + rvz * t_star;
		const double d_min = std::sqrt(mx * mx + mz * mz);
		const double margin = d_min - span;
		if (margin <= -(poke_contact + protect_shift)) {
			return 0.0;
		}
		if (dirx * (-mz) - dirz * (-mx) >= 0.0) {
			if (margin < worst_l) {
				worst_l = margin;
			}
		} else {
			if (margin < worst_r) {
				worst_r = margin;
			}
		}
	}
	if (worst_l == INF_D && worst_r == INF_D) {
		return 1.0;
	}
	double eff;
	if (worst_l < INF_D && worst_r < INF_D) {
		const double x = clampd((worst_r - worst_l) * 0.5, -protect_shift, protect_shift);
		eff = std::fmin(worst_l + x, worst_r - x);
	} else {
		eff = (worst_l < INF_D ? worst_l : worst_r) + protect_shift;
	}
	return clamp01((eff + poke_contact) / poke_contact);
}

double NativeCarrySpace::evade_safety(const Vector3 &carrier_pos, const Vector3 &carrier_vel,
		const Array &opponents, const Array &opponent_vels, double handle_reach,
		const PackedFloat64Array &caps) const {
	std::vector<Defender> defs;
	const bool valid = load(opponents, opponent_vels, caps, defs);
	const double proj_x = (double)carrier_pos.x + (double)carrier_vel.x * horizon_s;
	const double proj_z = (double)carrier_pos.z + (double)carrier_vel.z * horizon_s;
	const double cx = f32(proj_x);
	const double cz = f32(proj_z);
	double best_clear = reach_clearance(cx, cz, horizon_s, defs, valid, -1.0, 0.0, 0.0, 0.0,
			-INF_D);
	if (best_clear >= saturated_m) {
		return 1.0;
	}
	if (!valid) {
		// Nothing any sample reads can beat the empty defence's clearance.
		return clearance_to_safety(best_clear);
	}
	const double env = 0.5 * maneuver_accel * horizon_s * horizon_s + handle_reach;
	// _fill_clearance_bounds.
	const double tau = std::fmax(0.0, horizon_s - reaction_s);
	const double coast = horizon_s - tau;
	for (Defender &o : defs) {
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
			const double ub = board_gap(sx[k], sz[k]) < 0.0 ? -INF_D
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
				const double c = reach_clearance(sx[k], sz[k], horizon_s, defs, valid, -1.0,
						0.0, 0.0, 0.0, best_clear);
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

double NativeCarrySpace::carry_safety(const Vector3 &from, const Vector3 &to,
		double arrival_time, const Array &opponents, const Array &opponent_vels,
		const PackedFloat64Array &caps, bool apply_escape) const {
	std::vector<Defender> defs;
	const bool valid = load(opponents, opponent_vels, caps, defs);
	double carry_dx = 0.0;
	double carry_dz = 0.0;
	double carry_speed = 0.0;
	const double dx = (double)to.x - (double)from.x;
	const double dz = (double)to.z - (double)from.z;
	const double dist = std::sqrt(dx * dx + dz * dz);
	if (apply_escape && arrival_time > 0.0 && dist > 0.001) {
		carry_dx = f32(dx / dist);
		carry_dz = f32(dz / dist);
		carry_speed = dist / arrival_time;
	}
	const double lunge = std::fmin(arrival_time, lunge_window_s);
	if (dist < 0.001) {
		const double s_mid = clearance_to_safety(reach_clearance(from.x, from.z,
				arrival_time * 0.5, defs, valid, -1.0, 0.0, 0.0, 0.0, -INF_D));
		if (s_mid <= 0.0) {
			return 0.0;
		}
		return std::fmin(s_mid, clearance_to_safety(reach_clearance(from.x, from.z,
				arrival_time, defs, valid, lunge, 0.0, 0.0, 0.0, -INF_D)));
	}
	const double crossing = crossing_keep(from.x, from.z, to.x, to.z, arrival_time, defs,
			valid);
	if (crossing <= 0.0) {
		return 0.0;
	}
	const Vector3 mid = from.lerp(to, 0.5);
	const double t_mid = transit_clearance_to_safety(reach_clearance(mid.x, mid.z,
			arrival_time * 0.5, defs, valid, -1.0, carry_dx, carry_dz, carry_speed, -INF_D));
	if (t_mid <= 0.0) {
		return 0.0;
	}
	return std::fmin(crossing, std::fmin(t_mid, clearance_to_safety(reach_clearance(to.x,
			to.z, arrival_time, defs, valid, lunge, carry_dx, carry_dz, carry_speed,
			-INF_D))));
}

Vector3 NativeCarrySpace::carry_strip_point(const Vector3 &from, const Vector3 &to,
		double arrival_time, const Array &opponents, const Array &opponent_vels,
		const PackedFloat64Array &caps, bool apply_escape, bool covered_only) const {
	std::vector<Defender> defs;
	const bool valid = load(opponents, opponent_vels, caps, defs);
	double carry_dx = 0.0;
	double carry_dz = 0.0;
	double carry_speed = 0.0;
	if (apply_escape && arrival_time > 0.0) {
		const double ddx = (double)to.x - (double)from.x;
		const double ddz = (double)to.z - (double)from.z;
		const double ddist = std::sqrt(ddx * ddx + ddz * ddz);
		if (ddist > 0.001) {
			carry_dx = f32(ddx / ddist);
			carry_dz = f32(ddz / ddist);
			carry_speed = ddist / arrival_time;
		}
	}
	double cross_t = INF_D;
	Vector3 cross_pt = to;
	const double seg_x = (double)to.x - (double)from.x;
	const double seg_z = (double)to.z - (double)from.z;
	const double seg_len = std::sqrt(seg_x * seg_x + seg_z * seg_z);
	if (arrival_time > 0.0 && seg_len > 0.001 && opponent_vels.size() == opponents.size()) {
		const double dirx = seg_x / seg_len;
		const double dirz = seg_z / seg_len;
		const double inv_t = 1.0 / arrival_time;
		const double pvx = seg_x * inv_t;
		const double pvz = seg_z * inv_t;
		double worst_l = INF_D;
		double worst_r = INF_D;
		for (const Defender &o : defs) {
			const double rvx = pvx - o.vx;
			const double rvz = pvz - o.vz;
			const double rv_sq = rvx * rvx + rvz * rvz;
			if (rv_sq < 0.0001) {
				continue;
			}
			const double r0x = (double)from.x - o.x;
			const double r0z = (double)from.z - o.z;
			const double t_star = -(r0x * rvx + r0z * rvz) / rv_sq;
			if (t_star <= 0.0 || t_star >= arrival_time) {
				continue;
			}
			const double mx = r0x + rvx * t_star;
			const double mz = r0z + rvz * t_star;
			const double margin = std::sqrt(mx * mx + mz * mz) - (o.blade_reach + poke_contact);
			if (dirx * (-mz) - dirz * (-mx) >= 0.0) {
				worst_l = std::fmin(worst_l, margin);
			} else {
				worst_r = std::fmin(worst_r, margin);
			}
		}
		double shift = protect_shift;
		const bool both = worst_l < INF_D && worst_r < INF_D;
		if (both) {
			shift = clampd((worst_r - worst_l) * 0.5, -protect_shift, protect_shift);
		}
		if (std::fmin(worst_l, worst_r) <= -poke_contact + protect_shift) {
			for (const Defender &o : defs) {
				const double rvx2 = pvx - o.vx;
				const double rvz2 = pvz - o.vz;
				const double rv_sq2 = rvx2 * rvx2 + rvz2 * rvz2;
				if (rv_sq2 < 0.0001) {
					continue;
				}
				const double r0x2 = (double)from.x - o.x;
				const double r0z2 = (double)from.z - o.z;
				const double t_star2 = -(r0x2 * rvx2 + r0z2 * rvz2) / rv_sq2;
				if (t_star2 <= 0.0 || t_star2 >= arrival_time || t_star2 >= cross_t) {
					continue;
				}
				const double mx2 = r0x2 + rvx2 * t_star2;
				const double mz2 = r0z2 + rvz2 * t_star2;
				const double margin2 = std::sqrt(mx2 * mx2 + mz2 * mz2)
						- (o.blade_reach + poke_contact);
				const bool left = dirx * (-mz2) - dirz * (-mx2) >= 0.0;
				double eff = margin2 + protect_shift;
				if (both) {
					eff = margin2 + (left ? shift : -shift);
				}
				if (eff <= -poke_contact) {
					cross_t = t_star2;
					cross_pt = Vector3((real_t)((double)from.x + pvx * t_star2), 0.0f,
							(real_t)((double)from.z + pvz * t_star2));
				}
			}
		}
	}
	const Vector3 mid = from.lerp(to, 0.5);
	if (cross_t < arrival_time * 0.5) {
		return cross_pt;
	}
	const double c_mid = reach_clearance(mid.x, mid.z, arrival_time * 0.5, defs, valid, -1.0,
			carry_dx, carry_dz, carry_speed, -INF_D);
	if (c_mid < 0.0) {
		return mid;
	}
	if (cross_t < arrival_time) {
		return cross_pt;
	}
	const double c_end = reach_clearance(to.x, to.z, arrival_time, defs, valid,
			std::fmin(arrival_time, lunge_window_s), carry_dx, carry_dz, carry_speed, -INF_D);
	if (c_end < 0.0 || covered_only) {
		return to;
	}
	return c_mid <= c_end ? mid : to;
}

void NativeCarrySpace::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_kinematics", "maneuver_accel", "stick_reach",
								 "ref_speed", "reaction_s", "free_shed", "shed_decel",
								 "reversal_brake", "power_knee", "efficiency", "safe_margin"),
			&NativeCarrySpace::set_kinematics);
	ClassDB::bind_method(D_METHOD("set_rink", "inner_half_width", "inner_half_length",
								 "corner_radius", "corner_center_x", "corner_center_z"),
			&NativeCarrySpace::set_rink);
	ClassDB::bind_method(D_METHOD("set_sweep", "horizon_s", "angles", "rings", "saturated_m",
								 "poke_contact", "dwell_half_band"),
			&NativeCarrySpace::set_sweep);
	ClassDB::bind_method(D_METHOD("set_carry", "transit_strip", "transit_safe",
								 "lunge_window_s", "protect_shift", "league_blade_reach"),
			&NativeCarrySpace::set_carry);
	ClassDB::bind_method(D_METHOD("evade_safety", "carrier_pos", "carrier_vel", "opponents",
								 "opponent_vels", "handle_reach", "caps"),
			&NativeCarrySpace::evade_safety);
	ClassDB::bind_method(D_METHOD("carry_safety", "from", "to", "arrival_time", "opponents",
								 "opponent_vels", "caps", "apply_escape"),
			&NativeCarrySpace::carry_safety);
	ClassDB::bind_method(D_METHOD("carry_strip_point", "from", "to", "arrival_time",
								 "opponents", "opponent_vels", "caps", "apply_escape",
								 "covered_only"),
			&NativeCarrySpace::carry_strip_point);
}

} // namespace mitts
