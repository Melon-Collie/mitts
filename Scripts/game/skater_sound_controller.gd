class_name SkaterSoundController
# Node3D, not Node: a 3D player only inherits its parent's transform through a
# Node3D chain, so under a plain Node every stride would sound from the origin.
extends Node3D

# The stop's bite: the blades turned across and dug in, which is the stop's
# weight passing half, and only when there is speed to shed.
const _BITE_WEIGHT: float = 0.5
const _BITE_MIN_SPEED: float = 1.5
# The scrape's amplitude is the share of the legs shedding speed — the stop
# whole, the skid's snowplow at this share — times the speed being shed,
# against the speed it is full at; below the floor it stops.
const _SKID_SCRAPE_SHARE: float = 0.5
const _SCRAPE_FULL_SPEED: float = 8.0
const _SCRAPE_FLOOR_DB: float = -30.0
const _LEVEL_EPSILON_DB: float = 0.1
# Where the softest stickhandling tap bottoms out.
const _TAP_FLOOR_DB: float = -12.0
# A push's level follows the stroke's strength (Skater.skate_pushed), full at
# this — a flat-out stride — and no quieter than the floor; a hard drive past it
# holds at full.
const _PUSH_FULL_STRENGTH: float = 1.0
const _PUSH_FLOOR_DB: float = -14.0
const _PUSH_PITCH_VARIANCE: float = 0.04

var _skater: Skater = null
var _controller: SkaterController = null
var _brake_player: AudioStreamPlayer3D = null
var _scrape_player: AudioStreamPlayer3D = null
var _scrape_db: float = -INF
var _bite_armed: bool = true
# One per skate, so a push never cuts off the other foot's tail.
var _push_players: Array[AudioStreamPlayer3D] = []


func setup(skater: Skater, controller: SkaterController) -> void:
	_skater = skater
	_controller = controller
	_brake_player = _make_player("res://Sounds/skate_brake.wav")
	_brake_player.volume_db = SoundManager.level_db(SoundManager.Sound.SKATE_BRAKE)
	_scrape_player = _make_player("res://Sounds/skate_scrape.wav")
	_push_players = [_make_player(""), _make_player("")]
	skater.carry_caught.connect(_on_carry_caught)
	skater.skate_pushed.connect(_on_skate_pushed)


# The puck strikes the blade at about the stroke's speed, so the tap's amplitude
# follows it, full at the stroke speed the carry model calls a full push.
static func tap_volume_db(stroke_speed: float, full_stroke_speed: float) -> float:
	return clampf(linear_to_db(maxf(stroke_speed, 0.0) / full_stroke_speed), _TAP_FLOOR_DB, 0.0)


static func push_volume_db(strength: float) -> float:
	return clampf(linear_to_db(maxf(strength, 0.0) / _PUSH_FULL_STRENGTH), _PUSH_FLOOR_DB, 0.0)


# The scrape's level for the gait's (stop, skid) weights at `speed` (m/s): −INF
# when nothing is being shed.
static func scrape_volume_db(scrape: Vector2, speed: float) -> float:
	var amount: float = (scrape.x + _SKID_SCRAPE_SHARE * scrape.y) \
			* clampf(speed / _SCRAPE_FULL_SPEED, 0.0, 1.0)
	return linear_to_db(amount) if amount > 0.0 else -INF


func _on_carry_caught(stroke_speed: float) -> void:
	SoundManager.play_world(SoundManager.Sound.STICK_TAP, _skater.get_blade_contact_global(),
			tap_volume_db(stroke_speed, _skater.carry_stroke_full_speed), 0.06)


# Sounds from the skate that bit, where the gait draws it.
func _on_skate_pushed(left: bool, strength: float) -> void:
	var p: AudioStreamPlayer3D = _push_players[0 if left else 1]
	p.stream = SoundManager.take(SoundManager.Sound.SKATE_PUSH)
	if p.stream == null:
		return
	p.global_position = _skater.blade_mark_position(left)
	p.volume_db = SoundManager.level_db(SoundManager.Sound.SKATE_PUSH) + push_volume_db(strength)
	p.pitch_scale = randf_range(1.0 - _PUSH_PITCH_VARIANCE, 1.0 + _PUSH_PITCH_VARIANCE)
	p.play()


# A skater's own emitters are ordinary world sounds — same SFX bus, so the SFX
# slider governs them like everything else on the sheet, and the same falloff
# constants, so a stride and the puck it is chasing fade together. Both are read
# from SoundManager rather than copied: a second set of numbers here is a second
# audible distance, which is the inconsistency this is fixing.
func _make_player(path: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.max_distance = SoundManager.NO_DISTANCE_CUTOFF
	p.unit_size = SoundManager.WORLD_UNIT_SIZE
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if path != "" and ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


# Render rate, the gait's own clock: the weights it reads are this frame's pass.
func _process(_delta: float) -> void:
	if _skater == null or _controller == null:
		return
	var vel: Vector3 = _skater.velocity
	var speed: float = Vector2(vel.x, vel.z).length()
	var scrape: Vector2 = _controller.skate_scrape()
	_update_bite(scrape.x, speed)
	_update_scrape(scrape_volume_db(scrape, speed))


# Once per stop, as its weight passes half: re-armed when the stop lets go.
func _update_bite(stop: float, speed: float) -> void:
	if stop < _BITE_WEIGHT:
		_bite_armed = true
		return
	if _bite_armed and speed >= _BITE_MIN_SPEED and _brake_player.stream != null:
		_brake_player.play()
	_bite_armed = false


func _update_scrape(level_db: float) -> void:
	if _scrape_player.stream == null:
		return
	if level_db < _SCRAPE_FLOOR_DB:
		if _scrape_player.playing:
			_scrape_player.stop()
		_scrape_db = -INF
		return
	# Guarded: the setter pushes through to the audio server, and a held stop
	# re-sent identical values every frame.
	if absf(level_db - _scrape_db) > _LEVEL_EPSILON_DB:
		_scrape_db = level_db
		_scrape_player.volume_db = SoundManager.level_db(SoundManager.Sound.SKATE_SCRAPE) + level_db
	if not _scrape_player.playing:
		_scrape_player.play()
