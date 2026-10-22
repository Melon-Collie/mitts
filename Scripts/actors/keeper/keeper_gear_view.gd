class_name KeeperGearView
extends Node3D

# The keeper's gear drawn on his skeleton: each piece's mesh placed on its save
# box (KeeperGearMeshes builds them inside the boxes), and the break above each
# knee joining the pad to its thigh rise, painted from the kit by paint slot.
# One material per slot is shared by every piece that wears it, so a repaint is
# a handful of colour writes.

const S := KeeperMeshKit.Slot

# The slots no kit colours: skate steel and boot, the stick, tape, straps, cage.
const _FIXED: Dictionary = {
	S.SKATE_BOOT: Color(0.10, 0.10, 0.11),
	S.SKATE_STEEL: Color(0.78, 0.80, 0.84),
	S.STICK: Color(0.92, 0.92, 0.90),
	S.STICK_TAPE: Color(0.12, 0.12, 0.13),
	S.STRAP: Color(0.15, 0.15, 0.16),
	S.CAGE: Color(0.86, 0.86, 0.88),
}

var _pieces: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _knees: Array[KeeperKneeBreak] = []


func _ready() -> void:
	for slot: int in KeeperMeshKit.SLOT_COUNT:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.75
		m.albedo_color = _FIXED.get(slot, Color(0.85, 0.85, 0.85))
		_materials.append(m)
	_materials[S.SKATE_STEEL].metallic = 0.6
	_materials[S.SKATE_STEEL].roughness = 0.35
	for part: int in KeeperGear.PART_COUNT:
		var mi := MeshInstance3D.new()
		var mesh: ArrayMesh = KeeperGearMeshes.mesh(part)
		mi.mesh = mesh
		var slots: PackedInt32Array = KeeperMeshKit.surface_slots(mesh)
		for s: int in slots.size():
			mi.set_surface_override_material(s, _materials[slots[s]])
		add_child(mi)
		_pieces.append(mi)
	for side: int in 2:
		var knee := KeeperKneeBreak.new(KeeperGear.Part.PAD_G + side,
				KeeperGear.Part.RISE_G + side, _materials[S.PADS])
		add_child(knee)
		_knees.append(knee)
	apply_colors({
		"jersey": Color(0.59, 0.09, 0.16), "jersey_stripe": Color(0.91, 0.27, 0.35),
		"pants": Color(0.59, 0.09, 0.16), "pants_stripe": Color(0.91, 0.27, 0.35),
		"gloves": Color(0.96, 0.96, 0.96), "glove_accent": Color(0.59, 0.09, 0.16),
		"helmet": Color(0.59, 0.09, 0.16), "goalie_pads": Color(0.96, 0.96, 0.96),
	})


# A team's colours, as TeamColorRegistry.get_colors returns them.
func apply_colors(colors: Dictionary) -> void:
	_paint_slot(S.JERSEY, colors.get("jersey"))
	_paint_slot(S.JERSEY_STRIPE, colors.get("jersey_stripe"))
	_paint_slot(S.PANTS, colors.get("pants"))
	_paint_slot(S.PANTS_STRIPE, colors.get("pants_stripe"))
	_paint_slot(S.GLOVES, colors.get("gloves"))
	_paint_slot(S.GLOVE_ACCENT, colors.get("glove_accent"))
	_paint_slot(S.HELMET, colors.get("helmet"))
	_paint_slot(S.PADS, colors.get("goalie_pads"))


func _paint_slot(slot: int, c: Variant) -> void:
	if c is Color:
		_materials[slot].albedo_color = c


func update(skel: KeeperSkeleton) -> void:
	for part: int in _pieces.size():
		_pieces[part].transform = KeeperGear.box(skel, part)
	for knee: KeeperKneeBreak in _knees:
		knee.update(skel)
