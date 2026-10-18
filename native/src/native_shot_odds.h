#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <vector>

namespace mitts {

// C++ port of the query half of Scripts/domain/ai/shot_odds.gd (AIShotOdds
// ._weigh, ._weigh_spot and ._weighted_odds): bilinear over the release-spot
// grid, a kernel over each spot's cells, the normalised weights and the odds
// they give. The GDScript builds the field and computes each query's inputs;
// it loads the per-cell arrays here once (set_grid, set_cells, set_bandwidths).
// The GDScript is the reference; tests/unit/ai/test_native_shot_odds_parity.gd
// fuzzes the two. Change them together or not at all.
//
// Weights are stored as float, as the GDScript's PackedFloat32Array rounds them,
// and every product is taken in double between the stores, so the two agree to
// the bit.
//
// One instance per field, on the AI worker alone: the matched cells are its state.
class NativeShotOdds : public godot::RefCounted {
	GDCLASS(NativeShotOdds, godot::RefCounted)

	// The field, copied out of the GDScript's packed arrays when it loads: reading
	// a packed array element by element costs an engine call each.
	std::vector<double> spot_x;
	std::vector<double> spot_fwd;
	std::vector<int32_t> spot_first;
	std::vector<int32_t> spot_count;
	std::vector<int32_t> set_cell;

	std::vector<float> odds;
	std::vector<uint8_t> is_shot_sample;
	std::vector<uint8_t> is_feed;
	std::vector<uint8_t> one_timer;
	std::vector<uint8_t> stance;
	std::vector<uint8_t> in_seal_zone;
	std::vector<float> offset;
	std::vector<float> velocity;
	std::vector<float> depth;
	std::vector<float> square;
	std::vector<float> travel;
	std::vector<float> flight;

	double offset_bw = 1.0;
	double velocity_bw = 1.0;
	double depth_bw = 1.0;
	double square_bw = 1.0;
	double travel_bw = 1.0;
	double flight_bw = 1.0;
	double min_weight = 0.0;
	int64_t post_seal_stance = -1;

	std::vector<int32_t> q_cells;
	std::vector<float> q_weights;
	int64_t q_count = 0;

	static int bracket(const std::vector<double> &grid, double v);
	double weigh_spot(int spot, double spot_weight, bool p_is_feed, bool p_one_timer,
			int64_t p_stance, double a, double b, double p_depth, double p_square,
			int64_t p_in_seal_zone);
	void push(int cell, double w);

protected:
	static void _bind_methods();

public:
	void set_grid(const godot::PackedFloat64Array &p_spot_x,
			const godot::PackedFloat64Array &p_spot_fwd,
			const godot::PackedInt32Array &p_spot_first,
			const godot::PackedInt32Array &p_spot_count,
			const godot::PackedInt32Array &p_set_cell);
	void set_cells(const godot::PackedFloat32Array &p_odds,
			const godot::PackedByteArray &p_is_shot_sample,
			const godot::PackedByteArray &p_is_feed,
			const godot::PackedByteArray &p_one_timer,
			const godot::PackedByteArray &p_stance,
			const godot::PackedByteArray &p_in_seal_zone,
			const godot::PackedFloat32Array &p_offset,
			const godot::PackedFloat32Array &p_velocity,
			const godot::PackedFloat32Array &p_depth,
			const godot::PackedFloat32Array &p_square,
			const godot::PackedFloat32Array &p_travel,
			const godot::PackedFloat32Array &p_flight);
	void set_bandwidths(double p_offset, double p_velocity, double p_depth, double p_square,
			double p_travel, double p_flight, double p_min_weight, int64_t p_post_seal_stance);

	// AIShotOdds._weigh then ._weighted_odds: fills the matched cells and their
	// normalised weights, and returns the odds they give (0 when nothing matches).
	double weigh(double local_x, double local_y, bool p_is_feed, bool p_one_timer,
			int64_t p_stance, double a, double b, double p_depth, double p_square,
			bool set_query, int64_t p_in_seal_zone);

	int64_t get_count() const { return q_count; }
	godot::PackedInt32Array get_cells() const;
	godot::PackedFloat32Array get_weights() const;
};

} // namespace mitts
