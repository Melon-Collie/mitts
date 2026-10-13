class_name ArenaReflection
extends ReflectionProbe

# One box-projected probe over the whole bowl, so the ice, the glass and the
# gear reflect the building. Screen-space reflections can only return what is on
# screen, and from the top-down play camera the stands almost never are.
#
# It captures once (UPDATE_ONCE) and re-renders only when asked, so it must see
# only what holds still: every capture first tags the arena root's default-layer
# geometry and lights REFLECTED_STATIC, and the probe draws that layer (plus the
# overhead dressing) alone. Skaters, goalies and the puck spawn outside the arena
# root, so a capture never bakes a ghost of where someone stood at load.

# The cube is shot from this high over centre ice rather than from the box's
# centre ~10 m up: what reads the reflection is the ice and the glass, and a
# capture from near them puts the stands where those surfaces expect them.
const CAPTURE_HEIGHT: float = 2.5
# Drops the box floor below the ice so the ice is not inside the edge band the
# probe blends out across (blend_distance).
const FLOOR_MARGIN: float = 1.5
# A probe re-renders when its transform changes, and there is no other request
# for one; each capture moves it by this much, alternating sign. Well under
# anything a box-projected lookup can show.
const _NUDGE_M: float = 0.001

var _reflected_root: Node = null
var _center: Vector3 = Vector3.ZERO
var _nudge_sign: float = 1.0
var _capture_pending: bool = false
var _house_level: float = 1.0
# A capture shot while the house lights were down holds a dark bowl; it is shot
# again once they are back at full.
var _captured_dim: bool = false


# `reflected_root` is the arena scene: everything under it on the default layer
# is building, and gets tagged into the probe at each capture.
func setup(reflected_root: Node) -> void:
	_reflected_root = reflected_root
	update_mode = UPDATE_ONCE
	box_projection = true
	enable_shadows = true
	# Reflections only. ENVIRONMENT would replace the WorldEnvironment's ambient
	# inside the box with the cube's own blur, and the cube is a dark bowl;
	# DISABLED leaves that ambient, the even fill the house lights dim, as it is.
	ambient_mode = AMBIENT_DISABLED
	cull_mask = RenderLayers.REFLECTED_STATIC | RenderLayers.OVERHEAD_DRESSING


# Size the box to the bowl (`bounds` in the parent's space, ice at y = 0) and
# shoot a fresh capture. Called after every rebuild, since a rebuild is new
# geometry or a crowd repaint the old cube does not hold.
func fit(bounds: AABB) -> void:
	_center = bounds.get_center()
	size = bounds.size
	origin_offset = Vector3(0.0, CAPTURE_HEIGHT - _center.y, 0.0)
	request_capture()


# Brightness of the house as ArenaHouseLights runs it, 0 (down) to 1 (full).
# The cube is lit at full, so its intensity follows the lights.
func set_house_level(level: float) -> void:
	_house_level = level
	intensity = level
	if level >= 1.0 and _captured_dim:
		request_capture()


# Deferred to the end of the frame, so a capture asked for mid-build sees every
# sibling that builds in the same frame (the jumbotron readies after the bowl).
func request_capture() -> void:
	if _capture_pending:
		return
	_capture_pending = true
	_capture.call_deferred()


func _capture() -> void:
	_capture_pending = false
	if not is_inside_tree():
		return
	if is_instance_valid(_reflected_root):
		tag_static(_reflected_root)
	_captured_dim = _house_level < 1.0
	_nudge_sign = -_nudge_sign
	position = _center + Vector3(0.0, _NUDGE_M * _nudge_sign, 0.0)


# Adds REFLECTED_STATIC to every default-layer visual under `root`, lights
# included: a light outside the probe's cull mask does not light its capture.
# Particles are left out (a capture mid-burst would freeze it in the cube), and
# so is anything inside a SubViewport, which is another world's content.
static func tag_static(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is SubViewport:
			continue
		stack.append_array(node.get_children())
		if node is GPUParticles3D or node is CPUParticles3D:
			continue
		var visual: VisualInstance3D = node as VisualInstance3D
		if visual != null and (visual.layers & RenderLayers.DEFAULT) != 0:
			visual.layers |= RenderLayers.REFLECTED_STATIC
