class_name BuildReadout

# A build's effect on play as numbers a player can read: each stat is one
# PlayerAttributes accessor taken as a ratio to the neutral build's, so 1.0 is
# "plays like the controller's defaults". Each is oriented so that higher means
# more of what the stat is named for — COAST is the inverse of glide drag and
# SLAPPER_RELEASE the inverse of wind-up time. This adds no rule of its own; it
# only reads the attribute model.

enum Stat {
	TOP_SPEED, FIRST_STEP, AGILITY, CROSSOVER, BACKWARD, COAST,
	MASS, REACH,
	WRIST_SHOT, SLAPSHOT, SLAPPER_RELEASE, BACKHAND, PASS_CATCH,
}

# The six dials a player sets, in PlayerAttributes' constructor order.
enum Dial { HEIGHT, WEIGHT, PROFILE, CURVE, FLEX, LENGTH }

enum Group { SKATING, BODY, SHOT }

const STAT_COUNT: int = 13

const NAME_KEYS: Array[StringName] = [
	&"STAT_TOP_SPEED", &"STAT_FIRST_STEP", &"STAT_AGILITY", &"STAT_CROSSOVER",
	&"STAT_BACKWARD", &"STAT_COAST", &"STAT_MASS", &"STAT_REACH",
	&"STAT_WRIST_SHOT", &"STAT_SLAPSHOT", &"STAT_SLAPPER_RELEASE",
	&"STAT_BACKHAND", &"STAT_PASS_CATCH",
]

const GROUP_OF: Array[int] = [
	Group.SKATING, Group.SKATING, Group.SKATING, Group.SKATING, Group.SKATING,
	Group.SKATING, Group.BODY, Group.BODY,
	Group.SHOT, Group.SHOT, Group.SHOT, Group.SHOT, Group.SHOT,
]

const GROUP_KEYS: Array[StringName] = [&"STAT_GROUP_SKATING", &"STAT_GROUP_BODY",
		&"STAT_GROUP_SHOT"]

# A stat counts as moved by a dial past this ratio change — well under the
# smallest real lean (1%), well over float noise.
const _MOVED_EPS: float = 0.0005

static var _neutral_raw: PackedFloat64Array = PackedFloat64Array()


# The stat as a ratio to the neutral build's.
static func ratio(attrs: PlayerAttributes, stat: int) -> float:
	if _neutral_raw.is_empty():
		var neutral: PlayerAttributes = PlayerAttributes.neutral()
		_neutral_raw.resize(STAT_COUNT)
		for s: int in STAT_COUNT:
			_neutral_raw[s] = raw(neutral, s)
	return raw(attrs, stat) / _neutral_raw[stat]


static func raw(attrs: PlayerAttributes, stat: int) -> float:
	match stat:
		Stat.TOP_SPEED:
			return attrs.top_speed_mult()
		Stat.FIRST_STEP:
			return attrs.accel_mult()
		Stat.AGILITY:
			return attrs.agility_mult()
		Stat.CROSSOVER:
			return attrs.crossover_mult()
		Stat.BACKWARD:
			return attrs.backward_mult()
		Stat.COAST:
			return 1.0 / attrs.glide_drag_mult()
		Stat.MASS:
			return attrs.mass_mult()
		Stat.REACH:
			return attrs.stick_len_mult()
		Stat.WRIST_SHOT:
			return attrs.shot_power_mult()
		Stat.SLAPSHOT:
			return attrs.slapper_power_mult()
		Stat.SLAPPER_RELEASE:
			return 1.0 / attrs.shot_charge_mult()
		Stat.BACKHAND:
			return attrs.curve_backhand_mult()
		Stat.PASS_CATCH:
			return attrs.reception_ceiling_mult()
	return 1.0


# Every stat any of `dials` can move, found by swinging each dial to both ends
# of its range from the neutral build. Height swings at a constant frame (the
# weight follows it, as the height control carries it), so it reports what a
# height pick does to a body that keeps its build.
static func moved_by(dials: Array[int]) -> Array[int]:
	var moved: Array[int] = []
	for dial: int in dials:
		for probe: PlayerAttributes in _probes(dial):
			for s: int in STAT_COUNT:
				if not moved.has(s) and absf(ratio(probe, s) - 1.0) > _MOVED_EPS:
					moved.append(s)
	moved.sort()
	return moved


static func _probes(dial: int) -> Array[PlayerAttributes]:
	var mid: int = PlayerAttributes.HEIGHT_MEDIUM
	match dial:
		Dial.HEIGHT:
			var lo: int = PlayerAttributes.HEIGHT_MIN
			var hi: int = PlayerAttributes.HEIGHT_MAX
			return [PlayerAttributes.new(lo, PlayerAttributes.weight_for_frame_t(lo, 0.5)),
					PlayerAttributes.new(hi, PlayerAttributes.weight_for_frame_t(hi, 0.5))]
		Dial.WEIGHT:
			return [PlayerAttributes.new(mid, PlayerAttributes.weight_min(mid)),
					PlayerAttributes.new(mid, PlayerAttributes.weight_max(mid))]
	return [_gear_probe(dial, 0), _gear_probe(dial, 2)]


# The neutral build with one gear dial swung to `option`.
static func _gear_probe(dial: int, option: int) -> PlayerAttributes:
	var slots: Array[int] = [PlayerAttributes.GEAR_BALANCED, PlayerAttributes.GEAR_BALANCED,
			PlayerAttributes.GEAR_BALANCED, PlayerAttributes.GEAR_BALANCED]
	slots[dial - Dial.PROFILE] = option
	return PlayerAttributes.new(PlayerAttributes.HEIGHT_MEDIUM, 0,
			slots[0], slots[1], slots[2], slots[3])
