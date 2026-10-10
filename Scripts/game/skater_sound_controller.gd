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
# The glide's hiss is the runners sliding, so it follows speed, full at this,
# and is given up by the share of the legs turned across into a stop.
const _GLIDE_FULL_SPEED: float = 10.0
# The carve is an edge holding a curve: the share of its grip the curve uses
# (the gait's turn load), times speed against the speed it is full at. A held
# edge brightens as it loads.
const _CARVE_FULL_SPEED: float = 8.0
const _CARVE_PITCH_RISE: float = 0.08
# A held loop below this stops.
const _LOOP_FLOOR_DB: float = -30.0
const _LEVEL_EPSILON_DB: float = 0.1
const _PITCH_EPSILON: float = 0.002
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
var _glide_player: AudioStreamPlayer3D = null
var _carve_player: AudioStreamPlayer3D = null
var _bite_armed: bool = true
# One per skate, so a push never cuts off the other foot's tail.
var _push_players: Array[AudioStreamPlayer3D] = []


func setup(skater: Skater, controller: SkaterController) -> void:
	_skater = skater
	_controller = controller
	_brake_player = _make_player("res://Sounds/skate_brake.wav")
	_brake_player.volume_db = SoundManager.level_db(SoundManager.Sound.SKATE_BRAKE)
	_scrape_player = _make_player("res://Sounds/skate_scrape.wav")
	_glide_player = _make_player("res://Sounds/skate_glide.wav")
	_carve_player = _make_player("res://Sounds/skate_carve.wav")
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


# The glide's level at `speed` (m/s) with the stop's weight `stop`.
static func glide_volume_db(speed: float, stop: float) -> float:
	var amount: float = clampf(speed / _GLIDE_FULL_SPEED, 0.0, 1.0) * (1.0 - clampf(stop, 0.0, 1.0))
	return linear_to_db(amount) if amount > 0.0 else -INF


# The carve's level for the gait's turn load (0..1) at `speed` (m/s).
static func carve_volume_db(turn_load: float, speed: float) -> float:
	var amount: float = clampf(turn_load, 0.0, 1.0) * clampf(speed / _CARVE_FULL_SPEED, 0.0, 1.0)
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
	var heard: Vector3 = _controller.skate_sound()
	_update_bite(heard.x, speed)
	_hold_loop(_scrape_player, SoundManager.Sound.SKATE_SCRAPE,
			scrape_volume_db(Vector2(heard.x, heard.y), speed))
	_hold_loop(_glide_player, SoundManager.Sound.SKATE_GLIDE, glide_volume_db(speed, heard.x))
	if _hold_loop(_carve_player, SoundManager.Sound.SKATE_CARVE, carve_volume_db(heard.z, speed)):
		var pitch: float = 1.0 + _CARVE_PITCH_RISE * clampf(heard.z, 0.0, 1.0)
		if absf(pitch - _carve_player.pitch_scale) > _PITCH_EPSILON:
			_carve_player.pitch_scale = pitch


# Once per stop, as its weight passes half: re-armed when the stop lets go.
func _update_bite(stop: float, speed: float) -> void:
	if stop < _BITE_WEIGHT:
		_bite_armed = true
		return
	if _bite_armed and speed >= _BITE_MIN_SPEED and _brake_player.stream != null:
		_brake_player.play()
	_bite_armed = false


# Plays `player`'s loop at the cue's level plus `level_db`, or stops it under
# the floor; true while it plays.
func _hold_loop(player: AudioStreamPlayer3D, sound: SoundManager.Sound, level_db: float) -> bool:
	if player.stream == null:
		return false
	if level_db < _LOOP_FLOOR_DB:
		if player.playing:
			player.stop()
		return false
	var db: float = SoundManager.level_db(sound) + level_db
	# Guarded: the setter pushes through to the audio server, and a held loop
	# would re-send identical values every frame.
	if absf(db - player.volume_db) > _LEVEL_EPSILON_DB:
		player.volume_db = db
	if not player.playing:
		player.play()
	return true
