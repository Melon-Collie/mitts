class_name GoalieSkates
extends RefCounted

# The keeper's skates: the skater's boot and blade under the foot of each pad,
# held flat on the ice by the ankle while the pad rolls and pitches above, with
# the pad's toe bridge laid over the front of each. A puck slid under a pad
# rolled onto its inside edge meets the boot or the toe rather than open ice.
# Every piece is a child of its pad's body — that pad's save surface
# (Puck._classify_save_part) and on its collision layer — and is re-placed after
# every pad write (place). Nothing about it is on the wire: a client places it
# from the replicated pads.

# The boot assembly is authored in the skater's Foot frame (toe −Y, +Z down);
# this turns it to the keeper's (toe −Z, +Y up).
const _FOOT_TO_LEVEL := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, -1.0, 0.0))
const _BOOT_COLOR := Color(0.10, 0.10, 0.11)
const _HOLDER_COLOR := Color(0.92, 0.92, 0.90)
# How far the toe bridge reaches past the boot's toe.
const TOE_CAP_OVERHANG_M: float = 0.03

var _pads: Array[StaticBody3D] = []
var _skates: Array[CollisionShape3D] = []
var _caps: Array[CollisionShape3D] = []
var _cap_meshes: Array[MeshInstance3D] = []
# The skate's box in its level frame, origin on the ice under the boot's centre.
var _box := AABB()
# The toe cap's box in the same frame.
var _cap_box := AABB()


func _init(left_pad: StaticBody3D, right_pad: StaticBody3D) -> void:
	var boot: ArrayMesh = SkaterMeshBuilder.shared_boot_assembly()
	var level: AABB = Transform3D(_FOOT_TO_LEVEL, Vector3.ZERO) * boot.get_aabb()
	# Seat the runner's bottom on the ice and centre the boot over the origin.
	var seat := Vector3(-level.get_center().x, -level.position.y, -level.get_center().z)
	_box = AABB(level.position + seat, level.size)
	var cap: ArrayMesh = GoalieToeCapMesh.shared()
	var cap_front := Vector3(0.0, 0.0, _box.position.z - TOE_CAP_OVERHANG_M)
	_cap_box = AABB(cap.get_aabb().position + cap_front, cap.get_aabb().size)
	for pad: StaticBody3D in [left_pad, right_pad]:
		var skate := _piece(pad, "Skate", _box)
		var view := MeshInstance3D.new()
		view.name = "SkateMesh"
		view.mesh = boot
		view.transform = Transform3D(_FOOT_TO_LEVEL, seat - _box.get_center())
		_paint(view)
		skate.add_child(view)
		var toe := _piece(pad, "ToeCap", _cap_box)
		var cap_view := MeshInstance3D.new()
		cap_view.name = "ToeCapMesh"
		cap_view.mesh = cap
		cap_view.position = cap_front - _cap_box.get_center()
		toe.add_child(cap_view)
		_pads.append(pad)
		_skates.append(skate)
		_caps.append(toe)
		_cap_meshes.append(cap_view)


# The toe caps' meshes, which the uniform pass paints as the pads.
func toe_cap_meshes() -> Array[MeshInstance3D]:
	return _cap_meshes


# Re-seat both skates and their toe caps under their pads as they stand now.
func place() -> void:
	for i: int in _pads.size():
		var pad: Transform3D = _pads[i].transform
		var to_pad: Transform3D = pad.affine_inverse()
		var level: Transform3D = level_frame(pad)
		_skates[i].transform = to_pad * level * Transform3D(Basis.IDENTITY, _box.get_center())
		_caps[i].transform = to_pad * level * Transform3D(Basis.IDENTITY, _cap_box.get_center())


# The skate's level frame, in the goalie's, for a pad posed at `pad`: on the
# ice under the pad's foot with the boot's toe flush with the pad's face,
# turned the way the pad faces.
func level_frame(pad: Transform3D) -> Transform3D:
	var half := Vector3(GoalieAnatomy.PAD_BOX_WIDTH_M, GoalieAnatomy.PAD_BOX_HEIGHT_M,
			GoalieAnatomy.PAD_BOX_DEPTH_M) * 0.5
	var foot: Vector3 = pad * Vector3(0.0, -half.y, -half.z + _box.size.z * 0.5)
	var face: Vector3 = -pad.basis.z
	var yaw: float = atan2(-face.x, -face.z) if Vector2(face.x, face.z).length() > 0.001 \
			else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(foot.x, 0.0, foot.z))


static func _piece(pad: StaticBody3D, piece_name: String, box: AABB) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = box.size
	var piece := CollisionShape3D.new()
	piece.name = piece_name
	piece.shape = shape
	pad.add_child(piece)
	return piece


static func _paint(view: MeshInstance3D) -> void:
	for surface: int in [SkaterMeshBuilder.BOOT_SURF_SHELL, SkaterMeshBuilder.BOOT_SURF_TOE,
			SkaterMeshBuilder.BOOT_SURF_HOLDER]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _HOLDER_COLOR if surface == SkaterMeshBuilder.BOOT_SURF_HOLDER \
				else _BOOT_COLOR
		mat.roughness = 0.5
		BodyRim.apply(mat)
		view.set_surface_override_material(surface, mat)
