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


static func apply_puck(puck: Node3D) -> void:
	_swap(puck, "MeshInstance3D", "puck", _build_puck)


static func _build_puck() -> ArrayMesh:
	return _build_lathe(PROFILE, 12, 1.0, 1.0)
