extends GutTest

# Screening (KeeperScreen, KeeperShotRead): from his spot a body on his
# sightline to the puck he looks round with a step across, no further than
# half his chest, after which he sees it; one square on his line he cannot see
# round; a clean look asks nothing. A release a body hides from him is read
# once it comes out of the shadow.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SPOT := Vector2(0.0, -1.2)
const PUCK := Vector3(0.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, -8.0)

var _screen: KeeperScreen = null
var _cfg := GoalieScreenRules.ScreenConfig.new()


func before_each() -> void:
	_screen = KeeperScreen.new()


func _hidden(at: Vector2, bodies: PackedVector3Array, low: bool) -> bool:
	_cfg.eye_height = KeeperScreen.eye_height(low)
	return GoalieScreenRules.hidden_by(Vector3(at.x, 0.0, at.y), PUCK, bodies, _cfg) >= 0


func test_a_clean_look_asks_nothing() -> void:
	_screen.look(SPOT, PUCK, PackedVector3Array([Vector3(3.0, 0.0, -4.0)]), false)
	assert_eq(_screen.step, Vector2.ZERO, "no step")


# A body anywhere between: any step he takes sees past every body and is no
# further than half his chest, across his line. He steps round some, and a
# body square on his line he cannot.
func test_round_a_screen_he_steps_to_see_it() -> void:
	var stepped: int = 0
	for z: float in [-2.5, -3.5, -4.5, -5.5, -6.5, -7.2]:
		for x: float in [-0.45, -0.3, -0.15, 0.0, 0.1, 0.25, 0.4]:
			var bodies := PackedVector3Array([Vector3(x, 0.0, z)])
			_screen.look(SPOT, PUCK, bodies, false)
			var what: String = "a body at (%.2f, %.2f)" % [x, z]
			if _screen.step == Vector2.ZERO:
				continue
			stepped += 1
			assert_true(_hidden(SPOT, bodies, false), what + ": stepped only round a screen")
			assert_lte(_screen.step.length(), KeeperScreen.STEP_MAX_M + 1e-5, what + ": half his chest at most")
			assert_false(_hidden(SPOT + _screen.step, bodies, false), what + ": seen past it")
			var line: Vector2 = Vector2(PUCK.x, PUCK.z) - SPOT
			assert_almost_eq(_screen.step.dot(line.normalized()), 0.0, 1e-4, what + ": across his line")
	assert_gt(stepped, 0, "steps round some")
	_screen.look(SPOT, PUCK, PackedVector3Array([Vector3(0.0, 0.0, -3.0)]), false)
	assert_eq(_screen.step, Vector2.ZERO, "square on his line: no step sees round it")
	assert_true(_hidden(SPOT, PackedVector3Array([Vector3(0.0, 0.0, -3.0)]), false), "and he is screened")


# The step is round the near edge: away from the side of his line the body
# stands on.
func test_he_steps_round_the_near_edge() -> void:
	for x: float in [-0.25, 0.25]:
		_screen.look(SPOT, PUCK, PackedVector3Array([Vector3(x, 0.0, -4.5)]), false)
		assert_ne(_screen.step, Vector2.ZERO, "%+.2f: stepped" % x)
		assert_eq(signf(_screen.step.x), -signf(x), "%+.2f: the other way" % x)


func test_a_hidden_release_is_read_once_out_of_the_shadow() -> void:
	var read := KeeperShotRead.new()
	read.step(0.0, PUCK, Vector3(0.0, 0.0, 25.0))
	read.start(false, 0.0, 0.15)
	var t: float = 0.0
	while not read.legs_read():
		read.step(DT, read.position_in(DT), read.velocity)
		t += DT
	assert_almost_eq(t, 0.15 + read.leg_delay_s, DT + 1e-5, "his read after the shadow")
