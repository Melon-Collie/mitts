#include "native_carry_rollout.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace mitts {

// GDScript's sign() on a float.
static double signd(double x) {
	return x > 0.0 ? 1.0 : (x < 0.0 ? -1.0 : 0.0);
}

// The engine's smoothstep (core/math/math_funcs.h), which GDScript calls; the
// godot-cpp one differs when the edges coincide.
static double smoothstep(double from, double to, double s) {
	if (Math::is_equal_approx(from, to)) {
		if (from <= to) {
			return s <= from ? 0.0 : 1.0;
		}
		return s <= to ? 1.0 : 0.0;
	}
	const double x = CLAMP((s - from) / (to - from), 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

void NativeCarryRollout::set_geometry(double p_inner_half_width, double p_inner_half_length,
		double p_inner_corner_radius, double p_corner_center_x, double p_corner_center_z,
		double p_goal_line_z, double p_net_depth, double p_net_back_half_width) {
	inner_half_width = p_inner_half_width;
	inner_half_length = p_inner_half_length;
	inner_corner_radius = p_inner_corner_radius;
	corner_center_x = p_corner_center_x;
	corner_center_z = p_corner_center_z;
	goal_line_z = p_goal_line_z;
	net_depth = p_net_depth;
	net_back_half_width = p_net_back_half_width;
}

void NativeCarryRollout::set_moves(double p_soft_turn_rad, double p_hard_turn_rad,
		double p_tick_dt, int64_t p_ticks, int64_t p_samples_per_move) {
	soft_turn_rad = p_soft_turn_rad;
	hard_turn_rad = p_hard_turn_rad;
	tick_dt = p_tick_dt;
	ticks = p_ticks;
	samples_per_move = MAX(p_samples_per_move, (int64_t)1);
	end_pos.resize(MOVE_COUNT);
	end_vel.resize(MOVE_COUNT);
	end_facing.resize(MOVE_COUNT);
	samples.resize(MOVE_COUNT * samples_per_move);
}

String NativeCarryRollout::configure(Object *caps) {
	ERR_FAIL_NULL_V(caps, String("null caps"));
	String missing;
	const Variant movement = caps->get(StringName("movement"));
	if (movement.get_type() != Variant::OBJECT) {
		missing += "movement ";
	} else {
		missing += load_movement_tunables((Object *)movement, move_cfg);
	}
	const Variant facing_rules = caps->get(StringName("facing_rules"));
	if (facing_rules.get_type() != Variant::OBJECT) {
		missing += "facing_rules ";
	} else {
		Object *fr = (Object *)facing_rules;
#define X(name)                                                    \
	{                                                              \
		const Variant v = fr->get(StringName(#name));              \
		if (v.get_type() == Variant::NIL) {                        \
			missing += #name " ";                                  \
		} else {                                                   \
			facing_cfg.name = (double)v;                           \
		}                                                          \
	}
		MITTS_FACING_TUNABLES(X)
#undef X
	}
#define X(name)                                                    \
	{                                                              \
		const Variant v = caps->get(StringName(#name));            \
		if (v.get_type() == Variant::NIL) {                        \
			missing += #name " ";                                  \
		} else {                                                   \
			body.name = (double)v;                                 \
		}                                                          \
	}
	MITTS_ROLLOUT_BODY_TUNABLES(X)
#undef X
	return missing;
}

// GameRules.clamp_to_rink_inner.
Vector2 NativeCarryRollout::clamp_to_rink_inner(const Vector2 &world_xz, double margin) const {
	const double half_w = inner_half_width - margin;
	const double half_l = inner_half_length - margin;
	const double corner_r = inner_corner_radius - margin;
	const double ax = Math::abs((double)world_xz.x);
	const double az = Math::abs((double)world_xz.y);
	if (ax > corner_center_x && az > corner_center_z) {
		const double dx = ax - corner_center_x;
		const double dz = az - corner_center_z;
		const double dist = Math::sqrt(dx * dx + dz * dz);
		if (dist > corner_r) {
			const double scale = corner_r / dist;
			return Vector2((real_t)(signd(world_xz.x) * (corner_center_x + dx * scale)),
					(real_t)(signd(world_xz.y) * (corner_center_z + dz * scale)));
		}
	} else {
		if (ax > half_w) {
			return Vector2((real_t)(signd(world_xz.x) * half_w), world_xz.y);
		}
		if (az > half_l) {
			return Vector2(world_xz.x, (real_t)(signd(world_xz.y) * half_l));
		}
	}
	return world_xz;
}

// GameRules.push_out_of_net.
Vector2 NativeCarryRollout::push_out_of_net(const Vector2 &world_xz, double radius) const {
	const double az = Math::abs((double)world_xz.y);
	const double x = world_xz.x;
	const double end_sign = signd(world_xz.y);
	const double lo_z = goal_line_z;
	const double hi_z = goal_line_z + net_depth;
	if (az <= lo_z - radius || az >= hi_z + radius || Math::abs(x) >= net_back_half_width + radius) {
		return world_xz;
	}
	const Vector2 near((real_t)CLAMP(x, -net_back_half_width, net_back_half_width),
			(real_t)CLAMP(az, lo_z, hi_z));
	const Vector2 off = Vector2((real_t)x, (real_t)az) - near;
	if (off != Vector2()) {
		const double d = off.length();
		if (d >= radius) {
			return world_xz;
		}
		const Vector2 out = near + off * (real_t)(radius / d);
		return Vector2(out.x, (real_t)(end_sign * (double)out.y));
	}
	const double pen_front = az - lo_z + radius;
	const double pen_back = hi_z - az + radius;
	const double pen_left = x + net_back_half_width + radius;
	const double pen_right = net_back_half_width - x + radius;
	const double min_pen = MIN(MIN(pen_front, pen_back), MIN(pen_left, pen_right));
	if (min_pen == pen_front) {
		return Vector2((real_t)x, (real_t)(end_sign * (lo_z - radius)));
	}
	if (min_pen == pen_back) {
		return Vector2((real_t)x, (real_t)(end_sign * (hi_z + radius)));
	}
	if (min_pen == pen_left) {
		return Vector2((real_t)(-net_back_half_width - radius), world_xz.y);
	}
	return Vector2((real_t)(net_back_half_width + radius), world_xz.y);
}

// AICarryRollout._face over FacingRules.solve (never in stance) and
// BoardPlayRules.board_proximity / board_shield_facing.
Vector2 NativeCarryRollout::face(const Vector2 &f, const Vector2 &cur, const Vector3 &v,
		const Vector3 &p, bool braking, double step, bool shield) const {
	Vector2 target = cur;
	bool turning_to_cursor_behind = false;
	const Vector2 velocity(v.x, v.z);
	if (!braking) {
		const double speed = velocity.length();
		if (speed >= 0.001) {
			const Vector2 travel = velocity / (real_t)speed;
			const bool following = Math::abs((double)f.angle_to(travel))
					<= Math::abs((double)f.angle_to(cur));
			const double share = following
					? smoothstep(facing_cfg.hold_min_speed, facing_cfg.hold_full_speed, speed)
					: smoothstep(facing_cfg.engage_min_speed, facing_cfg.engage_full_speed, speed);
			if (share > 0.0) {
				const double cone = facing_cfg.cone_rad
						+ (following ? facing_cfg.cone_hysteresis_rad : -facing_cfg.cone_hysteresis_rad);
				if (Math::abs((double)travel.angle_to(cur)) > cone) {
					turning_to_cursor_behind = true;
				} else {
					target = cur.slerp(travel, (real_t)share);
				}
			}
		}
	}
	const bool behind = Math::abs((double)f.angle_to(cur)) >= body.reach_cone_half_angle;
	if (behind && !turning_to_cursor_behind) {
		return f;
	}
	if (shield) {
		Vector2 proximity;
		const double probe = body.board_shield_probe;
		if (probe > 0.0) {
			const Vector2 pos_xz(p.x, p.z);
			const Vector2 correction = clamp_to_rink_inner(pos_xz, probe) - pos_xz;
			const double depth = correction.length();
			if (depth >= 0.0001) {
				proximity = correction * (real_t)(CLAMP(depth / probe, 0.0, 1.0) / depth);
			}
		}
		const double closeness = proximity.length();
		const double max_turn = body.board_shield_max_rad;
		if (!(closeness < 0.0001 || max_turn <= 0.0 || target.length_squared() < 0.0001)) {
			const Vector2 inward = proximity / (real_t)closeness;
			if (target.dot(inward) < 0.0) {
				Vector2 along(-inward.y, inward.x);
				if (target.dot(along) < 0.0) {
					along = -along;
				}
				const double turn = target.angle_to(along);
				target = target.rotated((real_t)(CLAMP(turn, -max_turn, max_turn) * closeness))
								 .normalized();
			}
		}
	}
	if (behind) {
		return f.slerp(target, (real_t)MIN(step, 1.0));
	}
	return f.lerp(target, (real_t)step).normalized();
}

// AICarryRollout._roll.
void NativeCarryRollout::roll(int m, const Vector2 &stick, const Vector2 &cursor, bool braking,
		const Vector3 &pos, const Vector3 &vel, const Vector2 &facing, bool has_puck,
		int64_t step_ticks) {
	const double drag = braking ? body.facing_drag_speed_braking : body.facing_drag_speed;
	const double radius = body.body_radius;
	const double dt = tick_dt * (double)step_ticks;
	const double contain_x = inner_half_width - radius;
	const double shield_x = inner_half_width - body.board_shield_probe;
	const int64_t ticks_per_sample = ticks / samples_per_move;
	Vector3 p = pos;
	Vector3 v = vel;
	Vector2 f = facing;
	bool touched = false;
	for (int64_t i = step_ticks - 1; i < ticks; i += step_ticks) {
		v = movement_step(move_cfg, v, stick, Math::atan2((double)-f.x, (double)-f.y), has_puck,
				braking, dt, 0, move_cfg.thrust, 1.0);
		v.y = 0.0;
		const bool between_arcs = Math::abs((double)p.z) <= corner_center_z;
		f = face(f, cursor, v, p, braking, drag * dt,
				has_puck && !(between_arcs && Math::abs((double)p.x) <= shield_x));
		p += v * (real_t)dt;
		const bool on_sample = (i + 1) % ticks_per_sample == 0;
		if (Math::abs((double)p.z) <= corner_center_z && Math::abs((double)p.x) <= contain_x) {
			if (on_sample) {
				samples.set(m * samples_per_move + (i + 1) / ticks_per_sample - 1, p);
			}
			continue;
		}
		const Vector2 xz(p.x, p.z);
		const Vector2 held = push_out_of_net(clamp_to_rink_inner(xz, radius), radius);
		if (xz.distance_squared_to(held) > 1e-6) {
			const Vector2 out_dir = (held - xz).normalized();
			Vector2 vxz(v.x, v.z);
			const double into = vxz.dot(out_dir);
			if (into < 0.0) {
				vxz -= out_dir * (real_t)into;
				v.x = vxz.x;
				v.z = vxz.y;
			}
			p.x = held.x;
			p.z = held.y;
			touched = true;
		}
		if (on_sample) {
			samples.set(m * samples_per_move + (i + 1) / ticks_per_sample - 1, p);
		}
	}
	end_pos.set(m, p);
	end_vel.set(m, v);
	end_facing.set(m, f);
	if (touched) {
		touched_mask |= (int64_t)1 << m;
	}
}

// AICarryRollout.roll_all with _set_move.
void NativeCarryRollout::roll_all(const Vector3 &pos, const Vector3 &vel, const Vector2 &facing,
		const Vector2 &toward, bool has_puck, int64_t step_ticks) {
	touched_mask = 0;
	const int64_t st = MAX(step_ticks, (int64_t)1);
	for (int m = 0; m < MOVE_COUNT; m++) {
		Vector2 stick = toward;
		bool braking = false;
		switch (m) {
			case SOFT_LEFT:
				stick = toward.rotated((real_t)-soft_turn_rad);
				break;
			case SOFT_RIGHT:
				stick = toward.rotated((real_t)soft_turn_rad);
				break;
			case HARD_LEFT:
				stick = toward.rotated((real_t)-hard_turn_rad);
				break;
			case HARD_RIGHT:
				stick = toward.rotated((real_t)hard_turn_rad);
				break;
			case BRAKE:
				braking = true;
				break;
			case CUT_BACK:
				stick = -toward;
				break;
			default:
				break;
		}
		const Vector2 cursor = (m == BRAKE || m == CUT_BACK) ? toward : stick;
		roll(m, stick, cursor, braking, pos, vel, facing, has_puck, st);
	}
}

void NativeCarryRollout::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_geometry", "inner_half_width", "inner_half_length",
			"inner_corner_radius", "corner_center_x", "corner_center_z", "goal_line_z",
			"net_depth", "net_back_half_width"),
			&NativeCarryRollout::set_geometry);
	ClassDB::bind_method(D_METHOD("set_moves", "soft_turn_rad", "hard_turn_rad", "tick_dt",
			"ticks", "samples_per_move"),
			&NativeCarryRollout::set_moves);
	ClassDB::bind_method(D_METHOD("configure", "caps"), &NativeCarryRollout::configure);
	ClassDB::bind_method(D_METHOD("roll_all", "pos", "vel", "facing", "toward", "has_puck",
			"step_ticks"),
			&NativeCarryRollout::roll_all);
	ClassDB::bind_method(D_METHOD("get_end_pos"), &NativeCarryRollout::get_end_pos);
	ClassDB::bind_method(D_METHOD("get_end_vel"), &NativeCarryRollout::get_end_vel);
	ClassDB::bind_method(D_METHOD("get_end_facing"), &NativeCarryRollout::get_end_facing);
	ClassDB::bind_method(D_METHOD("get_samples"), &NativeCarryRollout::get_samples);
	ClassDB::bind_method(D_METHOD("get_touched_mask"), &NativeCarryRollout::get_touched_mask);
}

} // namespace mitts
