#include "native_blade_pass.h"

#include "native_blade_dangle.h"
#include "native_top_hand_ik.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace mitts {

namespace {

constexpr double TAU = 6.28318530717958647692;
// SkaterIKCoordinator._OPEN_ICE_MARGIN_M.
constexpr double OPEN_ICE_MARGIN_M = 0.05;
// ShotMechanics.WALL_PIN_MIN_ALONG_SPEED.
constexpr double WALL_PIN_MIN_ALONG_SPEED = 0.5;
// NetGeometry._AWAY_MARGIN.
constexpr double AWAY_MARGIN = 0.01;
// NetBladeCollision.SIDE_EPS_M / TELEPORT_M.
constexpr double SIDE_EPS_M = 0.001;
constexpr double TELEPORT_M = 1.0;
// The wall-pin release's power (SkaterIKCoordinator's literal).
constexpr double WALL_PIN_POWER = 3.0;

// GDScript's sign() and signf(): 0 at 0.
double sgn(double x) {
	return x > 0.0 ? 1.0 : (x < 0.0 ? -1.0 : 0.0);
}

// Godot's angle_difference.
double angle_difference(double from, double to) {
	const double difference = std::fmod(to - from, TAU);
	return std::fmod(2.0 * difference, TAU) - difference;
}

double lerpd(double from, double to, double weight) {
	return from + (to - from) * weight;
}

// Godot's smoothstep.
double smoothstepd(double from, double to, double x) {
	if (Math::is_equal_approx(from, to)) {
		if (from <= to) {
			return x <= from ? 0.0 : 1.0;
		}
		return x <= to ? 1.0 : 0.0;
	}
	const double t = CLAMP((x - from) / (to - from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// ── GoalieGearCollision ───────────────────────────────────────────────────────
// The GDScript (Scripts/domain/rules/goalie_gear_collision.gd) is the
// reference; this mirrors it statement for statement.

constexpr int GOALIE_FLOATS_PER_BOX = 15;
constexpr int GOALIE_SAMPLES = 5;
constexpr double GOALIE_SIDE_MIN = 0.3;
constexpr int GOALIE_ROUNDS = 2;

Vector3 goalie_axis(const float *box, int i) {
	return Vector3(box[i * 3], box[i * 3 + 1], box[i * 3 + 2]);
}

Vector3 goalie_origin(const float *box) {
	return Vector3(box[9], box[10], box[11]);
}

Vector3 goalie_half(const float *box) {
	return Vector3(box[12], box[13], box[14]);
}

Vector3 goalie_local(const Vector3 &p, const float *box) {
	return Vector3(p.dot(goalie_axis(box, 0)), p.dot(goalie_axis(box, 1)), p.dot(goalie_axis(box, 2)));
}

double goalie_across(const Vector3 &axis) {
	return Vector2(axis.x, axis.z).length();
}

int goalie_entered(const Vector3 &lw, const Vector3 &ln, const Vector3 &e) {
	if (Math::abs((double)lw.x) < (double)e.x && Math::abs((double)lw.y) < (double)e.y
			&& Math::abs((double)lw.z) < (double)e.z) {
		return -1;
	}
	int face = -1;
	double last = -INFINITY;
	for (int i = 0; i < 3; i++) {
		const double d = (double)ln[i] - (double)lw[i];
		if (Math::abs((double)lw[i]) < (double)e[i] || Math::abs(d) < 1e-9) {
			continue;
		}
		const double t = (sgn(lw[i]) * (double)e[i] - (double)lw[i]) / d;
		if (t > last) {
			last = t;
			face = i;
		}
	}
	return face;
}

int goalie_nearest_side(const Vector3 &ln, const Vector3 &e, const float *box) {
	int face = -1;
	double least = INFINITY;
	for (int i = 0; i < 3; i++) {
		const double across = goalie_across(goalie_axis(box, i));
		if (across < GOALIE_SIDE_MIN) {
			continue;
		}
		const double go = ((double)e[i] - Math::abs((double)ln[i])) / across;
		if (go < least) {
			least = go;
			face = i;
		}
	}
	return face;
}

Vector3 goalie_point_out(const Vector3 &was, const Vector3 &now, double radius, const float *box) {
	const Vector3 o = goalie_origin(box);
	const Vector3 e = goalie_half(box) + Vector3(1, 1, 1) * radius;
	const Vector3 ln = goalie_local(now - o, box);
	if (Math::abs((double)ln.x) >= (double)e.x || Math::abs((double)ln.y) >= (double)e.y
			|| Math::abs((double)ln.z) >= (double)e.z) {
		return Vector3();
	}
	const Vector3 lw = goalie_local(was - o, box);
	int face = goalie_entered(lw, ln, e);
	double side = 0.0;
	if (face >= 0 && goalie_across(goalie_axis(box, face)) >= GOALIE_SIDE_MIN) {
		side = sgn(lw[face]);
	} else {
		face = goalie_nearest_side(ln, e, box);
		if (face < 0) {
			return Vector3();
		}
		side = (double)ln[face] != 0.0 ? sgn(ln[face]) : 1.0;
	}
	const Vector3 axis = goalie_axis(box, face);
	const Vector3 flat(axis.x, 0.0, axis.z);
	const double across = flat.length();
	return flat / across * side * ((double)e[face] - side * (double)ln[face]) / across;
}

double goalie_out_along(const Vector3 &at, const Vector3 &way, double radius, const float *box) {
	const Vector3 o = goalie_origin(box);
	const Vector3 e = goalie_half(box) + Vector3(1, 1, 1) * radius;
	const Vector3 ln = goalie_local(at - o, box);
	if (Math::abs((double)ln.x) >= (double)e.x || Math::abs((double)ln.y) >= (double)e.y
			|| Math::abs((double)ln.z) >= (double)e.z) {
		return 0.0;
	}
	const Vector3 wl = goalie_local(way, box);
	double out = INFINITY;
	for (int i = 0; i < 3; i++) {
		if (Math::abs((double)wl[i]) < 1e-6) {
			continue;
		}
		out = MIN(out, (sgn(wl[i]) * (double)e[i] - (double)ln[i]) / (double)wl[i]);
	}
	return out != INFINITY ? out : 0.0;
}

Vector3 goalie_blade_out(const Vector3 &heel, const Vector3 &toe, const Vector3 &moved, double half_thickness,
		const float *box) {
	Vector3 lead;
	double nearest = INFINITY;
	for (int k = 0; k < GOALIE_SAMPLES; k++) {
		const double f = (double)k / (double)(GOALIE_SAMPLES - 1);
		const Vector3 now = heel.lerp(toe, f);
		const Vector3 push = goalie_point_out(now - moved, now, half_thickness, box);
		if (push != Vector3() && Math::abs(f - 0.5) < nearest) {
			nearest = Math::abs(f - 0.5);
			lead = push;
		}
	}
	if (lead == Vector3()) {
		return Vector3();
	}
	const Vector3 way = lead.normalized();
	double far = 0.0;
	for (int k = 0; k < GOALIE_SAMPLES; k++) {
		far = MAX(far, goalie_out_along(heel.lerp(toe, (double)k / (double)(GOALIE_SAMPLES - 1)), way,
				half_thickness, box));
	}
	return way * far;
}

Vector3 goalie_blade_resolve(const Vector3 &prev_mid, const Vector3 &heel, const Vector3 &toe,
		double half_thickness, const PackedFloat32Array &boxes) {
	const int count = boxes.size() / GOALIE_FLOATS_PER_BOX;
	const float *data = boxes.ptr();
	const Vector3 moved = (heel + toe) * 0.5 - prev_mid;
	const double reach = (double)heel.distance_to(toe) * 0.5 + (double)moved.length() + half_thickness;
	Vector3 offset;
	for (int round = 0; round < GOALIE_ROUNDS; round++) {
		Vector3 best;
		for (int b = 0; b < count; b++) {
			const float *box = data + b * GOALIE_FLOATS_PER_BOX;
			const Vector3 mid = (heel + toe) * 0.5 + offset;
			if ((double)mid.distance_to(goalie_origin(box)) > (double)goalie_half(box).length() + reach) {
				continue;
			}
			const Vector3 push = goalie_blade_out(heel + offset, toe + offset, moved, half_thickness, box);
			if (push.length_squared() > best.length_squared()) {
				best = push;
			}
		}
		if (best == Vector3()) {
			break;
		}
		offset += best;
	}
	return offset;
}

double read(const Dictionary &d, const char *key, bool &ok) {
	if (!d.has(key)) {
		ok = false;
		return 0.0;
	}
	return (double)d[key];
}

} // namespace

// ── Setup ──────────────────────────────────────────────────────────────────────

void NativeBladePass::bind(const Ref<RefCounted> &p_top, const Ref<RefCounted> &p_dangle) {
	top = p_top;
	dangle = p_dangle;
}

void NativeBladePass::set_rink(double p_inner_half_width, double p_inner_half_length,
		double p_inner_corner_radius, double p_corner_center_x, double p_corner_center_z) {
	inner_half_width = p_inner_half_width;
	inner_half_length = p_inner_half_length;
	inner_corner_radius = p_inner_corner_radius;
	corner_center_x = p_corner_center_x;
	corner_center_z = p_corner_center_z;
}

void NativeBladePass::set_net(double p_goal_line_z, double p_net_half_width, double p_net_post_radius,
		double p_net_depth, double p_net_top_depth, double p_net_height,
		double p_net_back_half_width, double p_net_crown_half_width,
		double p_net_mouth_corner_radius, double p_net_mesh_give) {
	goal_line_z = p_goal_line_z;
	net_half_width = p_net_half_width;
	net_post_radius = p_net_post_radius;
	net_depth = p_net_depth;
	net_top_depth = p_net_top_depth;
	net_height = p_net_height;
	net_back_half_width = p_net_back_half_width;
	net_crown_half_width = p_net_crown_half_width;
	net_mouth_corner_radius = p_net_mouth_corner_radius;
	net_mesh_give = p_net_mesh_give;
	back_slope = (net_top_depth - net_depth) / net_height;
}

bool NativeBladePass::configure(const Dictionary &t) {
	bool ok = true;
	hand_rest_y = read(t, "hand_rest_y", ok);
	hand_y_max = read(t, "hand_y_max", ok);
	faceoff_center_hand_rise = read(t, "faceoff_center_hand_rise", ok);
	faceoff_center_lean_deg = read(t, "faceoff_center_lean_deg", ok);
	stick_length = read(t, "stick_length", ok);
	rom_forward_reach_max = read(t, "rom_forward_reach_max", ok);
	net_blade_half_thickness = read(t, "net_blade_half_thickness", ok);
	blade_height = read(t, "blade_height", ok);
	blade_lift_height = read(t, "blade_lift_height", ok);
	hit_commit_blade_lift_m = read(t, "hit_commit_blade_lift_m", ok);
	bh_release_angle_deg = read(t, "bh_release_angle_deg", ok);
	reach_purpose_lookahead_s = read(t, "reach_purpose_lookahead_s", ok);
	reach_purpose_near_m = read(t, "reach_purpose_near_m", ok);
	reach_purpose_far_m = read(t, "reach_purpose_far_m", ok);
	hit_commit_hand_local_x = read(t, "hit_commit_hand_local_x", ok);
	hit_commit_hand_local_y = read(t, "hit_commit_hand_local_y", ok);
	hit_commit_hand_local_z = read(t, "hit_commit_hand_local_z", ok);
	hit_commit_blade_bearing_x = read(t, "hit_commit_blade_bearing_x", ok);
	hit_commit_blade_bearing_z = read(t, "hit_commit_blade_bearing_z", ok);
	hit_commit_blade_sweep = read(t, "hit_commit_blade_sweep", ok);
	bottom_hand_grip_fraction = read(t, "bottom_hand_grip_fraction", ok);
	faceoff_center_grip_fraction = read(t, "faceoff_center_grip_fraction", ok);
	twist_limit = read(t, "twist_limit", ok);
	const double forward_none = read(t, "top_hand_forward_none_m", ok);
	const double forward_full = read(t, "top_hand_forward_full_m", ok);
	const double fh_angle = read(t, "rom_forehand_angle_max", ok);
	const double bh_angle = read(t, "rom_backhand_angle_max", ok);
	const double fh_reach = read(t, "rom_forehand_reach_max", ok);
	const double bh_reach = read(t, "rom_backhand_reach_max", ok);
	if (ok && top.is_valid()) {
		top->set_rom_forehand_angle_max(fh_angle);
		top->set_rom_backhand_angle_max(bh_angle);
		top->set_rom_forward_reach_max(rom_forward_reach_max);
		top->set_rom_forehand_reach_max(fh_reach);
		top->set_rom_backhand_reach_max(bh_reach);
		top->set_hand_forward_none(forward_none);
		top->set_hand_forward_full(forward_full);
	}
	return ok;
}

// ── The pass ───────────────────────────────────────────────────────────────────

void NativeBladePass::run(const Transform3D &p_skater_xf, const Transform3D &p_ub_xf,
		const PackedFloat64Array &scalars, const PackedVector3Array &vectors,
		const PackedFloat32Array &goalies) {
	ERR_FAIL_COND(top.is_null() || dangle.is_null());
	ERR_FAIL_COND(scalars.size() < S_COUNT || vectors.size() < V_COUNT);
	for (int i = 0; i < S_COUNT; i++) {
		s[i] = scalars[i];
	}
	for (int i = 0; i < V_COUNT; i++) {
		v[i] = vectors[i];
	}
	goalie_boxes = goalies;
	skater_xf = p_skater_xf;
	ub_xf = p_ub_xf;
	ub_inv = ub_xf.affine_inverse();
	has_puck = s[S_HAS_PUCK] != 0.0;
	sign = s[S_LEFT_HANDED] != 0.0 ? -1.0 : 1.0;
	net_anchor = v[V_NET_ANCHOR];
	has_net_anchor = s[S_HAS_NET_ANCHOR] != 0.0;
	reach_purpose = s[S_REACH_PURPOSE];
	pending = false;
	skipped = false;
	stage = STAGE_DONE;
	wall_normal = Vector3();
	out_last_target = v[V_LAST_TARGET];

	// blade_y_local, the level tilt and the shoulder chain: fixed for the pass.
	double lift = s[S_LIFT_BLEND] * blade_lift_height;
	lift += s[S_COMMIT_BLEND] * hit_commit_blade_lift_m;
	blade_y_local = (blade_height + lift) - (double)ub_xf.origin.y;
	const Vector3 rot = v[V_UB_ROTATION];
	tilt = Basis::from_euler(Vector3(rot.x, 0.0, rot.z));
	top->set_hand_forward(s[S_HAND_FORWARD]);
	trunk_shoulder = shoulder_in_frame(v[V_SHOULDER]);
	place_arm_shoulder();
	bottom_trunk_shoulder = shoulder_in_frame(v[V_BOTTOM_SHOULDER]);

	// 1. The reach target.
	Vector3 mouse_world = v[V_TARGET];
	mouse_world.y = 0.0;
	Vector3 skater_pos = skater_xf.origin;
	skater_pos.y = 0.0;
	const bool hold_seat = s[S_HOLD_SEAT] != 0.0;
	const bool hold_blade = s[S_HOLD_BLADE] != 0.0;
	Vector3 target_blade_world;
	if (hold_seat && !seat_held) {
		held_seat_local = skater_xf.affine_inverse().xform(out_last_target);
	}
	seat_held = hold_seat;
	if (hold_seat) {
		target_blade_world = skater_xf.xform(held_seat_local);
		target_blade_world.y = 0.0;
		out_last_target = target_blade_world;
	} else if (hold_blade) {
		target_blade_world = ub_xf.xform(v[V_BLADE_MARKER]);
		target_blade_world.y = 0.0;
		out_last_target = target_blade_world;
	} else {
		if (has_puck) {
			mouse_world = held_out(mouse_world);
		}
		Vector3 shoulder_world = ub_xf.xform(arm_shoulder);
		shoulder_world.y = 0.0;
		if ((double)(mouse_world - shoulder_world).length() < 0.01) {
			skipped = true;
			return;
		}
		const Vector3 mouse_local = ub_inv.xform(mouse_world);
		Vector2 target_xz = blade_target_for(Vector2(mouse_local.x, mouse_local.z));
		const double target_reach = board_reach_limit(target_xz, shoulder_world);
		reach_purpose = purpose(skater_pos);
		Vector3 r_hand;
		Vector3 r_blade;
		solve_top_hand(target_xz, target_reach, true, r_hand, r_blade);
		if (has_puck) {
			solve_top_hand(Vector2(r_blade.x, r_blade.z), target_reach, true, r_hand, r_blade);
		}
		target_blade_world = ub_xf.xform(r_blade);
		target_blade_world.y = 0.0;
		out_last_target = target_blade_world;
	}

	// 2. The speed cap, relative to the skater (NativeBladeDangle).
	out_smoothed = dangle->advance(target_blade_world, skater_pos, s[S_DELTA],
			s[S_WRISTER_AIM] != 0.0);

	// 3. The hand for the capped blade.
	const Vector3 capped_local = ub_inv.xform(out_smoothed);
	const Vector2 capped_xz(capped_local.x, capped_local.z);
	const double commit_t = s[S_COMMIT_BLEND];
	Vector3 blade;
	solve_top_hand(capped_xz, board_reach_limit(capped_xz, ub_xf.xform(arm_shoulder)), false,
			hand, blade);
	if (commit_t > 0.0) {
		commit_hand_pose(hand, blade, commit_t);
	}

	// The carry's transit hop over a face flip.
	if (has_puck && s[S_CARRY_TRANSIT_LIFT] > 0.0) {
		const double transit = s[S_TRANSIT_FACTOR];
		if (transit > 0.0001) {
			const double lift_world = transit * s[S_CARRY_TRANSIT_LIFT];
			const double cpcr = MAX(Math::cos((double)rot.x) * Math::cos((double)rot.z), 0.01);
			blade.y = (double)blade.y + lift_world / cpcr;
		}
	}

	// The boards, and the wall-pin release.
	intended_blade = blade;
	wall_clamped = clamp_blade_to_walls(blade);
	if (has_puck) {
		const double squeeze = (double)intended_blade.length() - (double)wall_clamped.length();
		if (squeeze > s[S_WALL_SQUEEZE_THRESHOLD]) {
			// ShotMechanics.wall_pin_release_direction.
			const Vector3 vel(v[V_VELOCITY].x, 0.0, v[V_VELOCITY].z);
			Vector3 n(wall_normal.x, 0.0, wall_normal.z);
			Vector3 dir;
			if (n.length_squared() < 0.0001) {
				dir = vel.length_squared() > 0.0001 ? vel.normalized() : Vector3();
			} else {
				n = n.normalized();
				const Vector3 tangent(-n.z, 0.0, n.x);
				const double along = vel.dot(tangent);
				if (Math::abs(along) < WALL_PIN_MIN_ALONG_SPEED) {
					dir = n;
				} else {
					dir = tangent * (real_t)sgn(along);
					const double bias = s[S_WALL_PIN_INWARD_BIAS];
					if (bias > 0.0) {
						dir += n * (real_t)bias;
					}
					dir = dir.normalized();
				}
			}
			if ((double)dir.length() > 0.0) {
				release(dir, WALL_PIN_POWER);
			} else {
				const Vector3 blade_world = ub_xf.xform(wall_clamped);
				Vector3 back = skater_xf.origin - blade_world;
				back.y = 0.0;
				if (back.length_squared() < 0.0001) {
					back = -skater_xf.basis.get_column(2);
				}
				release(back.normalized(), WALL_PIN_POWER);
			}
			stage = STAGE_AFTER_WALL_RELEASE;
			return;
		}
	}
	stage = STAGE_AFTER_WALL_RELEASE;
	continue_pass();
}

void NativeBladePass::resume(bool p_has_puck) {
	ERR_FAIL_COND(!pending);
	pending = false;
	has_puck = p_has_puck;
	// The GDScript reads the chest's fold live (chest_fold, on has_puck), so the
	// rest of a pass whose release took the puck rebuilds the hand from a
	// shoulder no longer folded over the stick.
	if (!has_puck && s[S_CHEST_FOLD] != 0.0) {
		s[S_CHEST_FOLD] = 0.0;
		place_arm_shoulder();
	}
	continue_pass();
}

// SkaterIKCoordinator.arm_shoulder: the trunk's shoulder, the centre's address
// fold, then the chest's over the stick.
void NativeBladePass::place_arm_shoulder() {
	const double fold = Math::deg_to_rad(faceoff_center_lean_deg) * s[S_ADDRESS];
	arm_shoulder = folded(fold < 0.001 ? trunk_shoulder
									   : Basis::from_euler(Vector3(-fold, 0.0, 0.0)).xform(trunk_shoulder));
}

void NativeBladePass::release(const Vector3 &dir, double power) {
	pending = true;
	pending_dir = dir;
	pending_power = power;
}

void NativeBladePass::continue_pass() {
	// The goalie (resolve_blade_against_goalies), a wall that never strips.
	heel_world = ub_xf.xform(wall_clamped);
	clamped_heel = heel_world + resolve_goalies(heel_world);
	finish();
}

void NativeBladePass::finish() {
	stage = STAGE_DONE;
	clamped_heel += resolve_net(clamped_heel);
	if (clamped_heel != heel_world) {
		wall_clamped = ub_inv.xform(clamped_heel);
	}
	// Rebuild the arm for a blade a clamp moved: the blade is authoritative.
	if (wall_clamped != intended_blade) {
		const Vector3 clamped_level = tilt.xform(wall_clamped);
		hand = tilt.transposed().xform(hand_for_clamped_blade(
				tilt.xform(arm_shoulder),
				Vector2(clamped_level.x, clamped_level.z),
				clamped_level.y,
				level_config(tilt.xform(trunk_shoulder).y, blade_y_local, INFINITY)));
		enforce_rigid_stick(arm_shoulder, hand, wall_clamped,
				ik_config(wall_clamped.y, INFINITY));
	}
	out_hand = hand;
	out_blade = wall_clamped;
}

// ── The body ───────────────────────────────────────────────────────────────────

// SkaterSpineRig.shoulder_in_frame, hips square to the facing.
Vector3 NativeBladePass::shoulder_in_frame(const Vector3 &marker) const {
	const double fold = s[S_TRUNK_FOLD];
	if (Math::abs(fold) < 0.00001) {
		return marker;
	}
	const Vector3 trunk = v[V_UB_ROTATION];
	const double twist = CLAMP(angle_difference(0.0, (double)trunk.y), -twist_limit, twist_limit);
	const Basis built = Basis(Vector3(0.0, 1.0, 0.0), (double)trunk.y - twist)
			* Basis(Vector3(1.0, 0.0, 0.0), fold)
			* Basis(Vector3(0.0, 1.0, 0.0), twist)
			* Basis::from_euler(Vector3((double)trunk.x - fold, 0.0, trunk.z));
	return Basis::from_euler(trunk).inverse().xform(built.xform(marker));
}

double NativeBladePass::address_hand_ceiling() const {
	const double address = s[S_ADDRESS];
	if (address < 0.001) {
		return hand_y_max;
	}
	return lerpd(hand_y_max, hand_rest_y + faceoff_center_hand_rise, address);
}

NativeBladePass::Cfg NativeBladePass::ik_config(double p_blade_y, double max_reach) const {
	Cfg cfg;
	cfg.blade_y = p_blade_y;
	cfg.hand_rest_y = hand_rest_y;
	cfg.max_blade_reach = max_reach;
	cfg.stick_length = stick_length - s[S_GRIP_CHOKE];
	cfg.hand_y_max = address_hand_ceiling();
	return cfg;
}

NativeBladePass::Cfg NativeBladePass::level_config(double hang_y, double p_blade_y, double max_reach) const {
	Cfg cfg = ik_config(p_blade_y, max_reach);
	const double marker_y = v[V_SHOULDER].y;
	cfg.hand_rest_y = hang_y - (marker_y - hand_rest_y);
	cfg.hand_y_max = hang_y - (marker_y - cfg.hand_y_max);
	return cfg;
}

double NativeBladePass::lean_corrected_y(double x, double z) const {
	const double pitch = v[V_UB_ROTATION].x;
	const double roll = v[V_UB_ROTATION].z;
	double cp = Math::cos(pitch);
	double cr = Math::cos(roll);
	if (cp < 0.001) {
		cp = 0.001;
	}
	if (cr < 0.001) {
		cr = 0.001;
	}
	const double numerator = blade_y_local + z * Math::sin(pitch) - x * Math::sin(roll) * cp;
	return numerator / (cp * cr);
}

// SkaterIKCoordinator._blade_target_for.
Vector2 NativeBladePass::blade_target_for(const Vector2 &cursor_xz) const {
	const Vector2 to_target = cursor_xz - Vector2(v[V_SHOULDER].x, v[V_SHOULDER].z);
	if ((double)to_target.length() <= 0.001) {
		return cursor_xz;
	}
	const Vector2 stick_dir = to_target.normalized();
	Vector2 target = cursor_xz - stick_dir * (real_t)(s[S_BLADE_LENGTH] * 0.5);
	if (has_puck) {
		target += Vector2(-stick_dir.y, stick_dir.x) * (real_t)s[S_FOREHAND_FACTOR]
				* (real_t)s[S_CARRY_BLADE_OFFSET];
	}
	return target;
}

// SkaterIKCoordinator._held_out through CarryPostureRules.held_out: a carrier's
// cursor no closer than the floor off his centre, across the ice in the
// facing's frame.
Vector3 NativeBladePass::held_out(const Vector3 &cursor_world) const {
	const Vector3 local = skater_xf.affine_inverse().xform(cursor_world);
	const double min_out = s[S_CARRY_FLOOR];
	Vector2 held(local.x, local.z);
	const double out = held.length();
	if (out < min_out) {
		held = out < 0.001 ? Vector2(0.0, -min_out) : held * (real_t)(min_out / out);
	}
	Vector3 world = skater_xf.xform(Vector3(held.x, local.y, held.y));
	world.y = 0.0;
	return world;
}

// CarryPostureRules.folded_shoulder by the chest's fold over the stick.
Vector3 NativeBladePass::folded(const Vector3 &marker) const {
	const double fold = s[S_CHEST_FOLD];
	if (fold < 0.00001) {
		return marker;
	}
	return Basis(Vector3(1.0, 0.0, 0.0), -fold).xform(marker);
}

// SkaterIKCoordinator._board_reach_limit.
double NativeBladePass::board_reach_limit(const Vector2 &target_xz, const Vector3 &shoulder_world) const {
	const Vector2 origin(shoulder_world.x, shoulder_world.z);
	const double clear = MIN(distance_to_rink_inner(origin),
			distance_to_near_net(origin, net_blade_half_thickness));
	if (clear > stick_length + rom_forward_reach_max + OPEN_ICE_MARGIN_M) {
		return INFINITY;
	}
	const Vector3 aim_local((double)target_xz.x - (double)arm_shoulder.x, 0.0,
			(double)target_xz.y - (double)arm_shoulder.z);
	if (aim_local.length_squared() < 0.000001) {
		return INFINITY;
	}
	const Vector3 aim_world = ub_xf.basis.xform(aim_local);
	const Vector2 dir(aim_world.x, aim_world.z);
	if (dir.length_squared() < 0.000001) {
		return INFINITY;
	}
	const Vector2 unit = dir.normalized();
	return MIN(ray_to_rink_inner(origin, unit),
			ray_to_net(origin, unit, blade_height, net_blade_half_thickness));
}

// SkaterIKCoordinator._reach_purpose through ReachPurposeRules.purpose.
double NativeBladePass::purpose(const Vector3 &skater_pos) const {
	if (s[S_HAS_PUCK_NODE] == 0.0 || has_puck) {
		return 1.0;
	}
	const Vector2 body(skater_pos.x, skater_pos.z);
	const Vector2 puck_xz(v[V_PUCK_POS].x, v[V_PUCK_POS].z);
	const Vector2 vel_xz(v[V_PUCK_VEL].x, v[V_PUCK_VEL].z);
	const Vector2 path = vel_xz * (real_t)reach_purpose_lookahead_s;
	double t = 0.0;
	const double len_sq = path.length_squared();
	if (len_sq > 1e-8) {
		t = CLAMP((double)(body - puck_xz).dot(path) / len_sq, 0.0, 1.0);
	}
	const double gap = (double)(puck_xz + path * (real_t)t - body).length() - s[S_PURPOSE_RIM];
	return 1.0 - smoothstepd(reach_purpose_near_m, reach_purpose_far_m, gap);
}

// SkaterIKCoordinator._carry_backhand_stop.
Vector2 NativeBladePass::carry_backhand_stop(const Vector2 &target_xz) const {
	const Vector3 on_ice = ub_xf.xform(Vector3(target_xz.x,
			lean_corrected_y(target_xz.x, target_xz.y), target_xz.y));
	const Basis body = skater_xf.basis;
	const Vector3 rel = body.inverse().xform(on_ice - skater_xf.origin);
	const double r = Vector2(rel.x, rel.z).length();
	const double limit = Math::deg_to_rad(bh_release_angle_deg);
	if (r < 0.01 || Math::atan2((double)rel.x, -(double)rel.z) * -sign <= limit) {
		return target_xz;
	}
	const double a = limit * -sign;
	const Vector3 stopped = ub_inv.xform(skater_xf.origin
			+ body.xform(Vector3(Math::sin(a) * r, rel.y, -Math::cos(a) * r)));
	return Vector2(stopped.x, stopped.z);
}

void NativeBladePass::apply_cfg(const Cfg &cfg) const {
	top->set_hand_rest_y(cfg.hand_rest_y);
	top->set_blade_y(cfg.blade_y);
	top->set_max_blade_reach(cfg.max_blade_reach);
	top->set_stick_length(cfg.stick_length);
	top->set_hand_y_max(cfg.hand_y_max);
}

// SkaterIKCoordinator._two_hand_reach.
double NativeBladePass::two_hand_reach(const Vector3 &shoulder, const Vector2 &target_xz, const Cfg &cfg) {
	const Vector3 bottom = tilt.xform(folded(bottom_trunk_shoulder));
	apply_cfg(cfg);
	const double grip = lerpd(bottom_hand_grip_fraction, faceoff_center_grip_fraction, s[S_ADDRESS]);
	return top->two_hand_reach(shoulder, target_xz, sign, bottom, grip, s[S_BOTTOM_REACH],
			s[S_GLOVE_SPACING]);
}

// SkaterIKCoordinator._rest_reach.
double NativeBladePass::rest_reach(const Vector3 &shoulder, const Vector2 &target_xz, const Cfg &cfg) {
	const double held = two_hand_reach(shoulder, target_xz, cfg);
	if (held == INFINITY) {
		return cfg.max_blade_reach;
	}
	top->solve(shoulder, target_xz, sign);
	const Vector3 arm_blade = top->get_blade();
	const double arm = Vector2(arm_blade.x - shoulder.x, arm_blade.z - shoulder.z).length();
	return lerpd(held, arm, reach_purpose);
}

// SkaterIKCoordinator._solve_top_hand.
void NativeBladePass::solve_top_hand(Vector2 desired_xz, double max_reach, bool limits,
		Vector3 &r_hand, Vector3 &r_blade) {
	if (limits && has_puck) {
		desired_xz = carry_backhand_stop(desired_xz);
	}
	const Vector3 shoulder = tilt.xform(arm_shoulder);
	const double hang_y = tilt.xform(trunk_shoulder).y;
	const Vector3 target = tilt.xform(Vector3(desired_xz.x,
			lean_corrected_y(desired_xz.x, desired_xz.y), desired_xz.y));
	Cfg cfg = level_config(hang_y, blade_y_local, max_reach);
	const Vector2 target_xz(target.x, target.z);
	if (limits && has_puck) {
		max_reach = MIN(max_reach, two_hand_reach(shoulder, target_xz, cfg));
		cfg.max_blade_reach = max_reach;
	} else if (limits && reach_purpose < 1.0) {
		max_reach = rest_reach(shoulder, target_xz, cfg);
		cfg.max_blade_reach = max_reach;
	}
	top->set_hand_rest_y(cfg.hand_rest_y);
	top->solve_on_ice(shoulder, target_xz, sign, cfg.blade_y, 0.0, 0.0, max_reach,
			cfg.stick_length, cfg.hand_y_max);
	const Basis untilt = tilt.transposed();
	r_hand = untilt.xform(top->get_hand());
	r_blade = untilt.xform(top->get_blade());
}

// SkaterIKCoordinator._commit_hand_pose.
void NativeBladePass::commit_hand_pose(Vector3 &r_hand, Vector3 &r_blade, double commit_t) const {
	const Vector3 posed_hand(hit_commit_hand_local_x * sign, hit_commit_hand_local_y,
			hit_commit_hand_local_z);
	const double stick = stick_length - s[S_GRIP_CHOKE];
	const double drop = (double)posed_hand.y - (double)r_blade.y;
	const double horiz = Math::sqrt(MAX(stick * stick - drop * drop, 0.0001));
	Vector2 bearing((hit_commit_blade_bearing_x - s[S_CHECK_LEAD] * hit_commit_blade_sweep) * sign,
			hit_commit_blade_bearing_z);
	if (bearing.length_squared() < 0.000001) {
		bearing = Vector2(0.0, -1.0);
	}
	bearing = bearing.normalized();
	const Vector3 posed_blade((double)posed_hand.x + (double)bearing.x * horiz, r_blade.y,
			(double)posed_hand.z + (double)bearing.y * horiz);
	r_hand = r_hand.lerp(posed_hand, commit_t);
	r_blade = r_blade.lerp(posed_blade, commit_t);
}

// Skater.clamp_blade_to_walls.
Vector3 NativeBladePass::clamp_blade_to_walls(const Vector3 &local_pos) {
	wall_normal = Vector3();
	const Vector3 heel = ub_xf.xform(local_pos);
	Vector3 forward = v[V_BLADE_FORWARD];
	forward.y = 0.0;
	const double forward_len_sq = forward.length_squared();
	const Vector2 heel_xz(heel.x, heel.z);
	Vector2 offset = clamp_to_rink_inner(heel_xz) - heel_xz;
	if (forward_len_sq > 0.0001) {
		forward = forward.normalized();
		const Vector3 toe = heel + forward * (real_t)s[S_BLADE_LENGTH];
		const Vector2 toe_xz(toe.x, toe.z);
		const Vector2 toe_offset = clamp_to_rink_inner(toe_xz) - toe_xz;
		if (toe_offset.length_squared() > offset.length_squared()) {
			offset = toe_offset;
		}
	}
	if (offset.length_squared() < 0.0001) {
		return local_pos;
	}
	wall_normal = Vector3(offset.x, 0.0, offset.y).normalized();
	return ub_inv.xform(Vector3(heel.x + offset.x, heel.y, heel.z + offset.y));
}

// SkaterIKCoordinator.resolve_blade_against_goalies.
Vector3 NativeBladePass::resolve_goalies(const Vector3 &heel) const {
	if (goalie_boxes.is_empty()) {
		return Vector3();
	}
	Vector3 along = heel - ub_xf.xform(hand);
	along.y = 0.0;
	const Vector3 toe = along.length_squared() > 0.000001
			? heel + along.normalized() * (real_t)s[S_BLADE_LENGTH]
			: heel;
	return goalie_blade_resolve(v[V_PREV_CONTACT], heel, toe, net_blade_half_thickness, goalie_boxes);
}

// SkaterIKCoordinator.resolve_blade_against_net: the correction, and the side
// anchor carried to the next.
Vector3 NativeBladePass::resolve_net(const Vector3 &heel) {
	const Vector3 prev = v[V_PREV_CONTACT];
	net_anchor = has_net_anchor ? side_anchor(net_anchor, prev) : prev;
	has_net_anchor = true;
	Vector3 offset;
	net_resolve(net_anchor, heel, blade_toe_for(heel), net_blade_half_thickness, net_mesh_give, offset);
	return offset;
}

// SkaterIKCoordinator._blade_toe_for.
Vector3 NativeBladePass::blade_toe_for(const Vector3 &heel) const {
	Vector3 forward = v[V_BLADE_FORWARD];
	forward.y = 0.0;
	if (forward.length_squared() < 0.000001) {
		return heel;
	}
	return heel + forward.normalized() * (real_t)s[S_BLADE_LENGTH];
}

// ── TopHandIK ──────────────────────────────────────────────────────────────────

double NativeBladePass::max_reach_for_angle(double angle_to_forehand) const {
	const double side = angle_to_forehand > 0.0 ? top->get_rom_forehand_reach_max()
												: top->get_rom_backhand_reach_max();
	const double forward = top->get_rom_forward_reach_max();
	const double c = Math::cos(angle_to_forehand);
	if (c <= 0.0) {
		return side;
	}
	const double sn = Math::sin(angle_to_forehand);
	const double denom = Math::sqrt(side * side * c * c + forward * forward * sn * sn);
	return denom > 0.000001 ? forward * side / denom : 0.0;
}

// TopHandIK.hand_for_clamped_blade.
Vector3 NativeBladePass::hand_for_clamped_blade(const Vector3 &shoulder, const Vector2 &blade_xz,
		double p_blade_y, const Cfg &cfg) const {
	const Vector2 shoulder_xz(shoulder.x, shoulder.z);
	const Vector2 from_shoulder = blade_xz - shoulder_xz;
	const double d = from_shoulder.length();
	const double rest_drop = cfg.hand_rest_y - p_blade_y;
	const double stick_horiz_at_rest = Math::sqrt(MAX(cfg.stick_length * cfg.stick_length - rest_drop * rest_drop, 0.0001));
	const Vector2 bearing = d > 0.0001 ? from_shoulder / (real_t)d : Vector2(0.0, -1.0);
	const double floor_m = top->forward_floor(d, NativeTopHandIK::to_forehand(bearing, sign));
	const double reach = floor_m + NativeTopHandIK::hand_reach(d - floor_m, stick_horiz_at_rest);
	if (reach <= floor_m) {
		const double span = d - floor_m;
		const double drop_sq = cfg.stick_length * cfg.stick_length - span * span;
		const double hand_y = MIN(p_blade_y + Math::sqrt(MAX(drop_sq, 0.0)), cfg.hand_y_max);
		const Vector2 close_xz = shoulder_xz + bearing * (real_t)floor_m;
		return Vector3(close_xz.x, hand_y, close_xz.y);
	}
	const Vector2 dir = from_shoulder / (real_t)d;
	const double angle_to_forehand = CLAMP(
			Math::atan2((double)dir.x, -(double)dir.y) * sign,
			-top->get_rom_backhand_angle_max(), top->get_rom_forehand_angle_max());
	const double held = MIN(reach, max_reach_for_angle(angle_to_forehand));
	const Vector2 hand_xz = shoulder_xz + dir * (real_t)held;
	// TopHandIK._hand_y_on_stick.
	const double horiz = d - reach;
	double hand_y = cfg.hand_rest_y;
	if (horiz < stick_horiz_at_rest) {
		hand_y = p_blade_y + Math::sqrt(MAX(cfg.stick_length * cfg.stick_length - horiz * horiz, 0.0));
	}
	return Vector3(hand_xz.x, MIN(hand_y, cfg.hand_y_max), hand_xz.y);
}

// TopHandIK.enforce_rigid_stick.
void NativeBladePass::enforce_rigid_stick(const Vector3 &shoulder, Vector3 &r_hand, Vector3 &r_blade,
		const Cfg &cfg) const {
	const Vector3 to_blade = r_blade - r_hand;
	const double span = to_blade.length();
	const double over = span - cfg.stick_length;
	if (over <= 0.0 || span < 0.000001) {
		return;
	}
	const Vector3 dir = to_blade / (real_t)span;
	const Vector2 shoulder_xz(shoulder.x, shoulder.z);
	const Vector2 hand_xz(r_hand.x, r_hand.z);
	const Vector2 dir_xz(dir.x, dir.z);
	const Vector2 arm_xz = hand_xz - shoulder_xz;
	// TopHandIK._arm_angle_to_forehand.
	const Vector2 blade_from_shoulder = Vector2(r_blade.x, r_blade.z) - shoulder_xz;
	const Vector2 bearing = arm_xz.length_squared() > 0.000001 ? arm_xz : blade_from_shoulder;
	const double arm_angle = bearing.length_squared() < 0.000001
			? 0.0
			: Math::atan2((double)bearing.x, -(double)bearing.y) * sign;
	const double reach_max = max_reach_for_angle(arm_angle);
	double slide = over;
	const double a = dir_xz.length_squared();
	if (a > 0.000001) {
		const double b = 2.0 * (double)arm_xz.dot(dir_xz);
		const double c = (double)arm_xz.length_squared() - reach_max * reach_max;
		const double disc = b * b - 4.0 * a * c;
		const double limit = disc > 0.0 ? (-b + Math::sqrt(disc)) / (2.0 * a) : 0.0;
		slide = CLAMP(MIN(slide, limit), 0.0, over);
	}
	if ((double)dir.y > 0.000001) {
		slide = MIN(slide, MAX((cfg.hand_y_max - (double)r_hand.y) / (double)dir.y, 0.0));
	}
	r_hand = r_hand + dir * (real_t)slide;
	r_blade = r_blade - dir * (real_t)(over - slide);
}

// ── GameRules: the rink ────────────────────────────────────────────────────────

Vector2 NativeBladePass::clamp_to_rink_inner(const Vector2 &xz) const {
	const double ax = Math::abs((double)xz.x);
	const double az = Math::abs((double)xz.y);
	if (ax > corner_center_x && az > corner_center_z) {
		const double dx = ax - corner_center_x;
		const double dz = az - corner_center_z;
		const double dist = Math::sqrt(dx * dx + dz * dz);
		if (dist > inner_corner_radius) {
			const double scale = inner_corner_radius / dist;
			return Vector2(sgn(xz.x) * (corner_center_x + dx * scale),
					sgn(xz.y) * (corner_center_z + dz * scale));
		}
	} else {
		if (ax > inner_half_width) {
			return Vector2(sgn(xz.x) * inner_half_width, xz.y);
		}
		if (az > inner_half_length) {
			return Vector2(xz.x, sgn(xz.y) * inner_half_length);
		}
	}
	return xz;
}

double NativeBladePass::distance_to_rink_inner(const Vector2 &xz) const {
	const double qx = Math::abs((double)xz.x) - corner_center_x;
	const double qz = Math::abs((double)xz.y) - corner_center_z;
	return inner_corner_radius - (double)Vector2(MAX(qx, 0.0), MAX(qz, 0.0)).length()
			- MIN(MAX(qx, qz), 0.0);
}

double NativeBladePass::ray_to_rink_inner(const Vector2 &origin, const Vector2 &dir) const {
	if (dir.length_squared() < 0.000001) {
		return INFINITY;
	}
	double t = INFINITY;
	if (Math::abs((double)dir.x) > 0.000001) {
		const double wall_x = dir.x > 0.0 ? inner_half_width : -inner_half_width;
		t = (wall_x - (double)origin.x) / (double)dir.x;
	}
	if (Math::abs((double)dir.y) > 0.000001) {
		const double wall_z = dir.y > 0.0 ? inner_half_length : -inner_half_length;
		t = MIN(t, (wall_z - (double)origin.y) / (double)dir.y);
	}
	if (std::isinf(t)) {
		return INFINITY;
	}
	const Vector2 hit = origin + dir * (real_t)t;
	if (Math::abs((double)hit.x) > corner_center_x && Math::abs((double)hit.y) > corner_center_z) {
		const Vector2 center(sgn(hit.x) * corner_center_x, sgn(hit.y) * corner_center_z);
		const Vector2 m = origin - center;
		const double b = m.dot(dir);
		const double c = (double)m.length_squared() - inner_corner_radius * inner_corner_radius;
		const double disc = b * b - c;
		if (disc > 0.0) {
			t = MIN(t, -b + Math::sqrt(disc));
		}
	}
	return MAX(t, 0.0);
}

// ── NetGeometry ────────────────────────────────────────────────────────────────

double NativeBladePass::back_depth_at_height(double y) const {
	const double t = CLAMP(y / net_height, 0.0, 1.0);
	return lerpd(net_depth, net_top_depth, t);
}

double NativeBladePass::back_plane_distance(const Vector3 &p) const {
	const double depth = Math::abs((double)p.z) - goal_line_z;
	return (depth - net_depth - back_slope * (double)p.y) / back_plane_norm();
}

Vector3 NativeBladePass::back_plane_normal(double end_sign) const {
	const double inv = 1.0 / back_plane_norm();
	return Vector3(0.0, -back_slope * inv, end_sign * inv);
}

bool NativeBladePass::interior_or_mouth(const Vector3 &p) const {
	if ((double)p.y > net_height) {
		return false;
	}
	const double az = Math::abs((double)p.z);
	if (az <= goal_line_z) {
		return Math::abs((double)p.x) <= net_half_width;
	}
	if (back_plane_distance(p) >= 0.0) {
		return false;
	}
	return Math::abs((double)p.x) < net_half_width;
}

Vector3 NativeBladePass::closest_point_on_bend(const Vector3 &p, double end_z) const {
	const double side = p.x >= 0.0 ? 1.0 : -1.0;
	const double cx = side * net_crown_half_width;
	const double cy = post_top_y();
	const double r = net_mouth_corner_radius;
	double u = MAX(((double)p.x - cx) * side, 0.0);
	double vv = MAX((double)p.y - cy, 0.0);
	if (u <= 0.0 && vv <= 0.0) {
		u = 1.0;
	}
	const double inv = r / Math::sqrt(u * u + vv * vv);
	return Vector3(cx + side * u * inv, cy + vv * inv, end_z);
}

double NativeBladePass::ray_to_solid_face(const Vector2 &origin, const Vector2 &dir, double y) const {
	if (dir.length_squared() < 0.000001) {
		return INFINITY;
	}
	const double sg = sgn(near_end_z(origin.y));
	const double u = (double)origin.y * sg;
	const double du = (double)dir.y * sg;
	const double hw = net_half_width;
	const double u_lo = goal_line_z;
	const double u_hi = goal_line_z + back_depth_at_height(y);
	double tx_lo = -INFINITY;
	double tx_hi = INFINITY;
	if (Math::abs((double)dir.x) < 0.000001) {
		if (Math::abs((double)origin.x) > hw) {
			return INFINITY;
		}
	} else {
		const double a = (-hw - (double)origin.x) / (double)dir.x;
		const double b = (hw - (double)origin.x) / (double)dir.x;
		tx_lo = MIN(a, b);
		tx_hi = MAX(a, b);
	}
	double tu_lo = -INFINITY;
	double tu_hi = INFINITY;
	if (Math::abs(du) < 0.000001) {
		if (u < u_lo || u > u_hi) {
			return INFINITY;
		}
	} else {
		const double a2 = (u_lo - u) / du;
		const double b2 = (u_hi - u) / du;
		tu_lo = MIN(a2, b2);
		tu_hi = MAX(a2, b2);
	}
	const double t_enter = MAX(tx_lo, tu_lo);
	const double t_exit = MIN(tx_hi, tu_hi);
	if (t_enter > t_exit || t_exit < 0.0 || t_enter < 0.0) {
		return INFINITY;
	}
	if (tu_lo >= tx_lo && du > 0.0) {
		const double entry_x = (double)origin.x + (double)dir.x * t_enter;
		if (Math::abs(entry_x) < hw - net_post_radius) {
			return INFINITY;
		}
	}
	return t_enter;
}

namespace {
double ray_to_pipe(const Vector2 &origin, const Vector2 &dir, const Vector2 &center, double r) {
	const Vector2 m = origin - center;
	const double b = m.dot(dir);
	const double c = (double)m.length_squared() - r * r;
	if (c < 0.0) {
		return 0.0;
	}
	const double disc = b * b - c;
	if (disc < 0.0) {
		return INFINITY;
	}
	const double t = -b - Math::sqrt(disc);
	return t >= 0.0 ? t : INFINITY;
}
} // namespace

double NativeBladePass::ray_to_post(const Vector2 &origin, const Vector2 &dir, double clearance) const {
	const double end_z = near_end_z(origin.y);
	const double r = net_post_radius + clearance;
	const double left = ray_to_pipe(origin, dir, Vector2(-net_half_width, end_z), r);
	if (left == 0.0) {
		return 0.0;
	}
	return MIN(left, ray_to_pipe(origin, dir, Vector2(net_half_width, end_z), r));
}

double NativeBladePass::distance_to_near_net(const Vector2 &origin, double clearance) const {
	const double sg = sgn(near_end_z(origin.y));
	const double r = net_post_radius + clearance;
	const double half_x = MAX(net_half_width, net_half_width + r);
	const double u_lo = goal_line_z - r;
	const double u_hi = goal_line_z + MAX(net_depth, net_top_depth);
	const double u = (double)origin.y * sg;
	return Vector2(MAX(Math::abs((double)origin.x) - half_x, 0.0),
			MAX(MAX(u_lo - u, u - u_hi), 0.0))
			.length();
}

double NativeBladePass::ray_to_net(const Vector2 &origin, const Vector2 &dir, double y, double clearance) const {
	const double sg = sgn(near_end_z(origin.y));
	if ((double)dir.y * sg <= 0.0 && (double)origin.y * sg < goal_line_z - net_post_radius - clearance - AWAY_MARGIN) {
		return INFINITY;
	}
	return MIN(ray_to_solid_face(origin, dir, y), ray_to_post(origin, dir, clearance));
}

Vector3 NativeBladePass::post_overlap_xz(const Vector2 &a, const Vector2 &b, double post_x,
		double end_z, double clearance) const {
	const Vector2 center(post_x, end_z);
	const Vector2 span = b - a;
	const double len_sq = span.length_squared();
	Vector2 closest = a;
	if (len_sq > 0.000001) {
		closest = a + span * (real_t)CLAMP((double)(center - a).dot(span) / len_sq, 0.0, 1.0);
	}
	const Vector2 offset = closest - center;
	const double d = offset.length();
	const double reach = net_post_radius + clearance;
	if (d >= reach) {
		return Vector3();
	}
	const Vector2 n = d < 0.000001 ? Vector2(1.0, 0.0) : offset / (real_t)d;
	return Vector3(reach - d, n.x, n.y);
}

// ── NetBladeCollision ──────────────────────────────────────────────────────────

bool NativeBladePass::net_resolve(const Vector3 &prev, const Vector3 &heel, const Vector3 &toe,
		double half_thickness, double mesh_give, Vector3 &r_offset) const {
	r_offset = Vector3();
	if ((double)heel.y > net_height && (double)toe.y > net_height) {
		return false;
	}
	const double end_z = near_end_z(heel.z);
	const double reach = net_depth + half_thickness + 1.0;
	if (Math::abs((double)heel.z - end_z) > reach && Math::abs((double)toe.z - end_z) > reach) {
		return false;
	}
	const bool interior = interior_or_mouth(prev);
	const double lateral = net_back_half_width + half_thickness + mesh_give;
	if (!interior && (MIN((double)heel.x, (double)toe.x) > lateral || MAX((double)heel.x, (double)toe.x) < -lateral)) {
		return false;
	}
	const Vector2 a(heel.x, heel.z);
	const Vector2 b(toe.x, toe.z);
	const double near_x = heel.x >= 0.0 ? net_half_width : -net_half_width;
	Vector3 post = post_overlap_xz(a, b, near_x, end_z, half_thickness);
	if (post.x <= 0.0) {
		post = post_overlap_xz(a, b, -near_x, end_z, half_thickness);
	}
	if (post.x > 0.0) {
		const Vector3 pipe_normal(post.y, 0.0, post.z);
		r_offset = pipe_normal * post.x;
		return true;
	}
	if (resolve_bend(heel, toe, end_z, half_thickness, r_offset)) {
		return true;
	}
	Vector3 offset;
	if ((double)heel.y <= net_height) {
		offset = twine_offset(prev, heel, interior, mesh_give, end_z);
	}
	if ((double)toe.y <= net_height) {
		const Vector3 toe_offset = twine_offset(prev, toe, interior, mesh_give, end_z);
		if (toe_offset.length_squared() > offset.length_squared()) {
			offset = toe_offset;
		}
	}
	if (offset == Vector3()) {
		return false;
	}
	r_offset = offset;
	return true;
}

Vector3 NativeBladePass::side_anchor(const Vector3 &anchor, const Vector3 &contact) const {
	if ((double)anchor.distance_squared_to(contact) > TELEPORT_M * TELEPORT_M
			|| (double)contact.y > net_height) {
		return contact;
	}
	return contact + twine_offset(anchor, contact, interior_or_mouth(anchor), -SIDE_EPS_M,
							 near_end_z(contact.z));
}

bool NativeBladePass::resolve_bend(const Vector3 &heel, const Vector3 &toe, double end_z,
		double half_thickness, Vector3 &r_offset) const {
	const double lo = post_top_y() - half_thickness;
	const double hi = net_height + half_thickness;
	if (((double)heel.y < lo && (double)toe.y < lo) || ((double)heel.y > hi && (double)toe.y > hi)) {
		return false;
	}
	const double side = ((double)heel.x + (double)toe.x) >= 0.0 ? 1.0 : -1.0;
	const Vector3 centre(side * net_crown_half_width, post_top_y(), end_z);
	const Vector3 span = toe - heel;
	const double len_sq = span.length_squared();
	Vector3 sample = heel;
	if (len_sq > 0.000001) {
		sample = heel + span * (real_t)CLAMP((double)(centre - heel).dot(span) / len_sq, 0.0, 1.0);
	}
	const Vector3 axis = closest_point_on_bend(sample, end_z);
	const Vector3 offset = sample - axis;
	const double d = offset.length();
	const double reach = net_post_radius + half_thickness;
	if (d >= reach || d < 0.000001) {
		return false;
	}
	const Vector3 pipe_normal = offset / (real_t)d;
	r_offset = pipe_normal * (real_t)(reach - d);
	return true;
}

Vector3 NativeBladePass::twine_offset(const Vector3 &prev, const Vector3 &point, bool interior,
		double mesh_give, double end_z) const {
	const double end_sign = sgn(end_z);
	const double give = mesh_give;
	if (interior) {
		const double az = Math::abs((double)point.z);
		if (az <= goal_line_z) {
			return Vector3();
		}
		Vector3 out;
		const double back_limit = goal_line_z + back_depth_at_height(point.y) + give;
		if (az > back_limit) {
			out.z = end_sign * back_limit - (double)point.z;
		}
		const double side_limit = net_half_width + give;
		if (Math::abs((double)point.x) > side_limit) {
			out.x = sgn(point.x) * side_limit - (double)point.x;
		}
		return out;
	}
	if (back_plane_distance(prev) >= 0.0 && Math::abs((double)point.x) <= net_half_width + give) {
		const double back_dist = back_plane_distance(point);
		if (back_dist < -give) {
			return back_plane_normal(end_sign) * (real_t)(-give - back_dist);
		}
		return Vector3();
	}
	const double surface = net_half_width;
	const double side_stop = surface - give;
	if (Math::abs((double)prev.x) >= surface && Math::abs((double)point.x) < side_stop
			&& Math::abs((double)point.z) > goal_line_z) {
		return Vector3(sgn(prev.x) * side_stop - (double)point.x, 0.0, 0.0);
	}
	return Vector3();
}

// ── Bindings ───────────────────────────────────────────────────────────────────

void NativeBladePass::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "top", "dangle"), &NativeBladePass::bind);
	ClassDB::bind_method(D_METHOD("set_rink", "inner_half_width", "inner_half_length",
								 "inner_corner_radius", "corner_center_x", "corner_center_z"),
			&NativeBladePass::set_rink);
	ClassDB::bind_method(D_METHOD("set_net", "goal_line_z", "net_half_width", "net_post_radius",
								 "net_depth", "net_top_depth", "net_height", "net_back_half_width",
								 "net_crown_half_width", "net_mouth_corner_radius", "net_mesh_give"),
			&NativeBladePass::set_net);
	ClassDB::bind_method(D_METHOD("configure", "tunables"), &NativeBladePass::configure);
	ClassDB::bind_method(D_METHOD("reset_seat"), &NativeBladePass::reset_seat);
	ClassDB::bind_method(D_METHOD("run", "skater_xf", "ub_xf", "scalars", "vectors", "goalies"),
			&NativeBladePass::run);
	ClassDB::bind_method(D_METHOD("resume", "has_puck"), &NativeBladePass::resume);
	ClassDB::bind_method(D_METHOD("get_pending"), &NativeBladePass::get_pending);
	ClassDB::bind_method(D_METHOD("get_pending_dir"), &NativeBladePass::get_pending_dir);
	ClassDB::bind_method(D_METHOD("get_pending_power"), &NativeBladePass::get_pending_power);
	ClassDB::bind_method(D_METHOD("get_skipped"), &NativeBladePass::get_skipped);
	ClassDB::bind_method(D_METHOD("get_hand"), &NativeBladePass::get_hand);
	ClassDB::bind_method(D_METHOD("get_blade"), &NativeBladePass::get_blade);
	ClassDB::bind_method(D_METHOD("get_last_target"), &NativeBladePass::get_last_target);
	ClassDB::bind_method(D_METHOD("get_smoothed_blade"), &NativeBladePass::get_smoothed_blade);
	ClassDB::bind_method(D_METHOD("get_reach_purpose"), &NativeBladePass::get_reach_purpose);
	ClassDB::bind_method(D_METHOD("get_wall_normal"), &NativeBladePass::get_wall_normal);
	ClassDB::bind_method(D_METHOD("get_net_anchor"), &NativeBladePass::get_net_anchor);
	ClassDB::bind_method(D_METHOD("get_has_net_anchor"), &NativeBladePass::get_has_net_anchor);
}

} // namespace mitts
