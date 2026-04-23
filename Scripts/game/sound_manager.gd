class_name SoundManager
extends Node

enum Sound {
	UI_HOVER,
	UI_CLICK,
	SHOT_WRISTER,
	SHOT_SLAPPER,
	PUCK_PICKUP,
	GOAL_HORN,
	SKATE_BRAKE,
	SKATE_CARVE,
}

const _SOUND_PATHS: Dictionary = {
	Sound.UI_HOVER:     "res://Sounds/ui_hover.wav",
	Sound.UI_CLICK:     "res://Sounds/ui_select.wav",
	Sound.SHOT_WRISTER: "res://Sounds/shot_wrister.ogg",
	Sound.SHOT_SLAPPER: "res://Sounds/shot_slapper.wav",
	Sound.PUCK_PICKUP:  "res://Sounds/puck_pickup.ogg",
	Sound.GOAL_HORN:    "res://Sounds/goal_horn.ogg",
	Sound.SKATE_BRAKE:  "res://Sounds/skate_brake.ogg",
	Sound.SKATE_CARVE:  "res://Sounds/skate_carve.ogg",
}

const _2D_POOL_SIZE: int = 8
const _3D_POOL_SIZE: int = 12

var _streams: Dictionary = {}          # Sound -> AudioStream
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	_load_streams()
	_build_pools()


func _load_streams() -> void:
	for sound: int in _SOUND_PATHS:
		var path: String = _SOUND_PATHS[sound]
		if ResourceLoader.exists(path):
			_streams[sound] = load(path)


func _build_pools() -> void:
	for i: int in _2D_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool_2d.append(p)
	for i: int in _3D_POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Master"
		p.max_distance = 40.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool_3d.append(p)


func play_ui(sound: Sound, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	for p: AudioStreamPlayer in _pool_2d:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return


func play_world(sound: Sound, position: Vector3, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	for p: AudioStreamPlayer3D in _pool_3d:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.global_position = position
			p.play()
			return


# Connects hover and click sounds to a button. Call after creating each Button node.
func wire_button(button: Button) -> void:
	button.mouse_entered.connect(func() -> void: play_ui(Sound.UI_HOVER))
	button.pressed.connect(func() -> void: play_ui(Sound.UI_CLICK))
