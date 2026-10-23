extends GutTest

# The jersey's tail lifted out of the pants and the thigh guards
# (KeeperJerseyTail): a point is moved exactly when it lies inside the piece's
# surface stood off by a cloth's thickness along its own direction from the
# piece's axis, and it is moved onto that stood-off surface.

const SAMPLES: int = 4000


func test_a_point_is_moved_exactly_when_inside_the_stood_off_surface() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xf := Transform3D(Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.4), Vector3(0.1, 0.6, -0.05))
	var pieces: Array = [
		[KeeperGearMeshes.PANTS_SECTIONS, KeeperGear.half_extents(KeeperGear.Part.PANTS)],
		[KeeperGearMeshes.THIGH_SECTIONS, KeeperGear.half_extents(KeeperGear.Part.THIGH_G)],
	]
	for piece: Array in pieces:
		var sections: Array[Vector4] = piece[0]
		var h: Vector3 = piece[1]
		var moved: int = 0
		for i: int in SAMPLES:
			var local := Vector3(rng.randf_range(-1.3, 1.3) * h.x, rng.randf_range(-0.98, 0.98) * h.y,
					rng.randf_range(-1.3, 1.3) * h.z)
			var flat := Vector2(local.x, local.z)
			var sec: Vector3 = KeeperGearMeshes.section_at(sections, h, local.y)
			var surface: Vector3 = KeeperJerseyTail._on_section(sec, local.y, flat.normalized(),
					KeeperJerseyTail.CLOTH_M)
			var inside: bool = flat.length() < Vector2(surface.x, surface.z).length()
			var got: Vector3 = KeeperJerseyTail._clear_of(xf * local, xf, xf.affine_inverse(), sections, h)
			var want: Vector3 = xf * surface if inside else xf * local
			assert_almost_eq(got, want, Vector3.ONE * 1e-5, "%s" % local)
			if inside:
				moved += 1
		assert_between(moved, SAMPLES / 10, SAMPLES * 9 / 10, "both sides of the surface sampled")

