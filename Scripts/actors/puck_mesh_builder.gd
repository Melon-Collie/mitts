class_name PuckMeshBuilder
extends SkaterMeshBuilder

# Beveled low-poly puck replacing the smooth CylinderMesh
# (Assets/puck_mesh.tres, r 0.0381 × h 0.0254): same envelope, 12 flat-shaded
# sides, with a real puck's edge chamfer so the disc catches highlights on
# its rims instead of reading as a featureless dark ellipse from the game
# camera. Cosmetic only — puck physics is analytic
# (GameRules.PUCK_COLLISION_RADIUS); nothing reads this mesh.

# (height, radius), top rim down to the bottom chamfer.
const PROFILE: Array[Vector2] = [
	Vector2(0.0127, 0.034),   # top face rim
	Vector2(0.0083, 0.0381),  # chamfer → full radius
	Vector2(-0.0083, 0.0381),
	Vector2(-0.0127, 0.034),  # bottom chamfer
]


const SIDES: int = 12
# The top face is its own surface so it can wear PuckPrint; the rim and the
# bottom face are surface 0, the rubber.
const SURF_FACE: int = 1


static func apply_puck(puck: Node3D) -> void:
	_swap(puck, "MeshInstance3D", "puck", _build_puck)
	var mi: MeshInstance3D = puck.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		return
	var mesh: ArrayMesh = mi.mesh as ArrayMesh
	var rubber: BaseMaterial3D = mesh.surface_get_material(0) as BaseMaterial3D
	var base: Color = rubber.albedo_color if rubber != null else Color.BLACK
	mesh.surface_set_material(SURF_FACE, PuckPrint.material(base))


# _build_lathe's band and bottom cap, with the top cap split off. The face's UV
# is planar: (0.5, 0.5) at its centre, its corners at radius 0.5.
static func _build_puck() -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	for s: Vector2 in PROFILE:
		rings.append(_ring(s.x, s.y, 1.0, 1.0, SIDES))
	var y_top: float = PROFILE[0].x
	var y_bot: float = PROFILE[PROFILE.size() - 1].x
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in PROFILE.size() - 1:
		var v0: float = 0.5 * (y_top - PROFILE[i].x) / (y_top - y_bot)
		var v1: float = 0.5 * (y_top - PROFILE[i + 1].x) / (y_top - y_bot)
		for k in SIDES:
			var u0: float = float(k) / float(SIDES)
			var u1: float = float(k + 1) / float(SIDES)
			_uv_quad(st,
					rings[i][k], Vector2(u0, v0),
					rings[i][k + 1], Vector2(u1, v0),
					rings[i + 1][k + 1], Vector2(u1, v1),
					rings[i + 1][k], Vector2(u0, v1))
	_cap(st, rings[rings.size() - 1], Vector3(0.0, y_bot, 0.0), Vector2(0.75, 0.75), false)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	face.set_smooth_group(-1)
	_cap(face, rings[0], Vector3(0.0, y_top, 0.0), Vector2(0.5, 0.5), true, 0.5)
	face.generate_normals()
	return face.commit(mesh)
