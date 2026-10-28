#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <vector>

namespace mitts {

// C++ port of a garment's tail as cloth flaps, Scripts/actors/hem_flaps.gd
// (HemFlaps.step, _relax, _write_bones), and of the colliders it pushes out of:
// the skater's (Scripts/actors/skater_hem_colliders.gd: update, push_out) or
// the keeper's (Scripts/actors/keeper/keeper_tail_colliders.gd). The GDScript
// is the reference; the parity fuzz
// (tests/unit/rules/test_native_hem_flaps_parity.gd) keeps them identical.
//
// One call a frame, and like NativeArmRig it reads the bones it needs off the
// skeleton and writes the flap bones itself.
//
// Precision mirrors the reference: double scalars, real_t vectors and bases,
// and the per-column shares, the thighs' radii and the keeper's section tables
// held in single precision as their packed arrays and Vector4s hold them.
class NativeHemFlaps : public godot::RefCounted {
	GDCLASS(NativeHemFlaps, godot::RefCounted)

	static constexpr int STATIONS = 4;
	static constexpr int BEND = 2;
	static constexpr int HEM = 3;

	// A piece of the keeper's: rounded sections stacked up its box, the box its
	// bone's pose.
	struct SectionBox {
		int32_t bone = -1;
		godot::Vector3 h;
		std::vector<godot::Vector4> sections;
		godot::Transform3D xf;
		godot::Transform3D inv;
	};

	godot::ObjectID skeleton_id;
	int32_t bone_top = -1;
	int32_t bone_drape = -1;
	int32_t bone_columns = -1;

	int columns = 0;
	// Station-major: rest[station * columns + column], in the bones' rest frame.
	std::vector<godot::Vector3> rest;
	std::vector<float> hips_share;
	std::vector<float> tuck_share;
	double gravity = 9.8;
	double shape_hz = 1.6;
	double ring_stiffness = 0.35;
	double damping_per_s = 7.0;
	double margin = 0.012;
	double max_step = 1.0 / 30.0;
	godot::Vector3 authored_up = godot::Vector3(0, 1, 0);
	int iterations = 3;
	int colliding_iterations = 2;

	// The skater's colliders.
	bool skater = false;
	int32_t bone_pelvis = -1;
	int32_t bone_leg[2] = { -1, -1 };
	int32_t bone_thigh[2] = { -1, -1 };
	// (y, radius, rear sway) per pants station, top down, end to end.
	std::vector<double> pelvis_profile;
	double thigh_length = 0.26;
	double thigh_radius_m = 0.152;
	double pelvis_xs = 1.05;
	double pelvis_zs = 0.88;
	godot::Vector3 thigh_top[2];
	godot::Vector3 thigh_bottom[2];
	float thigh_radius[2] = { 0.0f, 0.0f };
	godot::Transform3D pelvis;
	godot::Transform3D pelvis_inv;

	// The keeper's colliders.
	std::vector<SectionBox> boxes;
	double section_order = 3.0;

	std::vector<godot::Vector3> bend;
	std::vector<godot::Vector3> hem;
	std::vector<godot::Vector3> bend_prev;
	std::vector<godot::Vector3> hem_prev;
	std::vector<godot::Vector3> anchor;
	double last_dt = 0.0;
	bool started = false;

	const godot::Vector3 &rest_at(int station, int column) const {
		return rest[station * columns + column];
	}
	godot::Vector3 rest_bend(int k, const godot::Basis &drape) const;
	godot::Vector3 rest_hem(int k, const godot::Basis &drape) const;
	godot::Vector3 closest_on_thigh(int i, const godot::Vector3 &p) const;
	// SkaterMeshBuilder.pelvis_ring, as the Vector2 it returns rounds it.
	void pelvis_ring(double y, float &r_radius, float &r_sway) const;
	// KeeperGearMeshes.section_at, as the Vector3 it returns rounds it.
	godot::Vector3 section_at(const SectionBox &box, double y) const;
	// KeeperTailColliders.push_out_of and on_section.
	godot::Vector3 push_out_of(const SectionBox &box, godot::Vector3 p) const;
	godot::Vector3 push_out(godot::Vector3 p) const;
	void relax(const godot::Basis &drape, bool collide);
	void start(const godot::Basis &drape);

protected:
	static void _bind_methods();

public:
	// `bones` is (top, drape, the first column bone): HemFlaps.bind's.
	void bind(godot::Object *p_skeleton, const godot::PackedInt32Array &p_bones);
	// `drape` is HemFlaps.rest station-major (seam points dropped);
	// `tunables` (gravity, shape_hz, ring_stiffness, damping_per_s, margin,
	// max_step, authored up x, y, z); `counts` (iterations, colliding
	// iterations). Restarts the
	// drape; the colliders are configured after it.
	void configure(const godot::PackedVector3Array &p_drape, const godot::PackedFloat32Array &p_hips,
			const godot::PackedFloat32Array &p_tuck, const godot::PackedFloat64Array &p_tunables,
			const godot::PackedInt32Array &p_counts);
	// The skater's: `bones` (pelvis, left leg, right leg, left thigh, right
	// thigh), SkaterMeshBuilder.pelvis_stations, and `dims` (thigh length,
	// thigh radius, pants x scale, pants z scale).
	void collide_skater(const godot::PackedInt32Array &p_bones, const godot::PackedFloat64Array &p_pelvis,
			const godot::PackedFloat64Array &p_dims);
	// The keeper's: a bone per piece, its half extents, its sections (t, half
	// width, front depth, back depth) end to end, how many each, and their
	// rounding's order.
	void collide_sections(const godot::PackedInt32Array &p_bones, const godot::PackedVector3Array &p_half_extents,
			const godot::PackedFloat64Array &p_sections, const godot::PackedInt32Array &p_counts,
			double p_order);
	void step(double p_delta, const godot::Vector3 &p_g, bool p_write);
	godot::PackedVector3Array get_points() const;
	godot::PackedVector3Array get_state() const;
	void set_state(const godot::PackedVector3Array &p_state, double p_last_dt);
};

} // namespace mitts
