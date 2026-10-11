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
# holds at full. A start's dig is measured the same way.
const _PUSH_FULL_STRENGTH: float = 1.0
const _PUSH_FLOOR_DB: float = -14.0
const _STEP_PITCH_VARIANCE: float = 0.04
# A landing's level follows how high the skate stepped: full at a crossover's
# over-step, a stride's recovery a few dB under it.
const _TOUCH_FULL_LIFT_M: float = 0.03
const _TOUCH_FLOOR_DB: float = -18.0
# Everyone else's steps and beds sit this far under the local skater's own, so
# the player's own stroke is the one in front; a stop is an event and plays
# full whoever makes it.
const _OTHERS_DB: float = -6.0

# The held loops, indexed as their players and their slots in _heard.
enum Loop { SCRAPE, GLIDE, CARVE }
const _LOOP_SOUNDS: Array[SoundManager.Sound] = [SoundManager.Sound.SKATE_SCRAPE,
		SoundManager.Sound.SKATE_GLIDE, SoundManager.Sound.SKATE_CARVE]
const _LOOP_PATHS: Array[String] = ["res://Sounds/skate_scrape.wav", "res://Sounds/skate_glide.wav",
		"res://Sounds/skate_carve.wav"]
# Held loops run as long as the gait holds them, so across a lobby they are the
# voices that pile up (three a skater, ten skaters in 5v5). Only the loudest
# this many at the listener play; a playing loop counts this much louder in the
# ranking, so two near-equal loops do not trade places every frame.
const _HELD_LOOP_BUDGET: int = 8
const _BUDGET_HOLD_DB: float = 3.0

# How loud each skater's held loops arrive at the listener, written each frame
# by their own controller and read by everyone's: Loop.size() entries a slot,
# −INF for a loop not wanted.
static var _heard: PackedFloat32Array = PackedFloat32Array()
static var _free_slots: Array[int] = []

var _skater: Skater = null
var _controller: SkaterController = null
var _slot: int = -1
var _brake_player: AudioStreamPlayer3D = null
var _loops: Array[AudioStreamPlayer3D] = []
var _bite_armed: bool = true
# One per skate for its steps — the push, the start's dig, the landing — so a
# step never cuts off the other foot's tail.
var _foot_players: Array[AudioStreamPlayer3D] = []


func setup(skater: Skater, controller: SkaterController) -> void:
	_skater = skater
	_controller = controller
	_brake_player = _make_player("res://Sounds/skate_brake.wav")
	_brake_player.volume_db = SoundManager.level_db(SoundManager.Sound.SKATE_BRAKE)
	for path: String in _LOOP_PATHS:
		_loops.append(_make_player(path))
	_foot_players = [_make_player(""), _make_player("")]
	skater.carry_caught.connect(_on_carry_caught)
	skater.skate_pushed.connect(_on_skate_pushed)
	skater.skate_touched.connect(_on_skate_touched)


func _enter_tree() -> void:
	if not _free_slots.is_empty():
		_slot = _free_slots.pop_back()
		return
	_slot = _heard.size() / Loop.size()
	for _i: int in Loop.size():
		_heard.append(-INF)


func _exit_tree() -> void:
	for k: int in Loop.size():
		_heard[_slot * Loop.size() + k] = -INF
	_free_slots.append(_slot)
	_slot = -1


# The puck strikes the blade at about the stroke's speed, so the tap's amplitude
# follows it, full at the stroke speed the carry model calls a full push.
static func tap_volume_db(stroke_speed: float, full_stroke_speed: float) -> float:
	return clampf(linear_to_db(maxf(stroke_speed, 0.0) / full_stroke_speed), _TAP_FLOOR_DB, 0.0)


static func push_volume_db(strength: float) -> float:
	return clampf(linear_to_db(maxf(strength, 0.0) / _PUSH_FULL_STRENGTH), _PUSH_FLOOR_DB, 0.0)


static func touch_volume_db(lift_m: float) -> float:
	return clampf(linear_to_db(maxf(lift_m, 0.0) / _TOUCH_FULL_LIFT_M), _TOUCH_FLOOR_DB, 0.0)


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


# Whether `entry` is among the `budget` loudest of `heard`, a tie going to the
# lower index.
static func within_budget(heard: PackedFloat32Array, entry: int, budget: int) -> bool:
	var level: float = heard[entry]
	var louder: int = 0
	for i: int in heard.size():
		if heard[i] > level or (heard[i] == level and i < entry):
			louder += 1
			if louder >= budget:
				return false
	return true


func _on_carry_caught(stroke_speed: float) -> void:
	SoundManager.play_world(SoundManager.Sound.STICK_TAP, _skater.get_blade_contact_global(),
			tap_volume_db(stroke_speed, _skater.carry_stroke_full_speed), 0.06)


# A start's first pushes are digs, short and hard, while the dig outweighs the
# stroke; then the stride's own push.
func _on_skate_pushed(left: bool, strength: float, dig: float) -> void:
	if dig > strength:
		_step(left, SoundManager.Sound.SKATE_DIG, push_volume_db(dig))
	else:
		_step(left, SoundManager.Sound.SKATE_PUSH, push_volume_db(strength))


func _on_skate_touched(left: bool, lift: float) -> void:
	_step(left, SoundManager.Sound.SKATE_TOUCH, touch_volume_db(lift))


# Sounds from the skate that stepped, where the gait draws it.
func _step(left: bool, sound: SoundManager.Sound, level_db: float) -> void:
	var p: AudioStreamPlayer3D = _foot_players[0 if left else 1]
	p.stream = SoundManager.take(sound)
	if p.stream == null:
		return
	p.global_position = _skater.blade_mark_position(left)
	p.volume_db = SoundManager.level_db(sound) + level_db + _own_db()
	p.pitch_scale = randf_range(1.0 - _STEP_PITCH_VARIANCE, 1.0 + _STEP_PITCH_VARIANCE)
	p.play()


func _own_db() -> float:
	return 0.0 if _skater.is_local_skater else _OTHERS_DB


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


# What the inverse-distance falloff takes off at the listener, dB, capped at the
# players' max_db as the engine caps it; nothing with no camera to hear from.
func _listener_db() -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var distance: float = cam.global_position.distance_to(_skater.global_position)
	return minf(linear_to_db(SoundManager.WORLD_UNIT_SIZE / maxf(distance, 0.01)), _brake_player.max_db)


# Render rate, the gait's own clock: the weights it reads are this frame's pass.
func _process(_delta: float) -> void:
	if _skater == null or _controller == null:
		return
	var vel: Vector3 = _skater.velocity
	var speed: float = Vector2(vel.x, vel.z).length()
	var heard: Vector3 = _controller.skate_sound()
	var listener_db: float = _listener_db()
	var own_db: float = _own_db()
	_update_bite(heard.x, speed)
	_hold_loop(Loop.SCRAPE, scrape_volume_db(Vector2(heard.x, heard.y), speed), 0.0, listener_db)
	_hold_loop(Loop.GLIDE, glide_volume_db(speed, heard.x), own_db, listener_db)
	if _hold_loop(Loop.CARVE, carve_volume_db(heard.z, speed), own_db, listener_db):
		var pitch: float = 1.0 + _CARVE_PITCH_RISE * clampf(heard.z, 0.0, 1.0)
		if absf(pitch - _loops[Loop.CARVE].pitch_scale) > _PITCH_EPSILON:
			_loops[Loop.CARVE].pitch_scale = pitch


# Once per stop, as its weight passes half: re-armed when the stop lets go.
func _update_bite(stop: float, speed: float) -> void:
	if stop < _BITE_WEIGHT:
		_bite_armed = true
		return
	if _bite_armed and speed >= _BITE_MIN_SPEED and _brake_player.stream != null:
		_brake_player.play()
	_bite_armed = false


# Plays `loop` at its cue's level plus `level_db` and `gain_db`, or stops it
# under the floor or outside the lobby's budget; true while it plays.
func _hold_loop(loop: Loop, level_db: float, gain_db: float, listener_db: float) -> bool:
	var player: AudioStreamPlayer3D = _loops[loop]
	var entry: int = _slot * Loop.size() + loop
	if player.stream == null or level_db < _LOOP_FLOOR_DB:
		_heard[entry] = -INF
		if player.playing:
			player.stop()
		return false
	var db: float = SoundManager.level_db(_LOOP_SOUNDS[loop]) + level_db + gain_db
	_heard[entry] = db + listener_db + (_BUDGET_HOLD_DB if player.playing else 0.0)
	if not within_budget(_heard, entry, _HELD_LOOP_BUDGET):
		if player.playing:
			player.stop()
		return false
	# Guarded: the setter pushes through to the audio server, and a held loop
	# would re-send identical values every frame.
	if absf(db - player.volume_db) > _LEVEL_EPSILON_DB:
		player.volume_db = db
	if not player.playing:
		player.play()
	return true
