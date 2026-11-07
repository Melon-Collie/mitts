extends GutTest

# The host judges a remote one-timer against the puck its shooter swung at. The
# shooter's client draws the loose puck on the render clock — its input stamp —
# and its tick (SkaterController, priority -1) reads what PuckController (+1)
# drew the tick before. So a swing stamped S was judged against the puck at
# S - one tick, whatever the shooter's ping. Reading it a whole input lead
# earlier put the host's swept window 0.5-2.5 m behind a fast feed.

const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")

var _ctrl: RemoteController = null
var _asked: Array[float] = []


func before_each() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	_ctrl = RemoteController.new()
	_ctrl.puck = puck
	_ctrl._is_host = true
	_asked.clear()
	_ctrl.set_puck_history_provider(func(t: float, _out: SkaterController.PuckView) -> void:
		_asked.append(t))


func after_each() -> void:
	_ctrl.free()


func _sample_at(stamp: float) -> float:
	var input := InputState.new()
	input.host_timestamp = stamp
	_ctrl.sample_shooter_puck_view(input, SkaterController.PuckView.new())
	assert_eq(_asked.size(), 1, "the host reads the shooter's puck out of its buffer")
	return _asked[0] if not _asked.is_empty() else NAN


func test_the_host_reads_the_puck_the_shooter_drew() -> void:
	assert_almost_eq(_sample_at(10.0), 10.0 - Constants.TICK_DURATION, 1e-9)


func test_the_instant_does_not_move_with_ping() -> void:
	# The render clock carries the lead; the stamp already includes it, so
	# nothing about the link may shift the read.
	var a: float = _sample_at(10.0)
	_asked.clear()
	_ctrl.net_peer_id = 77  # a peer the host holds no ping for
	assert_almost_eq(_sample_at(10.0), a, 1e-9)


func test_a_client_judges_its_own_rendered_puck() -> void:
	_ctrl._is_host = false
	var input := InputState.new()
	input.host_timestamp = 10.0
	_ctrl.sample_shooter_puck_view(input, SkaterController.PuckView.new())
	assert_eq(_asked.size(), 0)
