extends GutTest

# The stop's sound is the gait's stop (SkaterController.skate_scrape): one bite
# as the blades dig in, then a scrape held as long as they shed speed, louder
# the faster; the skid's snowplow scrapes softer and never bites; a stride
# scrapes not at all.

const DT: float = 1.0 / 120.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _sound: SkaterSoundController = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 15.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))
	_sound = SkaterSoundController.new()
	_skater.add_child(_sound)
	_sound.setup(_skater, _controller)
	_sound.set_process(false)


# Skates `ticks` of `move` (brake held if asked) and returns [bites, the loudest
# scrape level, ticks the scrape played].
func _skate(ticks: int, move: Vector2, brake: bool) -> Array:
	var input := InputState.new()
	var bites: int = 0
	var loudest: float = -INF
	var scraping: int = 0
	var was_biting: bool = _sound._brake_player.playing
	for _i: int in ticks:
		input.move_vector = move
		input.brake = brake
		input.mouse_world_pos = _skater.global_position + Vector3(0.0, -_skater.global_position.y, -6.0)
		input.delta = DT
		_controller._process_input(input, DT)
		_skater.global_position += _skater.velocity * DT
		_skater._process(DT)
		_sound._process(DT)
		var biting: bool = _sound._brake_player.playing
		if biting and not was_biting:
			bites += 1
		was_biting = biting
		if _sound._scrape_player.playing:
			scraping += 1
			loudest = maxf(loudest, _sound._scrape_db)
	return [bites, loudest, scraping]


func test_a_stop_bites_once_and_scrapes_until_it_has_stopped() -> void:
	_skate(300, Vector2(0.0, -1.0), false)
	var stop: Array = _skate(240, Vector2.ZERO, true)
	var after: Array = _skate(60, Vector2.ZERO, true)
	gut.p("stop: %d bites, loudest scrape %.1f dB, scraped %d ticks; after: %d ticks"
			% [stop[0], stop[1], stop[2], after[2]])
	assert_eq(stop[0], 1, "one bite as the stop digs in")
	assert_gt(stop[1], -6.0, "a stop from speed scrapes loud")
	assert_gt(stop[2], 30, "and holds it while it sheds speed")
	assert_eq(after[2], 0, "a stopped skater scrapes nothing")


func test_a_stride_does_not_scrape() -> void:
	var stride: Array = _skate(360, Vector2(0.0, -1.0), false)
	assert_eq(stride[0], 0, "no bite")
	assert_eq(stride[2], 0, "no scrape")


func test_the_skid_scrapes_softer_than_the_stop_and_does_not_bite() -> void:
	_skate(300, Vector2(0.0, -1.0), false)
	var skid: Array = _skate(30, Vector2(0.0, 1.0), false)
	gut.p("skid: %d bites, loudest scrape %.1f dB" % [skid[0], skid[1]])
	assert_eq(skid[0], 0, "a skid does not bite")
	assert_gt(skid[2], 0, "it scrapes")


func test_the_scrape_follows_the_speed_shed() -> void:
	var stop := Vector2(1.0, 0.0)
	assert_eq(SkaterSoundController.scrape_volume_db(Vector2.ZERO, 8.0), -INF, "nothing shed, no scrape")
	assert_eq(SkaterSoundController.scrape_volume_db(stop, 0.0), -INF, "nothing to shed at rest")
	assert_gt(SkaterSoundController.scrape_volume_db(stop, 6.0),
			SkaterSoundController.scrape_volume_db(stop, 2.0), "faster is louder")
	assert_gt(SkaterSoundController.scrape_volume_db(stop, 6.0),
			SkaterSoundController.scrape_volume_db(Vector2(0.0, 1.0), 6.0), "the stop over the skid")
