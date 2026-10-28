class_name KeeperBoxView
extends Node3D

# The keeper's save geometry drawn as it is: one translucent box per gear part,
# tinted by the material it rebounds as. A debug and capture view — what the
# puck meets, which the gear meshes are drawn inside.

const _TINT: Dictionary = {
	GoalieSaveRules.SavePart.PAD: Color(0.85, 0.85, 0.90, 0.55),
	GoalieSaveRules.SavePart.CHEST: Color(0.30, 0.45, 0.85, 0.55),
	GoalieSaveRules.SavePart.GLOVE: Color(0.85, 0.55, 0.20, 0.65),
	GoalieSaveRules.SavePart.BLOCKER: Color(0.85, 0.30, 0.30, 0.65),
	GoalieSaveRules.SavePart.MASK: Color(0.95, 0.95, 0.40, 0.65),
	GoalieSaveRules.SavePart.STICK: Color(0.15, 0.15, 0.15, 0.85),
}

var _boxes: Array[MeshInstance3D] = []


func _ready() -> void:
	for part: int in KeeperGear.PART_COUNT:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = KeeperGear.half_extents(part) * 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _TINT[KeeperGear.save_part(part)]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material = mat
		mi.mesh = mesh
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(mi)
		_boxes.append(mi)


func update(skel: KeeperSkeleton) -> void:
	for part: int in _boxes.size():
		_boxes[part].transform = KeeperGear.box(skel, part)
