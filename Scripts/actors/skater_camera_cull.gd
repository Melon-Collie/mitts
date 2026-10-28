class_name SkaterCameraCull
extends Object

# Whether the current camera can see a skater, for the render pass's mesh work
# (Skater.on_camera): a bounding sphere against the camera's frustum. Every
# skater shares one frustum, rebuilt only when the camera moves or changes.
#
# Built in the CAMERA's frame from its projection, with the skater brought into
# it, rather than from Camera3D.get_frustum: that call's space differs between
# the headless and the rendering server.

# Off while something draws the scene through a camera of its own
# (ClipFrameCapture), which can frame skaters the live camera does not.
static var enabled: bool = true

# Body, stick reach and a lying sprawl about the skater's origin, plus a tick of
# travel.
const RADIUS_M: float = 2.5

static var _planes: Array[Plane] = []
static var _camera: int = 0
static var _camera_xform := Transform3D()
static var _to_camera := Transform3D()
static var _has_camera: bool = false


# True with no camera (tests, headless tools) or with culling off.
static func sees(node: Node3D) -> bool:
	_has_camera = false
	if not enabled:
		return true
	var cam: Camera3D = node.get_viewport().get_camera_3d()
	if cam == null:
		return true
	_has_camera = true
	if cam.get_instance_id() != _camera or cam.global_transform != _camera_xform:
		_camera = cam.get_instance_id()
		_camera_xform = cam.global_transform
		_to_camera = _camera_xform.affine_inverse()
		var projection: Projection = cam.get_camera_projection()
		_planes.resize(6)
		for i: int in 6:
			_planes[i] = projection.get_projection_plane(i)
	var center: Vector3 = _to_camera * node.global_position
	for plane: Plane in _planes:
		if plane.distance_to(center) > RADIUS_M:
			return false
	return true


# How far `node` is from the camera `sees` just tested it against, or -1 when
# that call had no camera to test (tests, headless tools, culling off).
static func distance(node: Node3D) -> float:
	if not _has_camera:
		return -1.0
	return _camera_xform.origin.distance_to(node.global_position)
