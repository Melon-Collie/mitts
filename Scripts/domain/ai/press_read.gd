class_name AIPressRead
extends RefCounted

# When a bot's press is worth its commit, read from what the bot can see. The
# pair's motion is the one both bodies' movement steps would lay (PressRules, on
# the league body scaled by each build's caps), against the man as he stands
# now: his facing, posture, brake, stagger and intent (not a planted shot
# state, which the domain does not name; a planted screener reads as standing
# on his own edges). The push runs along the
# contact normal, from the presser through the man, so a press clears a screen
# only from the side that moves him off the sightline. Pure/static, no
# allocation.

# A press is priced over this long: about a point shot's wind-up and flight, the
# time the screen it clears has to be gone by. A starting value.
const READ_S: float = 1.0
# A man this close (body edge to body edge, m) is leaned on, not skated to: the
# step that closes it is the press's first stride.
const STEP_IN_M: float = 0.3

static var _league: SkaterMovementRules.MovementConfig = SkaterMovementRules.league_config()
static var _check_cfg := BodyCheckRules.Config.new()


# Body edge to body edge (m) between two bodies of the bots' body radius
# (GameRules.OFFSIDE_LINE_SLACK, the radius every bot read touches at).
static func gap_m(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length() - 2.0 * GameRules.OFFSIDE_LINE_SLACK


# How far (m) a committed press from `me` (driving straight at him, at the
# build's thrust) moves `man` along the normal in READ_S; `*_caps` null reads a
# league body. Never negative: a press he holds moves him nowhere.
static func displacement_m(me: SkaterNetworkState, my_caps: AISkaterCaps,
		man: SkaterNetworkState, man_caps: AISkaterCaps) -> float:
	var d := Vector2(man.position.x - me.position.x, man.position.z - me.position.z)
	if d.length_squared() < 0.0001:
		return 0.0
	var n: Vector2 = d.normalized()
	var a: float = pair_accel(me, my_caps, SkaterMovementRules.Posture.COMMIT, n, n, man, man_caps)
	return 0.5 * maxf(a, 0.0) * READ_S * READ_S


# The pair's acceleration (m/s²) as a press starts, along the normal from `me`
# toward `man` (positive moves him back), with `me` skating `intent` in
# `posture` facing `my_facing`, against the man as he stands now. Zero when
# neither body drives into the other.
static func pair_accel(me: SkaterNetworkState, my_caps: AISkaterCaps, posture: int,
		intent: Vector2, my_facing: Vector2, man: SkaterNetworkState,
		man_caps: AISkaterCaps) -> float:
	var d := Vector2(man.position.x - me.position.x, man.position.z - me.position.z)
	if d.length_squared() < 0.0001:
		return 0.0
	var n: Vector2 = d.normalized()
	var my_mass: float = my_caps.weight if my_caps != null else 1.0
	var man_mass: float = man_caps.weight if man_caps != null else 1.0
	var drive_me: float = PressRules.drive(_movement(my_caps), _thrust(my_caps), posture,
			false, false,
			BodyCheckRules.thrust_mult(me.stagger_timer, _check_cfg), my_facing, intent, n, 0.0)
	var hold_me: float = PressRules.hold(_movement(my_caps), posture, false, false,
			BodyCheckRules.grip_mult(me.stagger_timer, _check_cfg), my_facing, n, 0.0)
	var man_posture: int = SkaterMovementRules.posture_of(man.stance_active, man.hit_committed)
	var drive_man: float = PressRules.drive(_movement(man_caps), _thrust(man_caps), man_posture,
			man.brake_intent, false, BodyCheckRules.thrust_mult(man.stagger_timer, _check_cfg),
			man.facing, man.move_intent, -n, 0.0)
	var hold_man: float = PressRules.hold(_movement(man_caps), man_posture, man.brake_intent, false,
			BodyCheckRules.grip_mult(man.stagger_timer, _check_cfg), man.facing, n, 0.0)
	if not PressRules.pressing(drive_me, drive_man):
		return 0.0
	return PressRules.pair_accel(my_mass, drive_me, hold_me, man_mass, drive_man, hold_man,
			0.0, READ_S)


static func _movement(caps: AISkaterCaps) -> SkaterMovementRules.MovementConfig:
	return caps.movement if caps != null else _league


static func _thrust(caps: AISkaterCaps) -> float:
	return caps.max_accel if caps != null else GameRules.DEFAULT_SKATER_THRUST_M_S2
