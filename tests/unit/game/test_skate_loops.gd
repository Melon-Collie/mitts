extends GutTest

# The skating's held sounds follow the gait (SkaterController.skate_sound). The
# stop: one bite as the blades dig in, then a scrape held as long as they shed
# speed, louder the faster; the skid's snowplow scrapes softer and never bites.
# The glide hisses with speed and gives way to the stop. The carve sounds while
# an edge holds a curve and not on a straight line.

const DT: float = 1.0 / 120.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


# What one loop did over a run: its loudest level over the cue's own, and the
# ticks it played.
class Heard:
	var loudest: float = -INF
	var ticks: int = 0

	func sample(player: AudioStreamPlayer3D, sound: SoundManager.Sound) -> void:
		if player.playing:
			ticks += 1
			loudest = maxf(loudest, player.volume_db - SoundManager.level_db(sound))


var _skater: Skater = null
var _controller: SkaterController = null
var _sound: SkaterSoundController = null
var bites: int = 0
var scrape: Heard = null
var glide: Heard = null
var carve: Heard = null


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


# Skates `ticks` of `move` (brake held if asked), looking 6 m ahead along
# travel, and records what was heard. `arc` instead holds the stick square
# across travel to the right, the coasting carve.
func _skate(ticks: int, move: Vector2, brake: bool = false, arc: bool = false) -> void:
	var input := InputState.new()
	bites = 0
	scrape = Heard.new()
	glide = Heard.new()
	carve = Heard.new()
	var was_biting: bool = _sound._brake_player.playing
	for _i: int in ticks:
		var travel := Vector2(_skater.velocity.x, _skater.velocity.z)
		var ahead: Vector2 = travel.normalized() if travel.length() > 0.5 else Vector2(0.0, -1.0)
		input.move_vector = Vector2(-ahead.y, ahead.x) if arc else move
		input.brake = brake
		input.mouse_world_pos = Vector3(_skater.global_position.x + ahead.x * 6.0, 0.0,
				_skater.global_position.z + ahead.y * 6.0)
		input.delta = DT
		_controller._process_input(input, DT)
		_skater.global_position += _skater.velocity * DT
		_skater._process(DT)
		_sound._process(DT)
		var biting: bool = _sound._brake_player.playing
		if biting and not was_biting:
			bites += 1
		was_biting = biting
		scrape.sample(_sound._scrape_player, SoundManager.Sound.SKATE_SCRAPE)
		glide.sample(_sound._glide_player, SoundManager.Sound.SKATE_GLIDE)
		carve.sample(_sound._carve_player, SoundManager.Sound.SKATE_CARVE)


func test_a_stop_bites_once_and_scrapes_until_it_has_stopped() -> void:
	_skate(300, Vector2(0.0, -1.0))
	_skate(240, Vector2.ZERO, true)
	var stop_bites: int = bites
	var stop_scrape: Heard = scrape
	_skate(60, Vector2.ZERO, true)
	gut.p("stop: %d bites, loudest scrape %.1f dB, scraped %d ticks; after: %d ticks"
			% [stop_bites, stop_scrape.loudest, stop_scrape.ticks, scrape.ticks])
	assert_eq(stop_bites, 1, "one bite as the stop digs in")
	assert_gt(stop_scrape.loudest, -6.0, "a stop from speed scrapes loud")
	assert_gt(stop_scrape.ticks, 30, "and holds it while it sheds speed")
	assert_eq(scrape.ticks, 0, "a stopped skater scrapes nothing")
	assert_eq(glide.ticks, 0, "nor glides")


func test_a_stride_glides_and_neither_scrapes_nor_carves() -> void:
	_skate(360, Vector2(0.0, -1.0))
	gut.p("stride: glide %.1f dB over %d ticks, carve %d ticks"
			% [glide.loudest, glide.ticks, carve.ticks])
	assert_eq(bites, 0, "no bite")
	assert_eq(scrape.ticks, 0, "no scrape")
	assert_eq(carve.ticks, 0, "no carve on a straight line")
	assert_gt(glide.loudest, -6.0, "the glide hisses at speed")


func test_the_skid_scrapes_softer_than_the_stop_and_does_not_bite() -> void:
	_skate(300, Vector2(0.0, -1.0))
	_skate(30, Vector2(0.0, 1.0))
	gut.p("skid: %d bites, loudest scrape %.1f dB" % [bites, scrape.loudest])
	assert_eq(bites, 0, "a skid does not bite")
	assert_gt(scrape.ticks, 0, "it scrapes")


func test_a_held_curve_carves() -> void:
	_skate(300, Vector2(0.0, -1.0))
	_skate(120, Vector2.ZERO, false, true)
	gut.p("carve: loudest %.1f dB over %d of 120 ticks, pitch %.3f"
			% [carve.loudest, carve.ticks, _sound._carve_player.pitch_scale])
	assert_gt(carve.ticks, 60, "the edge is heard through the curve")
	assert_gt(carve.loudest, -12.0, "loaded, and loud with it")
	assert_gt(_sound._carve_player.pitch_scale, 1.0, "a loaded edge brightens")


func test_the_scrape_follows_the_speed_shed() -> void:
	var stop := Vector2(1.0, 0.0)
	assert_eq(SkaterSoundController.scrape_volume_db(Vector2.ZERO, 8.0), -INF, "nothing shed, no scrape")
	assert_eq(SkaterSoundController.scrape_volume_db(stop, 0.0), -INF, "nothing to shed at rest")
	assert_gt(SkaterSoundController.scrape_volume_db(stop, 6.0),
			SkaterSoundController.scrape_volume_db(stop, 2.0), "faster is louder")
	assert_gt(SkaterSoundController.scrape_volume_db(stop, 6.0),
			SkaterSoundController.scrape_volume_db(Vector2(0.0, 1.0), 6.0), "the stop over the skid")


func test_the_glide_follows_speed_and_gives_way_to_the_stop() -> void:
	assert_eq(SkaterSoundController.glide_volume_db(0.0, 0.0), -INF, "silent at rest")
	assert_gt(SkaterSoundController.glide_volume_db(8.0, 0.0),
			SkaterSoundController.glide_volume_db(3.0, 0.0), "faster is louder")
	assert_eq(SkaterSoundController.glide_volume_db(8.0, 1.0), -INF, "a full stop is all scrape")


func test_the_carve_follows_the_edge_load() -> void:
	assert_eq(SkaterSoundController.carve_volume_db(0.0, 8.0), -INF, "a straight line carves nothing")
	assert_gt(SkaterSoundController.carve_volume_db(0.8, 8.0),
			SkaterSoundController.carve_volume_db(0.3, 8.0), "a loaded edge is louder")
	assert_gt(SkaterSoundController.carve_volume_db(0.8, 8.0),
			SkaterSoundController.carve_volume_db(0.8, 3.0), "and faster is louder")
