class_name ShotSound
extends RefCounted

# The one shot-release cue, scaled by release speed, shared by live play, the
# remote-peer broadcast, and replay playback so all three sound identical.
#
# Normalized against the league-default power band per shot type rather than
# the shooter's own attribute-scaled band: a big shooter's rip should sound
# bigger than an average one, and a quick pass (a fixed-power wrister) should
# read as the soft touch it is.

const _WRISTER_VOL_MIN_DB: float = -9.0
const _WRISTER_VOL_MAX_DB: float = 0.0
const _SLAPPER_VOL_MIN_DB: float = -5.0
const _SLAPPER_VOL_MAX_DB: float = 2.0
# A harder strike rings the blade sharper.
const _PITCH_SOFT: float = 0.94
const _PITCH_HARD: float = 1.06
const _PITCH_VARIANCE: float = 0.04


static func intensity(power: float, is_slapper: bool) -> float:
	var lo: float = GameRules.DEFAULT_SLAPPER_POWER_MIN_M_S if is_slapper \
			else GameRules.DEFAULT_WRISTER_POWER_MIN_M_S
	var hi: float = GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S if is_slapper \
			else GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	return clampf((power - lo) / (hi - lo), 0.0, 1.0)


static func volume_db(power: float, is_slapper: bool) -> float:
	var t: float = intensity(power, is_slapper)
	if is_slapper:
		return lerpf(_SLAPPER_VOL_MIN_DB, _SLAPPER_VOL_MAX_DB, t)
	return lerpf(_WRISTER_VOL_MIN_DB, _WRISTER_VOL_MAX_DB, t)


static func pitch_scale(power: float, is_slapper: bool) -> float:
	return lerpf(_PITCH_SOFT, _PITCH_HARD, intensity(power, is_slapper))


static func play(position: Vector3, power: float, is_slapper: bool) -> void:
	var sound: SoundManager.Sound = SoundManager.Sound.SHOT_SLAPPER if is_slapper \
			else SoundManager.Sound.SHOT_WRISTER
	SoundManager.play_world(sound, position, volume_db(power, is_slapper),
			_PITCH_VARIANCE, pitch_scale(power, is_slapper))
