class_name LobbyArenaBackdrop
extends Node3D

# Live 3D arena behind the lobby panel: the real RinkArena scene (rink,
# stands, crowd, lights) with a slowly drifting camera. The crowd's fan mix
# re-tints as the lobby's
# team colors resolve (set_team_color_slots), so color votes repaint the
# bowl live, and the roster sits on the benches as itself (set_benches). PlayerPrefs.apply_video() is re-applied once the arena
# lands so the user's GI / crowd-density / shadow options carry into the
# lobby.

const _ARENA_SCENE_PATH: String = "res://Scenes/RinkArena.tscn"

# Camera path: a slow elliptical drift inside the bowl, matched to the rink's
# 60×26 footprint so the framing keeps a similar distance to the near boards
# all the way around. One lap ≈ 3.5 minutes — present, never distracting.
const _ORBIT_RADIUS_X: float = 16.0
const _ORBIT_RADIUS_Z: float = 22.0
const _ORBIT_HEIGHT: float = 8.5
const _ORBIT_SPEED: float = 0.03  # rad/s
const _LOOK_TARGET: Vector3 = Vector3(0.0, 1.2, 0.0)
const _CAMERA_FOV: float = 65.0

# Center-to-center spacing of seated players along the bench. 5 players
# (a full 5v5 side) at this spacing spans 4.2 m of the 6 m bench.
const _SEAT_SPACING: float = 1.05
# A figure faces −Z; the benches face the ice along −X.
const _FACE_THE_ICE: float = PI * 0.5

var _camera: Camera3D = null
var _stands: ArenaStands = null
var _jumbotron: Jumbotron = null
var _orbit_angle: float = 0.0
var _home_slot: int = -1
var _away_slot: int = -1

# One seated LockerMannequin per fielded lobby slot, on that team's bench: the
# player in the team kit — their lettering, build, skin and gear picks. Rebuilt
# when who sits there, as whom, or the resolved team colors change.
var _benches_root: Node3D = null
var _benches: Array = [[], []]
var _bench_key: String = ""


func _ready() -> void:
	var arena_scene: PackedScene = load(_ARENA_SCENE_PATH)
	var arena: Node3D = arena_scene.instantiate() as Node3D
	add_child(arena)
	_stands = arena.find_child("ArenaStands", false, false) as ArenaStands
	# The backdrop's arena has no live match behind it: pin the jumbotron to
	# its attract screen (wordmark + the lobby's team colors, re-tinted below).
	_jumbotron = arena.find_child("Jumbotron", false, false) as Jumbotron
	if _jumbotron != null:
		_jumbotron.lock_attract()
	_camera = Camera3D.new()
	_camera.fov = _CAMERA_FOV
	add_child(_camera)
	_update_camera(0.0)
	_camera.current = true
	# Deferred: apply_video reads the main loop's current_scene, which isn't
	# assigned yet while the lobby scene's children are still in _ready().
	PlayerPrefs.call_deferred(&"apply_video")


func _process(delta: float) -> void:
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	_orbit_angle = fmod(_orbit_angle + _ORBIT_SPEED * delta, TAU)
	_camera.position = Vector3(
			cos(_orbit_angle) * _ORBIT_RADIUS_X,
			_ORBIT_HEIGHT,
			sin(_orbit_angle) * _ORBIT_RADIUS_Z)
	_camera.look_at(_LOOK_TARGET)


# Re-tint the crowd/benches to the lobby's currently-resolved color slots.
# ArenaStands.setup() is a full bowl rebuild, so skip when nothing changed —
# the lobby calls this from _refresh_grid, which also fires on ready toggles
# and roster churn that leave the colors alone.
func set_team_color_slots(home_slot: int, away_slot: int) -> void:
	if home_slot == _home_slot and away_slot == _away_slot:
		return
	_home_slot = home_slot
	_away_slot = away_slot
	if _stands == null:
		return
	var home: Dictionary = TeamColorRegistry.get_colors(home_slot, 0)
	var away: Dictionary = TeamColorRegistry.get_colors(away_slot, 1)
	_stands.setup(home.primary, home.secondary, away.primary, away.secondary)
	if _jumbotron != null:
		_jumbotron.set_team_colors(
				home.primary, home.secondary, away.primary, away.secondary)
	_rebuild_benches()


# ── Benches ──────────────────────────────────────────────────────────────────

# [home, away], each an Array of PlayerLook in seat order (LobbyBench.benches).
func set_benches(benches: Array) -> void:
	var key: String = _key_for(benches)
	if key == _bench_key and _benches_root != null:
		return
	_benches = benches
	_bench_key = key
	_rebuild_benches()


# Everything a figure is drawn from, so an unrelated lobby refresh rebuilds
# nothing.
static func _key_for(benches: Array) -> String:
	var parts: PackedStringArray = []
	for team: Array in benches:
		parts.append("|")
		for look: PlayerLook in team:
			parts.append("%s#%d%s:%s:%d:%d:%d" % [look.player_name, look.jersey_number,
					"L" if look.is_left_handed else "R", str(look.attributes.to_dict()),
					look.skin_tone, look.tape_code, look.gear_style_code])
	return ",".join(parts)


func _rebuild_benches() -> void:
	if _stands == null or _home_slot < 0:
		return
	if _benches_root != null:
		_benches_root.queue_free()
	_benches_root = Node3D.new()
	_benches_root.name = "Benches"
	add_child(_benches_root)
	for team_id: int in 2:
		var looks: Array = _benches[team_id]
		var colors: Dictionary = TeamColorRegistry.get_colors(
				_home_slot if team_id == 0 else _away_slot, team_id)
		var seat: Vector3 = _stands.bench_seat_center(team_id)
		for i: int in looks.size():
			var look: PlayerLook = looks[i]
			var figure := LockerMannequin.new()
			figure.seated = true
			_benches_root.add_child(figure)
			figure.position = seat + Vector3(0.0, 0.0,
					(float(i) - float(looks.size() - 1) * 0.5) * _SEAT_SPACING)
			figure.rotation.y = _FACE_THE_ICE
			figure.set_jersey_info(look.player_name, look.jersey_number)
			figure.apply(look.attributes, GearStyleConfig.from_code(look.gear_style_code),
					StickTapeConfig.from_code(look.tape_code), colors, look.skin_tone,
					look.is_left_handed)
