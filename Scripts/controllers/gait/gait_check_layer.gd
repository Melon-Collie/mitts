class_name GaitCheckLayer
extends GaitLayer

# Both halves of a body check. The commit: holding Hit loads the skater up —
# lean forward into it and sink a touch — off the replicated hit_committed. The
# drive: the hitter's shoulder finishing through the contact, started off the
# host-authoritative body_check_landed broadcast (and the replay event
# dispatcher), so every machine plays the identical drive the same frame as the
# burst and the thud.
#
# The gait owns no shoulder channel here, and must not grow one: the trunk
# texture is symmetric, so a roll raises the trailing shoulder by exactly what
# it drops the leading one, which is a skater tipping over rather than one
# loading up. The per-side geometry lives in CheckStanceRules, eased at physics
# rate on the skater (Skater._update_commit_stance) — the loaded blade reads it.

var _drive_dir: Vector3 = Vector3.ZERO  # world-space, attacker → victim
var _drive_t: float = -1.0              # seconds into the drive; <0 = idle
var _drive_intensity: float = 0.0       # 0..1 VFX hit hardness
var _drive_env: float = 0.0
var _commit_blend: float = 0.0


func stages() -> int:
	return Stage.HOLD | Stage.FLOOR | Stage.TRUNK


func reset() -> void:
	_drive_dir = Vector3.ZERO
	_drive_t = -1.0
	_drive_intensity = 0.0
	_drive_env = 0.0
	_commit_blend = 0.0


func is_quiet() -> bool:
	return not _skater.hit_committed and _drive_t < 0.0


# During sustained contact or a quick follow-up hit inside an active drive the
# broadcast can re-fire: harden the intensity but never restart the clock — a
# re-zeroed envelope would pin the pose at its rise for as long as the contact
# grinds.
func start_drive(hit_dir: Vector3, intensity: float) -> void:
	var flat := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if flat.length_squared() < 0.0001 or intensity <= 0.0:
		return
	if _drive_t >= 0.0:
		_drive_intensity = maxf(_drive_intensity, intensity)
		return
	_drive_dir = flat.normalized()
	_drive_intensity = intensity
	_drive_t = 0.0


func advance(delta: float) -> bool:
	# An explosive rise (peaks ~15% in) easing out over check_drive_time.
	_drive_env = 0.0
	if _drive_t >= 0.0:
		_drive_t += delta
		var du: float = _drive_t / maxf(_controller.check_drive_time, 0.001)
		if du >= 1.0:
			_drive_t = -1.0
		else:
			_drive_env = sin(PI * pow(du, 0.35)) * _drive_intensity
	_commit_blend = move_toward(_commit_blend, 1.0 if _skater.hit_committed else 0.0,
			_controller.hit_commit_pose_speed * delta)
	return _drive_env > 0.0 or _commit_blend > 0.001


# A landed check plants through the finish.
func stride_hold() -> float:
	return _drive_env * _controller.shot_stride_fade


# The drive is delivered with the LEGS — the finishing base under the shoulder.
func stance_floor() -> float:
	return _controller.check_drive_stance * _drive_env


func shape_trunk(p: GaitPose) -> void:
	# The trunk drives INTO the hit. Same directional decomposition as the reach
	# lean (pitch = mag·local.z folds toward local −Z, roll = −mag·local.x),
	# re-derived body-local each pass so the lean stays on the victim line while
	# the body carries through.
	if _drive_env > 0.0:
		var drive_local: Vector3 = _skater.global_transform.basis.inverse() * _drive_dir
		var drive_mag: float = deg_to_rad(_controller.check_drive_lean_deg) * _drive_env
		p.trunk_pitch += drive_mag * drive_local.z
		p.trunk_roll += -drive_mag * drive_local.x
	if _commit_blend > 0.001:
		p.trunk_pitch += -deg_to_rad(_controller.hit_commit_lean_deg) * _commit_blend
		p.drop += _controller.hit_commit_crouch_m * _commit_blend
