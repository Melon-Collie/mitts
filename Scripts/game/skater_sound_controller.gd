class_name SkaterSoundController
extends Node

# Tunable thresholds
const _SKATE_START_SPEED: float = 0.5      # m/s XZ to start loop
const _SKATE_MAX_SPEED: float = 10.0       # m/s XZ for full volume
const _SKATE_MIN_VOL_DB: float = -24.0
const _SKATE_MAX_VOL_DB: float = 0.0
const _SKATE_MIN_PITCH: float = 0.85
const _SKATE_MAX_PITCH: float = 1.15

const _BRAKE_DECEL_THRESHOLD: float = 4.0  # m/s drop per second to trigger
const _BRAKE_MIN_SPEED: float = 1.5        # must be moving this fast before decel

const _CARVE_ANGULAR_THRESHOLD: float = 1.8  # rad/s to start carve loop
const _CARVE_STOP_ANGULAR: float = 0.8       # rad/s to stop

var _skater: CharacterBody3D = null
var _skate_player: AudioStreamPlayer3D = null
var _brake_player: AudioStreamPlayer3D = null
var _carve_player: AudioStreamPlayer3D = null

var _prev_speed: float = 0.0
var _prev_facing: Vector2 = Vector2.ZERO
var _angular_vel: float = 0.0
var _carving: bool = false


func setup(skater: CharacterBody3D) -> void:
	_skater = skater
	_skate_player = _make_loop_player("res://Sounds/skate_loop.ogg")
	_brake_player = _make_oneshot_player("res://Sounds/skate_brake.ogg")
	_carve_player = _make_loop_player("res://Sounds/skate_carve.ogg")


func _make_loop_player(path: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Master"
	p.max_distance = 35.0
	p.unit_size = 5.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _make_oneshot_player(path: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Master"
	p.max_distance = 35.0
	p.unit_size = 5.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	if _skater == null:
		return

	var vel: Vector3 = _skater.velocity
	var speed: float = Vector2(vel.x, vel.z).length()

	_update_skate_loop(speed)
	_update_brake(speed, delta)
	_update_carve(delta)

	_prev_speed = speed


func _update_skate_loop(speed: float) -> void:
	if _skate_player.stream == null:
		return
	if speed > _SKATE_START_SPEED:
		var t: float = clampf(
			(speed - _SKATE_START_SPEED) / (_SKATE_MAX_SPEED - _SKATE_START_SPEED), 0.0, 1.0)
		_skate_player.volume_db = lerpf(_SKATE_MIN_VOL_DB, _SKATE_MAX_VOL_DB, t)
		_skate_player.pitch_scale = lerpf(_SKATE_MIN_PITCH, _SKATE_MAX_PITCH, t)
		if not _skate_player.playing:
			_skate_player.play()
	else:
		if _skate_player.playing:
			_skate_player.stop()


func _update_brake(speed: float, delta: float) -> void:
	if _brake_player.stream == null or _brake_player.playing:
		return
	if delta <= 0.0:
		return
	var decel: float = (_prev_speed - speed) / delta
	if _prev_speed >= _BRAKE_MIN_SPEED and decel >= _BRAKE_DECEL_THRESHOLD:
		_brake_player.global_position = _skater.global_position
		_brake_player.play()


func _update_carve(delta: float) -> void:
	if _carve_player.stream == null:
		return
	if delta <= 0.0:
		return

	var facing: Vector2 = _skater.get_facing() if _skater.has_method("get_facing") else Vector2.ZERO
	if _prev_facing != Vector2.ZERO and facing != Vector2.ZERO:
		# Cross product magnitude gives signed angular velocity
		var cross: float = _prev_facing.x * facing.y - _prev_facing.y * facing.x
		var angle_delta: float = clampf(asin(clampf(cross, -1.0, 1.0)), -PI, PI)
		_angular_vel = absf(angle_delta / delta)
	_prev_facing = facing

	var speed: float = Vector2(_skater.velocity.x, _skater.velocity.z).length()
	var fast_enough: bool = speed > _SKATE_START_SPEED

	if not _carving and _angular_vel >= _CARVE_ANGULAR_THRESHOLD and fast_enough:
		_carving = true
		_carve_player.play()
	elif _carving and (_angular_vel < _CARVE_STOP_ANGULAR or not fast_enough):
		_carving = false
		_carve_player.stop()
