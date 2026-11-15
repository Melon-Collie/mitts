class_name PingPreview
extends Node3D

# A smart ping before it is sent. While the key is held it draws, fainter than
# the real thing, the call the ping would make and the ring on what it would
# mark, and reads both again every frame: the call turns on who has the puck,
# and that changes under a held key.

# The bubble's tail stands this far clear of the ring, up the screen from it.
const _CALLOUT_GAP_M: float = 0.15

# () -> PingRules.Resolution: what the ping would say now, null for nothing.
var _resolve: Callable = Callable()
# (PingRules.Resolution) -> Node3D: the skater or puck it would mark, null
# when it marks no one.
var _subject_of: Callable = Callable()
var _marker: PingMarker = null
var _callout: PingCallout = null


func setup(resolve: Callable, subject_of: Callable) -> void:
	_resolve = resolve
	_subject_of = subject_of


func _ready() -> void:
	_marker = PingMarker.held()
	add_child(_marker)
	_callout = PingCallout.new()
	add_child(_callout)
	close()


func open() -> void:
	set_process(true)
	_refresh()


func close() -> void:
	set_process(false)
	_show_nothing()


func is_open() -> bool:
	return is_processing()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	# Whoever resolves the ping is the session's, and this node is the scene's.
	if not _resolve.is_valid() or not _subject_of.is_valid():
		close()
		return
	var res: PingRules.Resolution = _resolve.call() as PingRules.Resolution
	if res == null:
		_show_nothing()
		return
	var subject: Node3D = _subject_of.call(res) as Node3D
	var at: Vector3 = res.world_pos
	if subject != null:
		_marker.aim_at_node(subject)
		at = PingMarker.ground_of(subject)
	elif res.type == PingRules.Type.GO_THERE:
		_marker.aim_at_spot(at)
	else:
		_show_nothing()
		return
	_marker.visible = true
	var reach: float = _marker.held_radius() + _CALLOUT_GAP_M
	var up: Vector2 = _screen_up()
	_callout.hold(tr(PingRules.message_key_for(res.type)))
	_callout.global_position = Vector3(at.x + up.x * reach, 0.0, at.z + up.y * reach)


func _show_nothing() -> void:
	_marker.visible = false
	_callout.dismiss()


# The direction on the ice (XZ) that runs up the screen.
func _screen_up() -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(0.0, -1.0)
	var basis_y: Vector3 = cam.global_transform.basis.y
	var up := Vector2(basis_y.x, basis_y.z)
	return up.normalized() if up.length_squared() > 0.0001 else Vector2(0.0, -1.0)
