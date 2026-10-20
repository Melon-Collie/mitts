extends GutTest

# A client's puck node carries no velocity of its own — PuckController drives only
# its position, and linear_velocity holds whatever this client last fired. So the
# local player's one-timer and deflect judge the RENDERED flight
# (PuckController.rendered_loose_velocity); the host keeps its live puck.

const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const STALE := Vector3(0.0, 0.0, 30.0)      # the client's own last shot
const FEED := Vector3(-20.0, 0.0, 0.0)       # the pass actually coming at him

var _ctrl: LocalController = null
var _pc: PuckController = null
var _saved_pc: PuckController = null


func before_each() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.linear_velocity = STALE
	_ctrl = LocalController.new()
	_ctrl.puck = puck
	_pc = PuckController.new()
	_pc.rendered_loose_velocity = FEED
	_saved_pc = GameManager.puck_controller
	GameManager.puck_controller = _pc


func after_each() -> void:
	GameManager.puck_controller = _saved_pc
	_ctrl.free()
	_pc.free()


func _view() -> SkaterController.PuckView:
	var view := SkaterController.PuckView.new()
	_ctrl.sample_shooter_puck_view(InputState.new(), view)
	return view


func test_a_client_judges_the_flight_it_renders() -> void:
	_ctrl._is_host = false
	assert_eq(_view().velocity, FEED)


func test_the_host_judges_its_live_puck() -> void:
	_ctrl._is_host = true
	assert_eq(_view().velocity, STALE)


func test_the_stale_velocity_whiffs_a_swing_the_feed_connects() -> void:
	# A feed 1.2 m short of the zone, inside the leniency window at 20 m/s.
	var zone := Vector2.ZERO
	var puck_xz := Vector2(1.2, 0.0)
	var back: float = 0.08
	var fwd: float = 0.08
	assert_true(ShotReleaseRules.one_timer_connects(zone, 0.5, puck_xz,
			Vector2(FEED.x, FEED.z), false, back, fwd), "the host's verdict")
	assert_false(ShotReleaseRules.one_timer_connects(zone, 0.5, puck_xz,
			Vector2(STALE.x, STALE.z), false, back, fwd), "what the stale read said")
