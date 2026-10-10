class_name SkaterSoundController
# Node3D, not Node: a 3D player only inherits its parent's transform through a
# Node3D chain, so under a plain Node every stride would sound from the origin.
extends Node3D

const _BRAKE_MIN_SPEED: float = 1.5        # must be moving this fast for brake sound
# Where the softest stickhandling tap bottoms out.
const _TAP_FLOOR_DB: float = -12.0
# A push's level follows the stroke's strength (Skater.skate_pushed), full at
# this — a flat-out stride — and no quieter than the floor; a hard drive past it
# holds at full.
const _PUSH_FULL_STRENGTH: float = 1.0
const _PUSH_FLOOR_DB: float = -14.0
const _PUSH_PITCH_VARIANCE: float = 0.04

var _skater: Skater = null
var _brake_player: AudioStreamPlayer3D = null
# One per skate, so a push never cuts off the other foot's tail.
var _push_players: Array[AudioStreamPlayer3D] = []


func setup(skater: Skater) -> void:
	_skater = skater
	_brake_player = _make_player("res://Sounds/skate_brake.wav")
	_brake_player.volume_db = SoundManager.level_db(SoundManager.Sound.SKATE_BRAKE)
	_push_players = [_make_player(""), _make_player("")]
	skater.carry_caught.connect(_on_carry_caught)
	skater.skate_pushed.connect(_on_skate_pushed)


# The puck strikes the blade at about the stroke's speed, so the tap's amplitude
# follows it, full at the stroke speed the carry model calls a full push.
static func tap_volume_db(stroke_speed: float, full_stroke_speed: float) -> float:
	return clampf(linear_to_db(maxf(stroke_speed, 0.0) / full_stroke_speed), _TAP_FLOOR_DB, 0.0)


static func push_volume_db(strength: float) -> float:
	return clampf(linear_to_db(maxf(strength, 0.0) / _PUSH_FULL_STRENGTH), _PUSH_FLOOR_DB, 0.0)


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


# Render rate, not the physics tick: this drives audio only, and it ran per
# skater per tick. Braking is a held action lasting hundreds of ms, so the brake
# trigger losing sub-frame precision is inaudible.
func _process(_delta: float) -> void:
	if _skater == null:
		return
	var vel: Vector3 = _skater.velocity
	_update_brake(Vector2(vel.x, vel.z).length())


func _update_brake(speed: float) -> void:
	if _brake_player.stream == null or _brake_player.playing:
		return
	if _skater.is_braking and speed >= _BRAKE_MIN_SPEED:
		_brake_player.play()
