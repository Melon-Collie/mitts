extends Node

# Mute-on-unfocus: silence the Master bus while the OS focus is on another
# window, then restore the player's intended mute state on return. Gated by
# PlayerPrefs.mute_when_unfocused (default on). Mirrors network_manager's use
# of the WM window-focus notifications.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_apply_focus_mute(true)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_apply_focus_mute(false)


func _apply_focus_mute(unfocused: bool) -> void:
	var master: int = AudioServer.get_bus_index("Master")
	if master == -1:
		return
	if unfocused:
		if PlayerPrefs.mute_when_unfocused:
			AudioServer.set_bus_mute(master, true)
	else:
		# On focus return, restore whatever the player's Mute All setting was.
		AudioServer.set_bus_mute(master, PlayerPrefs.master_muted)


enum Sound {
	UI_HOVER,
	UI_CLICK,
	SHOT_WRISTER,
	SHOT_SLAPPER,
	PUCK_PICKUP,
	GOAL_HORN,
	SKATE_BRAKE,
	PUCK_BOARDS,
	PUCK_GOALIE,
	PUCK_POST,
	PUCK_GOAL_BODY,
	PUCK_DEFLECTION,
	PUCK_BODY_BLOCK,
	PUCK_STRIP,
	STICK_LIFT,
	PERIOD_BUZZER,
	BODY_CHECK,
	FACEOFF_WHISTLE,
	PUCK_GLASS,
	STICK_TAP,
	GOALIE_PAD_DROP,
	GOALIE_PAD_SLIDE,
	SKATE_PUSH,
	SKATE_SCRAPE,
	SKATE_GLIDE,
	SKATE_CARVE,
	SKATE_DIG,
	SKATE_TOUCH,
}

const _SOUND_PATHS: Dictionary = {
	Sound.UI_HOVER:         "res://Sounds/ui_hover.wav",
	Sound.UI_CLICK:         "res://Sounds/ui_select.wav",
	Sound.SHOT_WRISTER:     "res://Sounds/shot_wrister.ogg",
	Sound.SHOT_SLAPPER:     "res://Sounds/shot_slapper.ogg",
	Sound.PUCK_PICKUP:      "res://Sounds/puck_pickup.ogg",
	Sound.GOAL_HORN:        "res://Sounds/goal_horn.ogg",
	Sound.SKATE_BRAKE:      "res://Sounds/skate_brake.wav",
	Sound.PUCK_BOARDS:      "res://Sounds/puck_boards.wav",
	Sound.PUCK_GOALIE:      "res://Sounds/puck_goalie.wav",
	Sound.PUCK_POST:        "res://Sounds/puck_post.wav",
	Sound.PUCK_GOAL_BODY:   "res://Sounds/puck_goal_body.wav",
	Sound.PUCK_DEFLECTION:  "res://Sounds/puck_deflection.wav",
	Sound.PUCK_BODY_BLOCK:  "res://Sounds/puck_goalie.wav",
	Sound.PUCK_STRIP:       "res://Sounds/puck_strip.wav",
	Sound.STICK_LIFT:       "res://Sounds/stick_lift.wav",
	Sound.PERIOD_BUZZER:    "res://Sounds/period_buzzer.wav",
	Sound.BODY_CHECK:       "res://Sounds/body_check.ogg",
	Sound.FACEOFF_WHISTLE:  "res://Sounds/faceoff_whistle.wav",
	Sound.PUCK_GLASS:       "res://Sounds/puck_glass.wav",
	Sound.STICK_TAP:        "res://Sounds/stick_tap_%02d.wav",
	Sound.GOALIE_PAD_DROP:  "res://Sounds/goalie_pad_drop.wav",
	Sound.GOALIE_PAD_SLIDE: "res://Sounds/goalie_pad_slide.wav",
	Sound.SKATE_PUSH:       "res://Sounds/skate_push_%02d.wav",
	Sound.SKATE_SCRAPE:     "res://Sounds/skate_scrape.wav",
	Sound.SKATE_GLIDE:      "res://Sounds/skate_glide.wav",
	Sound.SKATE_CARVE:      "res://Sounds/skate_carve.wav",
	Sound.SKATE_DIG:        "res://Sounds/skate_dig_%02d.wav",
	Sound.SKATE_TOUCH:      "res://Sounds/skate_touch_%02d.wav",
}

# Cues recorded as several takes: the path above is a pattern numbered from 1,
# and each play draws a take other than the last one, so a run of the same cue
# never repeats a sample back to back.
const _TAKE_COUNTS: Dictionary = {
	Sound.STICK_TAP: 15,
	Sound.SKATE_PUSH: 6,
	Sound.SKATE_DIG: 4,
	Sound.SKATE_TOUCH: 4,
}

# Every file above is mastered to one reference loudness
# (tools/normalize_sfx.py), so this table is the mix: each cue's level against
# the others before distance and the call site's own modifiers (puck speed, shot
# power, save bumps). Arena cues play without distance falloff, while a world
# cue at the live camera's range loses about 8 dB (see WORLD_UNIT_SIZE).
const _MIX_DB: Dictionary = {
	Sound.GOAL_HORN:        4.0,
	Sound.PERIOD_BUZZER:    0.0,
	Sound.FACEOFF_WHISTLE: -2.0,
	Sound.SHOT_SLAPPER:     2.0,
	Sound.SHOT_WRISTER:     2.0,
	Sound.PUCK_BOARDS:      0.0,
	Sound.PUCK_GLASS:       0.0,
	Sound.PUCK_GOALIE:      0.0,
	Sound.PUCK_POST:        0.0,
	Sound.PUCK_GOAL_BODY:   0.0,
	Sound.PUCK_DEFLECTION:  0.0,
	Sound.PUCK_BODY_BLOCK:  0.0,
	Sound.PUCK_STRIP:       0.0,
	Sound.STICK_LIFT:       0.0,
	Sound.BODY_CHECK:       0.0,
	Sound.PUCK_PICKUP:     -6.0,
	Sound.SKATE_BRAKE:     -4.0,
	Sound.SKATE_DIG:       -4.0,
	Sound.GOALIE_PAD_DROP: -3.0,
	Sound.GOALIE_PAD_SLIDE: -4.0,
	Sound.STICK_TAP:       -6.0,
	Sound.SKATE_PUSH:      -6.0,
	Sound.SKATE_SCRAPE:    -6.0,
	Sound.SKATE_CARVE:     -8.0,
	Sound.SKATE_GLIDE:    -10.0,
	Sound.SKATE_TOUCH:    -11.0,
	Sound.UI_CLICK:       -12.0,
	Sound.UI_HOVER:       -18.0,
}

# Files the mastering left under the reference because reaching it would have
# limited their attack past normalize_sfx.MAX_LIMIT_DB; the tool's report gives
# the number when a file is re-mastered.
const _UNDER_REFERENCE_DB: Dictionary = {
	Sound.UI_CLICK:        5.0,
	Sound.PUCK_PICKUP:     2.3,
	Sound.PUCK_DEFLECTION: 6.9,
	Sound.STICK_LIFT:      6.9,
	Sound.PUCK_GOALIE:     4.1,
	Sound.PUCK_STRIP:      2.8,
	Sound.PUCK_GOAL_BODY:  1.3,
	Sound.PUCK_BODY_BLOCK: 4.1,
	Sound.PUCK_GLASS:      7.1,
	Sound.STICK_TAP:      10.0,
	Sound.GOALIE_PAD_DROP: 11.0,
	Sound.SKATE_PUSH:      4.9,
	Sound.SKATE_DIG:       3.8,
	Sound.SKATE_TOUCH:    12.8,
}

# A cue reusing another's recording, pitched to read as a different target:
# a body is a softer, heavier stop than a goalie pad.
const _BASE_PITCH: Dictionary = {
	Sound.PUCK_BODY_BLOCK: 0.85,
}

const _UI_POOL_SIZE: int = 4
const _SFX_2D_POOL_SIZE: int = 4
const _SFX_3D_POOL_SIZE: int = 12
# Arena venue one-shots (goal horn, period buzzer, faceoff whistle) route here
# so the Crowd slider governs all crowd/arena atmosphere as one group, separate
# from gameplay SFX. Sized for the game-over case where the goal horn and the
# period buzzer can overlap.
const _CROWD_POOL_SIZE: int = 4

# ONE inverse-distance falloff for every world sound, at every camera, in every
# mode — the same curve `SkaterSoundController` gives the skate loops. Two dials,
# and neither is per-camera:
#
# Unit size is where the curve is anchored, and it is anchored on the LIVE camera
# because that is the shot the game is played in: the game cam frames the puck
# from ~15 m up, so events land around -8 dB — present and clearly placed, without
# bleeding across the rink.
#
# NO distance cutoff (Godot reads 0.0 as unlimited). The rink is 60 x 26 m and the
# camera pulls back off it, so listener-to-event distances past 40 m are ordinary
# rather than exceptional — a cutoff there silenced far-side play outright instead
# of merely quieting it. Unbounded, the curve keeps falling on its own (about
# -17 dB at 40 m, -21 dB at 65 m), which is the "audible but clearly over there"
# the cutoff was destroying.
#
# The cutoff is also why this used to be three presets a camera switched between:
# with a 40 m wall in the way, the replay cams — parked 4.5-38 m out — needed
# their own wider curves to reach past it at all. Take the wall away and the
# widening has nothing left to do, and a level that changes when the direction
# stays put is its own inconsistency. Replay is quieter than it was on the old
# REPLAY_FAR preset by design: it is the distance, not a mode.
const WORLD_UNIT_SIZE: float = 6.0
const NO_DISTANCE_CUTOFF: float = 0.0

# Where a feather pass bottoms out — still audible next to the passer.
const _SHOT_VOLUME_FLOOR_DB: float = -18.0
# The launch speed a shot cue is loudest at: the league's hardest shot.
const _SHOT_FULL_POWER_M_S: float = GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S

var _streams: Dictionary = {}
var _takes: Dictionary = {}       # Sound -> Array[AudioStream], multi-take cues only
var _last_take: Dictionary = {}   # Sound -> index played last
var _pool_ui: Array[AudioStreamPlayer] = []      # UI bus — hover, click
var _pool_sfx_2d: Array[AudioStreamPlayer] = []  # SFX bus — non-spatial gameplay cues
var _pool_3d: Array[AudioStreamPlayer3D] = []    # SFX bus — all world sounds
var _pool_crowd: Array[AudioStreamPlayer] = []   # Arena bus — horn, buzzer, whistle


func _ready() -> void:
	_ensure_buses()
	# PlayerPrefs._ready() runs first (autoload order), so saved volumes were
	# applied against buses that didn't exist yet. Re-apply now that SFX / UI /
	# Crowd exist so startup volumes match the slider state.
	PlayerPrefs.apply_audio()
	_load_streams()
	_build_pools()


func _ensure_buses() -> void:
	for bus_name: String in ["SFX", "UI", "Arena"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	_ensure_master_limiter()


# Short transients mastered under the reference get make-up gain, and a world cue
# under a close replay camera skips most of the distance falloff, so peaks can
# pass full scale; the limiter catches them instead of the output clipping.
func _ensure_master_limiter() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	for i: int in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	AudioServer.add_bus_effect(master, AudioEffectHardLimiter.new())


func _load_streams() -> void:
	for sound: int in _SOUND_PATHS:
		var path: String = _SOUND_PATHS[sound]
		if _TAKE_COUNTS.has(sound):
			var takes: Array[AudioStream] = []
			for i: int in _TAKE_COUNTS[sound]:
				if ResourceLoader.exists(path % (i + 1)):
					takes.append(load(path % (i + 1)))
			if not takes.is_empty():
				_takes[sound] = takes
				_last_take[sound] = -1
		elif ResourceLoader.exists(path):
			_streams[sound] = load(path)


# The stream a cue plays next — for an emitter of its own (a skater's), drawn as
# the pools draw it.
func take(sound: Sound) -> AudioStream:
	return _stream_for(sound)


func _stream_for(sound: Sound) -> AudioStream:
	if not _takes.has(sound):
		return _streams.get(sound)
	var takes: Array[AudioStream] = _takes[sound]
	var pick: int = randi() % takes.size()
	if takes.size() > 1 and pick == _last_take[sound]:
		pick = (pick + 1 + randi() % (takes.size() - 1)) % takes.size()
	_last_take[sound] = pick
	return takes[pick]


func _build_pools() -> void:
	for i: int in _UI_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_pool_ui.append(p)
	for i: int in _SFX_2D_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_sfx_2d.append(p)
	for i: int in _SFX_3D_POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = NO_DISTANCE_CUTOFF
		p.unit_size = WORLD_UNIT_SIZE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool_3d.append(p)
	for i: int in _CROWD_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Arena"
		add_child(p)
		_pool_crowd.append(p)


func play_ui(sound: Sound, volume_db: float = 0.0, pitch_variance: float = 0.0) -> void:
	var stream: AudioStream = _stream_for(sound)
	if stream == null:
		return
	for p: AudioStreamPlayer in _pool_ui:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db + level_db(sound)
			p.pitch_scale = _BASE_PITCH.get(sound, 1.0) * (randf_range(1.0 - pitch_variance, 1.0 + pitch_variance) if pitch_variance > 0.0 else 1.0)
			p.play()
			return


func play_crowd(sound: Sound, volume_db: float = 0.0, pitch_variance: float = 0.0) -> void:
	var stream: AudioStream = _stream_for(sound)
	if stream == null:
		return
	for p: AudioStreamPlayer in _pool_crowd:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db + level_db(sound)
			p.pitch_scale = _BASE_PITCH.get(sound, 1.0) * (randf_range(1.0 - pitch_variance, 1.0 + pitch_variance) if pitch_variance > 0.0 else 1.0)
			p.play()
			return


# A full pool steals the voice furthest into its clip rather than dropping the
# new cue: in a scramble the fresh contact is the one the player is watching,
# and the oldest voice is mostly tail by then.
func play_world(sound: Sound, position: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.0, pitch_scale: float = 1.0) -> void:
	var stream: AudioStream = _stream_for(sound)
	if stream == null:
		return
	var voice: AudioStreamPlayer3D = null
	var oldest_s: float = -1.0
	for p: AudioStreamPlayer3D in _pool_3d:
		if not p.playing:
			voice = p
			break
		var played_s: float = p.get_playback_position()
		if played_s > oldest_s:
			oldest_s = played_s
			voice = p
	voice.stream = stream
	voice.volume_db = volume_db + level_db(sound)
	voice.pitch_scale = _BASE_PITCH.get(sound, 1.0) * (randf_range(1.0 - pitch_variance, 1.0 + pitch_variance) * pitch_scale if pitch_variance > 0.0 else pitch_scale)
	voice.global_position = position
	voice.play()


# The gain a cue plays at before any situational modifier: its mix level, plus
# make-up for a file mastered under the reference.
static func level_db(sound: Sound) -> float:
	return _MIX_DB[sound] + _UNDER_REFERENCE_DB.get(sound, 0.0)


# Above the dasher's cap rail the puck is striking glass, not boards.
static func board_contact_sound(contact: Vector3) -> Sound:
	return Sound.PUCK_GLASS if contact.y > GameRules.BOARD_TOP_HEIGHT else Sound.PUCK_BOARDS


# A release's amplitude scales with the puck's launch speed (m/s), so its level
# is that ratio in dB against the hardest shot in the league. Wrister and
# slapper files are mastered alike, so speed alone sets them apart. Power past
# it (a one-timer's bonus) holds at full.
static func shot_volume_db(power: float) -> float:
	return clampf(linear_to_db(maxf(power, 0.0) / _SHOT_FULL_POWER_M_S), _SHOT_VOLUME_FLOOR_DB, 0.0)


# Connects hover and click sounds to a button. Call after creating each Button node.
func wire_button(button: Button) -> void:
	button.mouse_entered.connect(func() -> void: play_ui(Sound.UI_HOVER))
	button.pressed.connect(func() -> void: play_ui(Sound.UI_CLICK))
