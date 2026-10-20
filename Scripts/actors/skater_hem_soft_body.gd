class_name SkaterHemSoftBody
extends SkaterHemSim

# The tail below the belt as a physics-server cloth: a SoftBody3D band — the
# tail's four lathe rings and a ring between each pair, one point per facet
# column — pinned along the belt ring to nodes that follow the belt points, and
# colliding with capsules on each thigh and across the pants (the numbers
# SkaterHemColliders uses), which sit on a layer of their own so nothing else in
# the game meets them. The torso surface's own tail is cut away
# (SkaterJerseyHem TAIL_CUT); the band wears the torso's paint.
#
# The physics server steps it on the physics tick, in world space, while the
# pins and colliders move with the render-rate rig: a prototype's compromise
# with the rig's clock rule, which a shipped version would have to settle.

const CLOTH_LAYER: int = 1 << 20

var total_mass_kg: float = 0.25
var linear_stiffness: float = 0.6
# The server damps world-space velocity, so at skating speed any damping reads
# as a wind the band trails in; kept to what steadies it.
var damping: float = 0.05
var precision: int = 12

var _upper_mesh: MeshInstance3D = null
var _body: SoftBody3D = null
var _pins: Array[Node3D] = []
# Per pinned point: its point index, and its column and row on the band.
var _pinned := PackedInt32Array()
# The server's point index of each band vertex.
var _point_of := PackedInt32Array()
var _shapes: Array[AnimatableBody3D] = []
var _paint: Material = null
var _rows: int = 0


func set_paint_source(upper_mesh: MeshInstance3D) -> void:
	_upper_mesh = upper_mesh


func _rested() -> void:
	if _body != null:
		_body.queue_free()
		_body = null
		for pin: Node3D in _pins:
			pin.queue_free()
		_pins.clear()


func update(_delta: float, _on_camera: bool) -> void:
	var torso: Transform3D = _torso()
	var tail: Transform3D = _tail()
	_colliders.update(_skeleton)
	if _body == null:
		_build(tail)
	var anchor: PackedVector3Array = anchors(torso, tail)
	for i: int in _pins.size():
		var column: int = _pinned[i] % columns
		var row: int = int(_pinned[i] / float(columns))
		_pins[i].position = anchor[column] + tail.basis * (_ring_point(row, column) - rest[0][column])
	_place_shapes()
	if _upper_mesh != null:
		var paint: Material = _upper_mesh.get_surface_override_material(
				SkaterMeshBuilder.UpperSurface.TORSO)
		if paint != _paint:
			_paint = paint
			_body.material_override = paint


func hem_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if _body == null:
		return out
	var to_skeleton: Transform3D = _skeleton.global_transform.affine_inverse()
	for v: int in range(columns, _point_of.size()):
		out.append(to_skeleton * _body.get_point_transform(_point_of[v]))
	return out


# Rows run from the belt down: each tail station, and the midpoint between it
# and the next.
func _ring_point(row: int, column: int) -> Vector3:
	var station: int = int(row * 0.5)
	if row % 2 == 0:
		return rest[station][column]
	return rest[station][column].lerp(rest[station + 1][column], 0.5)


func _build(tail: Transform3D) -> void:
	_rows = 2 * STATIONS - 1
	var top_y: float = SkaterMeshBuilder.torso_ring(0, GearModelRegistry.TUCK_NONE)[0].y
	var span: float = SkaterMeshBuilder.TORSO_SIDE_HEIGHT_M
	var loose: Array[PackedVector3Array] = []
	for station: int in STATIONS:
		loose.append(SkaterMeshBuilder.torso_ring(FIRST_STATION + station,
				GearModelRegistry.TUCK_NONE))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var logical := PackedVector3Array()
	for row: int in _rows:
		var station: int = int(row * 0.5)
		var y: float = loose[station][0].y if row % 2 == 0 \
				else lerpf(loose[station][0].y, loose[station + 1][0].y, 0.5)
		for k: int in columns:
			st.set_uv(Vector2(float(k) / float(columns), 0.5 * (top_y - y) / span))
			logical.append(tail * _ring_point(row, k))
			st.add_vertex(logical[logical.size() - 1])
	# Wound so the faces look out (Godot's front faces wind clockwise), which the
	# first face's normal decides.
	var p0: Vector3 = tail * _ring_point(0, 0)
	var outward: Vector3 = p0 - tail * Vector3(0.0, rest[0][0].y, 0.0)
	var n0: Vector3 = (tail * _ring_point(0, 1) - p0).cross(tail * _ring_point(1, 1) - p0)
	var flip: bool = n0.dot(outward) > 0.0
	for row: int in _rows - 1:
		for k: int in columns:
			var a: int = row * columns + k
			var b: int = row * columns + (k + 1) % columns
			var c: int = a + columns
			var d: int = b + columns
			for i: int in ([a, b, d, a, d, c] if not flip else [a, d, b, a, c, d]):
				st.add_index(i)
	st.generate_normals()
	_body = SoftBody3D.new()
	_body.name = "HemCloth"
	_body.top_level = true
	_body.mesh = st.commit()
	_body.collision_layer = 0
	_body.collision_mask = CLOTH_LAYER
	_body.total_mass = total_mass_kg
	_body.linear_stiffness = linear_stiffness
	_body.damping_coefficient = damping
	_body.simulation_precision = precision
	_body.material_override = _paint
	_body.transform = _skeleton.global_transform
	_skeleton.add_child(_body)
	# The server's points are the committed mesh's vertices, which generating the
	# normals re-indexed out of row order, so each band point is found by where
	# it is.
	var verts: PackedVector3Array = _body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_point_of.resize(logical.size())
	for v: int in logical.size():
		var best: int = 0
		for i: int in verts.size():
			if verts[i].distance_squared_to(logical[v]) < verts[best].distance_squared_to(logical[v]):
				best = i
		_point_of[v] = best
	# The belt row is pinned; a tucked column is pinned all the way down.
	_pinned.clear()
	for row: int in _rows:
		for k: int in columns:
			if row == 0 or tuck_share[k] >= 0.5:
				var pin := Node3D.new()
				_skeleton.add_child(pin)
				# A pinned point keeps the offset it has from its node when pinned,
				# so the node starts on the point.
				pin.position = logical[row * columns + k]
				_pins.append(pin)
				_pinned.append(row * columns + k)
	for i: int in _pins.size():
		_body.set_point_pinned(_point_of[_pinned[i]], true, _body.get_path_to(_pins[i]))
	if _shapes.is_empty():
		_build_shapes()


func _build_shapes() -> void:
	for i: int in 4:
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = CLOTH_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = CapsuleShape3D.new()
		# The default 4 cm margin fattens a thigh past the rest drape, which then
		# starts inside it and is flung out.
		shape.shape.margin = 0.001
		body.add_child(shape)
		_skeleton.add_child(body)
		_shapes.append(body)


# Thighs from SkaterHemColliders; the pants as two capsules lying across the
# hips, through the waistband and the seat, as wide and as deep as the lathe.
func _place_shapes() -> void:
	for side: int in 2:
		var a: Vector3 = _colliders.thigh_top[side]
		var b: Vector3 = _colliders.thigh_bottom[side]
		var r: float = _colliders.thigh_radius[side]
		_place(_shapes[side], (a + b) * 0.5, (b - a).normalized(), r, a.distance_to(b) + 2.0 * r)
	var pelvis: Transform3D = _colliders.pelvis
	var heights: Array[float] = [-0.02, -0.12]
	for i: int in 2:
		var ring: Vector2 = SkaterMeshBuilder.pelvis_ring(heights[i])
		var scale: float = pelvis.basis.x.length()
		_place(_shapes[2 + i], pelvis * Vector3(0.0, heights[i], ring.y),
				pelvis.basis.x.normalized(), ring.x * SkaterMeshBuilder.PELVIS_XZ_SCALE.y * scale,
				2.0 * ring.x * SkaterMeshBuilder.PELVIS_XZ_SCALE.x * scale)


func _place(body: AnimatableBody3D, centre: Vector3, axis: Vector3, radius: float,
		height: float) -> void:
	var capsule: CapsuleShape3D = (body.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	capsule.radius = radius
	capsule.height = maxf(height, 2.0 * radius)
	var side: Vector3 = axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT)
	var basis := Basis(side.normalized(), axis, side.normalized().cross(axis))
	body.transform = Transform3D(basis.orthonormalized(), centre)
