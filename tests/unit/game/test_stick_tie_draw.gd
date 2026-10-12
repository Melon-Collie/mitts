extends GutTest

# StickTieDraw: two tied sticks apart on the host's terms are drawn meeting in
# the middle, a mesh-only slide that never moves the gameplay Blade marker.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")

var _a: Skater = null
var _b: Skater = null
var _draw: StickTieDraw = null


func before_each() -> void:
	_a = _spawn_skater(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0))
	_b = _spawn_skater(Vector3(2.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0))
	_draw = StickTieDraw.new()


func _spawn_skater(pos: Vector3) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.global_position = pos
	s.set_physics_process(false)
	s.set_process(false)
	return s


func _gap() -> float:
	return StickCheckRules.stick_gap(_a.upper_body_to_global(_a.get_top_hand_position()),
			_a.get_blade_contact_global(),
			_b.upper_body_to_global(_b.get_top_hand_position()), _b.get_blade_contact_global())


func test_tied_sticks_slide_toward_each_other_by_half_the_gap() -> void:
	_a.stick_tied = true
	_b.stick_tied = true
	var gap: float = _gap()
	assert_gt(gap, 0.0, "the rig's sticks start apart")
	_draw.update([_a, _b] as Array[Skater], {_a: 0, _b: 1})
	assert_almost_eq(_a._tie_draw_target.length(), gap * 0.5, 1e-4)
	assert_almost_eq(_b._tie_draw_target.length(), gap * 0.5, 1e-4)
	assert_lt(_a._tie_draw_target.dot(_b._tie_draw_target), 0.0, "toward each other")


func test_untied_or_teammates_get_no_slide() -> void:
	_a.stick_tied = true
	_b.stick_tied = true
	_draw.update([_a, _b] as Array[Skater], {_a: 0, _b: 0})
	assert_eq(_a._tie_draw_target, Vector3.ZERO, "a teammate is never the partner")
	_b.stick_tied = false
	_draw.update([_a, _b] as Array[Skater], {_a: 0, _b: 1})
	assert_eq(_a._tie_draw_target, Vector3.ZERO)


func test_the_slide_moves_the_mesh_not_the_marker() -> void:
	_a.stick_tied = true
	_b.stick_tied = true
	var marker: Vector3 = _a.blade.global_position
	_draw.update([_a, _b] as Array[Skater], {_a: 0, _b: 1})
	_a._tie_draw_offset = _a._tie_draw_target
	var before: Vector3 = _a._blade_mesh_instance.global_position
	_a._apply_blade_tilt()
	assert_eq(_a.blade.global_position, marker, "gameplay geometry is untouched")
	var moved: Vector3 = _a._blade_mesh_instance.global_position - before
	assert_almost_eq(Vector2(moved.x, moved.z).length(), _a._tie_draw_target.length(), 0.01,
			"the drawn blade slides by the offset")
