class_name SkaterSoundController
extends Node

# Tunable thresholds
const _SKATE_START_SPEED: float = 0.5      # m/s XZ to start loop
const _SKATE_MAX_SPEED: float = 10.0       # m/s XZ for full volume
const _SKATE_MIN_VOL_DB: float = -24.0
const _SKATE_MAX_VOL_DB: float = 0.0
const _SKATE_MIN_PITCH: float = 0.85
const _SKATE_MAX_PITCH: float = 1.15

const _BRAKE_MIN_SPEED: float = 1.5        # must be moving this fast for brake sound

# Stickhandling tap, one per stroke catch. A cradle is a whisper, a hard dangle
# a crisp click. Two voices so a fast dangle's next catch never cuts the last.
const _TAP_PATH: String = "res://Sounds/stick_puck_tap.wav"
const _TAP_SOFT_DB: float = -16.0
const _TAP_HARD_DB: float = -6.0
const _TAP_PITCH_SOFT: float = 0.96
const _TAP_PITCH_HARD: float = 1.08
const _TAP_PITCH_VARIANCE: float = 0.06
const _TAP_VOICES: int = 2

# Last skate-loop blend factor pushed to the player (see _update_skate_loop).
# -1 forces the first write.
const _LEVEL_EPSILON: float = 0.002
var _skate_level: float = -1.0
var _skater: Skater = null
var _skate_player: AudioStreamPlayer3D = null
var _brake_player: AudioStreamPlayer3D = null
var _tap_player: AudioStreamPlayer3D = null


func setup(skater: Skater) -> void:
	_skater = skater
	_skate_player = _make_player("res://Sounds/skate_loop.ogg")
	_brake_player = _make_player("res://Sounds/skate_brake.wav")
	_tap_player = _make_player(_TAP_PATH)
	_tap_player.max_polyphony = _TAP_VOICES
	if _tap_player.stream != null:
		skater.carry_catch_landed.connect(_on_carry_catch_landed)


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
	if ResourceLoader.exists(path):
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
	var speed: float = Vector2(vel.x, vel.z).length()

	_update_skate_loop(speed)
	_update_brake(speed)


func _update_skate_loop(speed: float) -> void:
	if _skate_player.stream == null:
		return
	if speed > _SKATE_START_SPEED:
		var t: float = clampf(
			(speed - _SKATE_START_SPEED) / (_SKATE_MAX_SPEED - _SKATE_START_SPEED), 0.0, 1.0)
		# Guarded on the blend factor rather than the derived values: both setters
		# push through to the audio server, and a skater holding a steady speed
		# (or pinned at the 0/1 ends of the ramp) re-sent identical values every
		# frame. The epsilon is far below audible resolution on both ramps.
		if absf(t - _skate_level) > _LEVEL_EPSILON:
			_skate_level = t
			_skate_player.volume_db = lerpf(_SKATE_MIN_VOL_DB, _SKATE_MAX_VOL_DB, t)
			_skate_player.pitch_scale = lerpf(_SKATE_MIN_PITCH, _SKATE_MAX_PITCH, t)
		if not _skate_player.playing:
			_skate_player.play()
	else:
		if _skate_player.playing:
			_skate_player.stop()


func _update_brake(speed: float) -> void:
	if _brake_player.stream == null or _brake_player.playing:
		return
	if _skater.is_braking and speed >= _BRAKE_MIN_SPEED:
		_brake_player.global_position = _skater.global_position
		_brake_player.play()


func _on_carry_catch_landed(hardness: float) -> void:
	_tap_player.volume_db = lerpf(_TAP_SOFT_DB, _TAP_HARD_DB, hardness)
	_tap_player.pitch_scale = lerpf(_TAP_PITCH_SOFT, _TAP_PITCH_HARD, hardness) \
			* randf_range(1.0 - _TAP_PITCH_VARIANCE, 1.0 + _TAP_PITCH_VARIANCE)
	_tap_player.global_position = _skater.get_blade_contact_global()
	_tap_player.play()
