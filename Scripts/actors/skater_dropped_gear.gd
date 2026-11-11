class_name SkaterDroppedGear
extends RefCounted

# The stick and gloves a fighter drops (Skater.gloves_off), drawn on every
# machine and never on the wire. As the gloves come off, each piece is copied
# from where it is drawn — the stick's shaft, blade and knob as they are, each
# glove's fist and cuff off its bones — and falls, tumbling, to the ice, where
# it slides to a stop lying flat. When the gloves go back on (the fight is over)
# the pieces go. Nothing reads them: they are mesh, top-level and opted out of
# physics interpolation, stepped at render rate.

const GRAVITY_M_S2: float = 9.8
# How hard a landed piece slides to a stop, m/s².
const SLIDE_DECEL_M_S2: float = 3.0
# How fast a landed piece settles flat, per second.
const SETTLE_RATE: float = 10.0
# The share of the skater's own velocity a dropped piece leaves with.
const CARRY_SHARE: float = 0.6
# Gloves are shaken off, down and out to their own side, m/s; the stick is let go.
const GLOVE_TOSS_DOWN_M_S: float = 1.5
const GLOVE_TOSS_OUT_M_S: float = 0.8
const GLOVE_SPIN_RAD_S: float = 6.0
const STICK_TOPPLE_RAD_S: float = 2.5
# Height of each piece's root over the ice once flat, metres: the stick's root
# is its grip, on the shaft's line; a glove's is its fist's bone.
const STICK_REST_Y_M: float = 0.03
const GLOVE_REST_Y_M: float = 0.05


class Piece:
	var node: Node3D
	var velocity: Vector3
	var spin: Vector3          # axis × rad/s, world
	var rest_y: float
	var landed: bool = false


var _skater: Skater = null
var _pieces: Array[Piece] = []
var _down: bool = false


func setup(skater: Skater) -> void:
	_skater = skater


# Per drawn frame, after the rig is posed: drops the gear as the gloves come off,
# steps what is down, and takes it all away as they go back on.
func update(delta: float) -> void:
	var off: bool = _skater.gloves_off()
	if off and not _down:
		_drop()
	elif not off and _down:
		clear()
	_down = off
	if not _pieces.is_empty():
		for piece: Piece in _pieces:
			_step(piece, delta)


func clear() -> void:
	for piece: Piece in _pieces:
		if is_instance_valid(piece.node):
			piece.node.queue_free()
	_pieces.clear()


func piece_count() -> int:
	return _pieces.size()


func _drop() -> void:
	clear()
	var carried: Vector3 = _skater.velocity * CARRY_SHARE
	carried.y = 0.0
	_drop_stick(carried)
	for top: bool in [true, false]:
		_drop_glove(top, carried)


func _drop_stick(carried: Vector3) -> void:
	var hand: Vector3 = _skater.upper_body.global_transform * _skater.drawn_top_hand()
	var blade: Vector3 = _skater.upper_body.global_transform * _skater.drawn_blade().origin
	var shaft: Vector3 = blade - hand
	if shaft.length_squared() < 0.0001:
		return
	var root: Node3D = _new_root(Transform3D(
			Basis.looking_at(shaft.normalized(), SkaterArmPoses.up_for_look_at(shaft)), hand))
	for part: MeshInstance3D in [_skater.stick_mesh, _skater.stick_knob_mesh,
			_skater.blade_mesh_instance()]:
		if part != null:
			_copy_into(root, part)
	# Let go of, the stick falls over about the axis across its shaft.
	var across: Vector3 = Vector3.UP.cross(shaft).normalized()
	_add(root, carried, across * STICK_TOPPLE_RAD_S, STICK_REST_Y_M)


func _drop_glove(top: bool, carried: Vector3) -> void:
	var skeleton: Skeleton3D = _skater.body_skeleton()
	var mesh: ArrayMesh = SkaterRigidParts.glove_mesh(top, _skater.is_top_hand_right())
	if skeleton == null or mesh == null:
		return
	var fist_bone: int = SkaterMeshBuilder.UpperBone.TOP_HAND if top \
			else SkaterMeshBuilder.UpperBone.BOTTOM_HAND
	var cuff_bone: int = SkaterMeshBuilder.UpperBone.TOP_CUFF if top \
			else SkaterMeshBuilder.UpperBone.BOTTOM_CUFF
	var fist: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(fist_bone)
	var cuff: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(cuff_bone)
	var root: Node3D = _new_root(fist.orthonormalized())
	var inv: Transform3D = root.global_transform.affine_inverse()
	for part: Array in [[mesh.surface_get_arrays(0), fist], [mesh.surface_get_arrays(1), cuff]]:
		var arrays: Array = part[0]
		if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		var surface := ArrayMesh.new()
		surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = surface
		mi.material_override = _skater.body_material()
		mi.set_instance_shader_parameter(&"flat_from_position", 1.0)
		root.add_child(mi)
		mi.transform = inv * (part[1] as Transform3D)
	var side: Vector3 = (fist.origin - _skater.global_position)
	side.y = 0.0
	var out: Vector3 = side.normalized() if side.length_squared() > 0.0001 else Vector3.ZERO
	var toss: Vector3 = carried + out * GLOVE_TOSS_OUT_M_S + Vector3.DOWN * GLOVE_TOSS_DOWN_M_S
	var spin_axis: Vector3 = Vector3.UP.cross(out) if out != Vector3.ZERO else Vector3.RIGHT
	_add(root, toss, spin_axis * GLOVE_SPIN_RAD_S, GLOVE_REST_Y_M)


func _new_root(xform: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "DroppedGear"
	root.top_level = true
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_skater.add_child(root)
	root.global_transform = xform
	return root


# A copy of a live stick part, where it is drawn, with its own material: the
# live shaft's shader takes the hidden stick's uniforms every frame.
func _copy_into(root: Node3D, part: MeshInstance3D) -> void:
	var copy: MeshInstance3D = part.duplicate() as MeshInstance3D
	if copy == null:
		return
	if part.material_override != null:
		copy.material_override = part.material_override.duplicate()
	copy.visible = true
	root.add_child(copy)
	copy.global_transform = part.global_transform


func _add(root: Node3D, velocity: Vector3, spin: Vector3, rest_y: float) -> void:
	var piece := Piece.new()
	piece.node = root
	piece.velocity = velocity
	piece.spin = spin
	piece.rest_y = rest_y
	_pieces.append(piece)


func _step(piece: Piece, delta: float) -> void:
	if not is_instance_valid(piece.node):
		return
	var xform: Transform3D = piece.node.global_transform
	if not piece.landed:
		piece.velocity.y -= GRAVITY_M_S2 * delta
		xform.origin += piece.velocity * delta
		if piece.spin.length_squared() > 0.0:
			xform.basis = Basis(piece.spin.normalized(), piece.spin.length() * delta) * xform.basis
		if xform.origin.y <= piece.rest_y:
			xform.origin.y = piece.rest_y
			piece.velocity.y = 0.0
			piece.landed = true
	else:
		var flat := Vector3(piece.velocity.x, 0.0, piece.velocity.z)
		var speed: float = maxf(flat.length() - SLIDE_DECEL_M_S2 * delta, 0.0)
		piece.velocity = flat.normalized() * speed if speed > 0.0 else Vector3.ZERO
		xform.origin += piece.velocity * delta
		xform.basis = xform.basis.orthonormalized().slerp(_flat(xform.basis),
				minf(SETTLE_RATE * delta, 1.0))
	piece.node.global_transform = xform


# Lying flat: the piece's root −Z — down the shaft, or out of the fist — laid
# level on the ice where it points, the root's +Y up.
static func _flat(basis: Basis) -> Basis:
	var along: Vector3 = -basis.orthonormalized().z
	var level := Vector3(along.x, 0.0, along.z)
	if level.length_squared() < 0.0001:
		level = Vector3(basis.x.x, 0.0, basis.x.z)
	if level.length_squared() < 0.0001:
		return basis.orthonormalized()
	return Basis.looking_at(level.normalized(), Vector3.UP)
