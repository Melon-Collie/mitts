extends GutTest

# The gait's overlay layers (GaitLayer) as SkaterSkatingCoordinator composes
# them: lowest priority first, an override taking everything beneath it on the
# channels it owns.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = 1.0 / 120.0

var _skater: Skater = null
var _controller: SkaterController = null
var _coord: SkaterSkatingCoordinator = null


func before_each() -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_physics_process(false)
	_skater.set_process(false)
	_controller = SkaterController.new()
	autofree(_controller)
	_coord = SkaterSkatingCoordinator.new()
	_coord.setup(_skater, SkaterStateMachine.new(), _controller)
	_skater.set_facing(Vector2(0.0, -1.0))


func _knock_down() -> void:
	# Past the buckle, ahead of the get-up tail: the crumple at full weight.
	_controller.set("_knockdown_total", 1.5)
	_controller.knockdown_timer = 1.2


func test_layers_declare_stages_and_the_knockdown_overrides_last() -> void:
	var layers: Array[GaitLayer] = _coord._layers
	for layer: GaitLayer in layers:
		assert_ne(layer.stages(), 0, "%s takes part in no stage" % layer.get_script().get_global_name())
		assert_true(layer.is_quiet(), "%s should be quiet at rest" % layer.get_script().get_global_name())
	assert_eq(layers.back(), _coord._knockdown, "a body going down supersedes every other layer")
	assert_lt(layers.find(_coord._block), layers.find(_coord._knockdown),
			"a blocker who gets run over goes down; he doesn't hold the knee")


func test_knockdown_takes_the_stride_and_the_trunk_texture() -> void:
	_skater.velocity = Vector3(0.0, 0.0, -7.0)
	_skater.move_intent = Vector2(0.0, -1.0)
	var sway: float = 0.0
	for _i: int in 120:
		_coord.apply(DT)
		sway = maxf(sway, absf(_coord.trunk_pitch_add) + absf(_coord.trunk_roll_add))
	assert_gt(sway, 0.01, "the stride should texture the trunk before the hit (%.4f rad)" % sway)
	_knock_down()
	# The body slides on at speed with the stick still held — nothing the gait
	# reads from the skating stops; the crumple has to take it.
	for _i: int in 60:
		_coord.apply(DT)
	assert_almost_eq(_coord.trunk_pitch_add, 0.0, 0.002, "a downed body's trunk doesn't sway")
	assert_almost_eq(_coord.trunk_roll_add, 0.0, 0.002, "a downed body's trunk doesn't sway")
	assert_almost_eq(_skater.edge_load(true), 0.0, 0.001, "a downed body loads no edge")
	assert_almost_eq(_skater.edge_load(false), 0.0, 0.001, "a downed body loads no edge")
	assert_almost_eq(_coord.crouch_drop, _controller.knockdown_pose_drop_m, 0.001,
			"the crumple owns the drop")


func test_the_stance_widens_lowers_and_folds_without_moving_the_blade() -> void:
	for _i: int in 60:
		_coord.apply(DT)
	var upright_drop: float = _coord.crouch_drop
	var upright_pitch: float = _coord.trunk_pitch_add
	var upright_splay: float = _skater._legs._gait_leg_r.z - _skater._legs._gait_leg_l.z
	var frame: Transform3D = _skater.upper_body.transform
	_controller.stance_active = true
	for _i: int in 60:
		_coord.apply(DT)
	var splay: float = _skater._legs._gait_leg_r.z - _skater._legs._gait_leg_l.z
	assert_gt(splay - upright_splay, deg_to_rad(_controller.stance_width_deg) * 1.5,
			"both legs splay into the wide base (%.3f rad wider)" % (splay - upright_splay))
	assert_gt(_coord.crouch_drop, upright_drop + 0.02, "the stance sits the hips down")
	assert_lt(_coord.trunk_pitch_add, upright_pitch - 0.2, "the chest folds over the knees")
	assert_true(_skater.upper_body.transform.is_equal_approx(frame),
			"the stance poses the body, never the frame the blade hangs from")
	_controller.stance_active = false
	for _i: int in 120:
		_coord.apply(DT)
	assert_almost_eq(_coord.crouch_drop, upright_drop, 0.005, "letting go stands back up")


func test_knockdown_takes_the_check_commit_with_it() -> void:
	_skater.hit_committed = true
	for _i: int in 60:
		_coord.apply(DT)
	assert_lt(_coord.trunk_pitch_add, -0.05, "the commit leans into the check")
	_knock_down()
	for _i: int in 60:
		_coord.apply(DT)
	assert_almost_eq(_coord.trunk_pitch_add, 0.0, 0.002, "going down drops the load-up")
	assert_almost_eq(_coord.crouch_drop, _controller.knockdown_pose_drop_m, 0.001,
			"the commit's sink rides under the crumple, not on top of it")
