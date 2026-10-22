class_name GoalieToeBridge
extends RefCounted

# The pad's toe bridge: hung from the bottom of the pad and laid over the front
# of the skate onto the ice (GoalieSkates), so it stretches as the pad rolls
# above a skate that stays down. Its top follows the pad's bottom edge and its
# foot lies level on the ice, which no rigid piece can do, so it is redrawn
# whenever the pads move and draws itself rather than joining the merged body
# (GoalieBodyRig.DRAWS_ITSELF). Its collider is the box over the toe it comes to
# rest on: WIDTH_M across, FOOT_HEIGHT_M tall, LENGTH_M back from its front edge.

const WIDTH_M: float = GoalieAnatomy.PAD_BOX_WIDTH_M * 0.86   # the pad's toe station
const LENGTH_M: float = 0.16
const FOOT_HEIGHT_M: float = 0.12

# The corners `draw` takes, in this order: the top's front left, front right,
# back left, back right (on the pad), then the foot's the same way (on the ice).
const CORNERS: int = 8

# Faces as four corner indices each, each listed so its first three span it:
# front (pad down to the ice), back, left, right, top (against the pad), foot.
const _FACES: Array[int] = [
	0, 1, 5, 4,
	3, 2, 6, 7,
	2, 0, 4, 6,
	1, 3, 7, 5,
	0, 2, 3, 1,
	4, 5, 7, 6,
]


# Redraws `mesh` as the bridge between `corners` (see CORNERS), flat-shaded with
# every face turned out from the bridge's middle.
static func draw(mesh: ImmediateMesh, corners: PackedVector3Array) -> void:
	var middle := Vector3.ZERO
	for c: Vector3 in corners:
		middle += c
	middle /= float(CORNERS)
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: int in range(0, _FACES.size(), 4):
		var a: Vector3 = corners[_FACES[f]]
		var b: Vector3 = corners[_FACES[f + 1]]
		var c: Vector3 = corners[_FACES[f + 2]]
		var d: Vector3 = corners[_FACES[f + 3]]
		var n: Vector3 = (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		# Godot's front faces wind clockwise seen from outside, where this cross
		# product points inward; a face spanned the other way is turned round.
		if n.dot((a + b + c + d) * 0.25 - middle) > 0.0:
			var t: Vector3 = b
			b = d
			d = t
		else:
			n = -n
		mesh.surface_set_normal(n.normalized())
		mesh.surface_set_color(Color.WHITE)
		mesh.surface_add_vertex(a)
		mesh.surface_add_vertex(b)
		mesh.surface_add_vertex(c)
		mesh.surface_add_vertex(a)
		mesh.surface_add_vertex(c)
		mesh.surface_add_vertex(d)
	mesh.surface_end()
