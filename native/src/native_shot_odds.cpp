#include "native_shot_odds.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cmath>

using namespace godot;

namespace mitts {

template <typename T, typename P>
static void copy_out(const P &packed, std::vector<T> &out) {
	out.resize(packed.size());
	for (int64_t i = 0; i < packed.size(); i++) {
		out[i] = (T)packed[i];
	}
}

// The engine's angle_difference (core/math/math_funcs.h), which GDScript calls.
static double angle_difference(double from, double to) {
	const double difference = std::fmod(to - from, Math_TAU);
	return std::fmod(2.0 * difference, Math_TAU) - difference;
}

void NativeShotOdds::set_grid(const PackedFloat64Array &p_spot_x,
		const PackedFloat64Array &p_spot_fwd, const PackedInt32Array &p_spot_first,
		const PackedInt32Array &p_spot_count, const PackedInt32Array &p_set_cell) {
	copy_out(p_spot_x, spot_x);
	copy_out(p_spot_fwd, spot_fwd);
	copy_out(p_spot_first, spot_first);
	copy_out(p_spot_count, spot_count);
	copy_out(p_set_cell, set_cell);
}

void NativeShotOdds::set_cells(const PackedFloat32Array &p_odds,
		const PackedByteArray &p_is_shot_sample, const PackedByteArray &p_is_feed,
		const PackedByteArray &p_one_timer, const PackedByteArray &p_stance,
		const PackedByteArray &p_in_seal_zone, const PackedFloat32Array &p_offset,
		const PackedFloat32Array &p_velocity, const PackedFloat32Array &p_depth,
		const PackedFloat32Array &p_square, const PackedFloat32Array &p_travel,
		const PackedFloat32Array &p_flight) {
	copy_out(p_odds, odds);
	copy_out(p_is_shot_sample, is_shot_sample);
	copy_out(p_is_feed, is_feed);
	copy_out(p_one_timer, one_timer);
	copy_out(p_stance, stance);
	copy_out(p_in_seal_zone, in_seal_zone);
	copy_out(p_offset, offset);
	copy_out(p_velocity, velocity);
	copy_out(p_depth, depth);
	copy_out(p_square, square);
	copy_out(p_travel, travel);
	copy_out(p_flight, flight);
	q_cells.resize(odds.size());
	q_weights.resize(odds.size());
}

void NativeShotOdds::set_bandwidths(double p_offset, double p_velocity, double p_depth,
		double p_square, double p_travel, double p_flight, double p_min_weight,
		int64_t p_post_seal_stance) {
	offset_bw = p_offset;
	velocity_bw = p_velocity;
	depth_bw = p_depth;
	square_bw = p_square;
	travel_bw = p_travel;
	flight_bw = p_flight;
	min_weight = p_min_weight;
	post_seal_stance = p_post_seal_stance;
}

// AIShotOdds._bracket.
int NativeShotOdds::bracket(const std::vector<double> &grid, double v) {
	for (int i = (int)grid.size() - 2; i >= 0; i--) {
		if (v >= grid[i]) {
			return i;
		}
	}
	return 0;
}

void NativeShotOdds::push(int cell, double w) {
	if (q_count >= (int64_t)q_cells.size()) {
		q_cells.resize(q_count + 1);
		q_weights.resize(q_count + 1);
	}
	q_cells[q_count] = cell;
	q_weights[q_count] = (float)w;
	q_count++;
}

// AIShotOdds._weigh_spot.
double NativeShotOdds::weigh_spot(int spot, double spot_weight, bool p_is_feed,
		bool p_one_timer, int64_t p_stance, double a, double b, double p_depth,
		double p_square, int64_t p_in_seal_zone) {
	const double ha = p_is_feed ? travel_bw : offset_bw;
	const double hb = p_is_feed ? flight_bw : velocity_bw;
	const bool has_depth = !std::isnan(p_depth);
	const bool has_square = !std::isnan(p_square);
	const int64_t first = q_count;
	double wsum = 0.0;
	int nearest = -1;
	double nearest_d2 = INFINITY;
	const int c0 = spot_first[spot];
	const int c1 = c0 + spot_count[spot];
	for (int c = c0; c < c1; c++) {
		double ca;
		double cb;
		if (p_is_feed) {
			if (is_feed[c] == 0 || (one_timer[c] == 1) != p_one_timer) {
				continue;
			}
			ca = travel[c];
			cb = flight[c];
		} else {
			if (is_shot_sample[c] == 0 || stance[c] != p_stance) {
				continue;
			}
			if (p_stance == post_seal_stance && in_seal_zone[c] != p_in_seal_zone) {
				continue;
			}
			ca = offset[c];
			cb = velocity[c];
		}
		const double da = (a - ca) / ha;
		const double db = (b - cb) / hb;
		double d2 = da * da + db * db;
		if (!p_is_feed) {
			if (has_depth) {
				const double dd = (p_depth - (double)depth[c]) / depth_bw;
				d2 += dd * dd;
			}
			if (has_square) {
				const double ds = angle_difference(square[c], p_square) / square_bw;
				d2 += ds * ds;
			}
		}
		const double w = std::exp(-0.5 * d2);
		push(c, w);
		wsum += w;
		if (d2 < nearest_d2) {
			nearest_d2 = d2;
			nearest = c;
		}
	}
	if (nearest < 0) {
		return 0.0;
	}
	if (wsum < min_weight) {
		q_count = first;
		push(nearest, spot_weight * min_weight);
		return spot_weight * min_weight;
	}
	const double share = spot_weight * MIN(wsum, 1.0);
	const double scale = share / wsum;
	for (int64_t j = first; j < q_count; j++) {
		q_weights[j] = (float)((double)q_weights[j] * scale);
	}
	return share;
}

// AIShotOdds._weigh, then ._weighted_odds.
double NativeShotOdds::weigh(double local_x, double local_y, bool p_is_feed, bool p_one_timer,
		int64_t p_stance, double a, double b, double p_depth, double p_square, bool set_query,
		int64_t p_in_seal_zone) {
	q_count = 0;
	const int nx = (int)spot_x.size();
	const int xi = bracket(spot_x, local_x);
	const int fi = bracket(spot_fwd, local_y);
	const double tx = CLAMP((local_x - spot_x[xi]) / (spot_x[xi + 1] - spot_x[xi]), 0.0, 1.0);
	const double tf = CLAMP((local_y - spot_fwd[fi]) / (spot_fwd[fi + 1] - spot_fwd[fi]),
			0.0, 1.0);
	double total = 0.0;
	for (int corner = 0; corner < 4; corner++) {
		const double w = ((corner & 1) ? tx : 1.0 - tx) * ((corner >> 1) ? tf : 1.0 - tf);
		if (w <= 0.0) {
			continue;
		}
		const int spot = (fi + (corner >> 1)) * nx + xi + (corner & 1);
		if (set_query) {
			if (set_cell[spot] >= 0) {
				push(set_cell[spot], w);
				total += w;
			}
		} else {
			total += weigh_spot(spot, w, p_is_feed, p_one_timer, p_stance, a, b, p_depth,
					p_square, p_in_seal_zone);
		}
	}
	if (total <= 0.0) {
		q_count = 0;
		return 0.0;
	}
	double v = 0.0;
	for (int64_t j = 0; j < q_count; j++) {
		const float normalised = (float)((double)q_weights[j] / total);
		q_weights[j] = normalised;
		v += (double)normalised * (double)odds[q_cells[j]];
	}
	return MIN(v, 1.0);
}

PackedInt32Array NativeShotOdds::get_cells() const {
	PackedInt32Array out;
	out.resize(q_count);
	int32_t *w = out.ptrw();
	for (int64_t j = 0; j < q_count; j++) {
		w[j] = q_cells[j];
	}
	return out;
}

PackedFloat32Array NativeShotOdds::get_weights() const {
	PackedFloat32Array out;
	out.resize(q_count);
	float *w = out.ptrw();
	for (int64_t j = 0; j < q_count; j++) {
		w[j] = q_weights[j];
	}
	return out;
}

void NativeShotOdds::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_grid", "spot_x", "spot_fwd", "spot_first", "spot_count",
								 "set_cell"),
			&NativeShotOdds::set_grid);
	ClassDB::bind_method(D_METHOD("set_cells", "odds", "is_shot_sample", "is_feed",
								 "one_timer", "stance", "in_seal_zone", "offset", "velocity",
								 "depth", "square", "travel", "flight"),
			&NativeShotOdds::set_cells);
	ClassDB::bind_method(D_METHOD("set_bandwidths", "offset", "velocity", "depth", "square",
								 "travel", "flight", "min_weight", "post_seal_stance"),
			&NativeShotOdds::set_bandwidths);
	ClassDB::bind_method(D_METHOD("weigh", "local_x", "local_y", "is_feed", "one_timer",
								 "stance", "a", "b", "depth", "square", "set_query",
								 "in_seal_zone"),
			&NativeShotOdds::weigh);
	ClassDB::bind_method(D_METHOD("get_count"), &NativeShotOdds::get_count);
	ClassDB::bind_method(D_METHOD("get_cells"), &NativeShotOdds::get_cells);
	ClassDB::bind_method(D_METHOD("get_weights"), &NativeShotOdds::get_weights);
}

} // namespace mitts
