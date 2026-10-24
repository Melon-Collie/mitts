class_name KeeperChestTrap
extends RefCounted

# A shot into his chest protector caught there (USA Hockey: smothered into the
# upper body by caving the arms in around it). It has to be at the logo, the
# face between where his arm pads lie on it, where both arms can close round
# it; the foam takes most of its pace (GoalieSaveRules' chest material) and it
# is his if the nearer of his hands gets onto it before what is left carries
# it out of the glove's pocket. A hard shot comes off him before an arm away
# from it can close; a soft one, or one his glove was already over, he holds.
#
# Keeper space: the solved skeleton's (its boxes as KeeperGear places them).

# How far off his chest a puck can come and still be closed on: the glove's
# pocket.
const POCKET_M: float = KeeperAnatomy.GLOVE_WIDTH_M * 0.5
# The glove come over a puck held to his chest: its palm on the puck, its
# hand this far out from the protector's face.
const GLOVE_OFF_CHEST_M: float = GameRules.PUCK_COLLISION_RADIUS + KeeperAnatomy.GLOVE_DEPTH_M * 0.5


# Whether `point` on him is on the chest protector's face at the logo: across,
# inside the arm pads lying on it; up, the middle half of its height.
static func at_logo(skel: KeeperSkeleton, point: Vector3) -> bool:
	var local: Vector3 = KeeperGear.box(skel, KeeperGear.Part.CHEST).affine_inverse() * point
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	return local.z < 0.0 and absf(local.x) <= h.x - KeeperAnatomy.ARM_PAD_WIDTH_M \
			and absf(local.y) <= 0.5 * h.y


# Whether a puck meeting his chest at `normal_speed` (into it, relative to it)
# is closed on by a hand `reach_s` seconds from it (the soonest of his hands at
# its speed): before the foam's rebound carries it out of the pocket.
static func closes_on(normal_speed: float, reach_s: float) -> bool:
	var off: float = normal_speed * GoalieSaveRules.MATERIALS[GoalieSaveRules.SavePart.CHEST * GoalieSaveRules.MAT_STRIDE
			+ GoalieSaveRules.MAT_COR_SCALE]
	return off * reach_s <= POCKET_M
