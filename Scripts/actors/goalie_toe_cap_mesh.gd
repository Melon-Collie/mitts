class_name GoalieToeCapMesh
extends SkaterMeshBuilder

# The pad's toe bridge, laid over the front of the skate (GoalieSkates) in a
# level frame: x across, y up from the ice, z back from its front edge. As wide
# as the pad's toe station, low at the front and rising over the boot's instep.
# Built here rather than in GoalieMeshBuilder because it rides the skate, not
# the pad.

const WIDTH_M: float = GoalieAnatomy.PAD_BOX_WIDTH_M * 0.86
const LENGTH_M: float = 0.16
const FRONT_HEIGHT_M: float = 0.05
const BACK_HEIGHT_M: float = 0.12


static func shared() -> ArrayMesh:
	return _shared("goalie_toe_cap", func() -> ArrayMesh:
		var x: float = WIDTH_M * 0.5
		var hf: float = FRONT_HEIGHT_M
		var hb: float = BACK_HEIGHT_M
		var l: float = LENGTH_M
		var z0 := Vector2.ZERO
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder's class doc
		st.set_color(Color.WHITE)
		_uv_quad(st,  # top, sloping up from the front
				Vector3(-x, hf, 0.0), z0, Vector3(x, hf, 0.0), z0,
				Vector3(x, hb, l), z0, Vector3(-x, hb, l), z0)
		_uv_quad(st,  # front
				Vector3(x, hf, 0.0), z0, Vector3(-x, hf, 0.0), z0,
				Vector3(-x, 0.0, 0.0), z0, Vector3(x, 0.0, 0.0), z0)
		_uv_quad(st,  # back
				Vector3(-x, hb, l), z0, Vector3(x, hb, l), z0,
				Vector3(x, 0.0, l), z0, Vector3(-x, 0.0, l), z0)
		_uv_quad(st,  # +X
				Vector3(x, hb, l), z0, Vector3(x, hf, 0.0), z0,
				Vector3(x, 0.0, 0.0), z0, Vector3(x, 0.0, l), z0)
		_uv_quad(st,  # −X
				Vector3(-x, hf, 0.0), z0, Vector3(-x, hb, l), z0,
				Vector3(-x, 0.0, l), z0, Vector3(-x, 0.0, 0.0), z0)
		_uv_quad(st,  # bottom
				Vector3(-x, 0.0, l), z0, Vector3(x, 0.0, l), z0,
				Vector3(x, 0.0, 0.0), z0, Vector3(-x, 0.0, 0.0), z0)
		st.generate_normals()
		return st.commit())
