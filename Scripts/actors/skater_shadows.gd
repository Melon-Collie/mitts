class_name SkaterShadows
extends RefCounted

# Whether the skater casts a shadow: the player's Video setting (set_enabled),
# reaching the body's meshes on the skeleton (the skin and its rigid parts, one
# surface each), the stick and the blade. The small pieces a shadow map cannot
# resolve — the knob, the tape, the face gear — never cast, where they are
# created. A ghost is drawn translucent, and casts nothing either.

# A skater built later reads it in build().
static var enabled: bool = true

# Every built switch, so a settings change reaches the skaters already on the ice.
static var _live: Array[WeakRef] = []

var _casters: Array[GeometryInstance3D] = []
var _ghost: bool = false


# `skeleton` already carries the body's meshes.
func build(skeleton: Skeleton3D, stick: GeometryInstance3D, blade: GeometryInstance3D) -> void:
	for child: Node in skeleton.get_children():
		if child is MeshInstance3D:
			_casters.append(child as MeshInstance3D)
	for part: GeometryInstance3D in [stick, blade]:
		if part != null:
			_casters.append(part)
	_live.append(weakref(self))
	refresh()


static func set_enabled(on: bool) -> void:
	enabled = on
	var kept: Array[WeakRef] = []
	for ref: WeakRef in _live:
		var switch: SkaterShadows = ref.get_ref() as SkaterShadows
		if switch != null:
			switch.refresh()
			kept.append(ref)
	_live = kept


func set_ghost(ghost: bool) -> void:
	_ghost = ghost
	refresh()


func refresh() -> void:
	var cast: GeometryInstance3D.ShadowCastingSetting = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled and not _ghost \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for part: GeometryInstance3D in _casters:
		if is_instance_valid(part):
			part.cast_shadow = cast
