class_name KeeperKneeShuffle
extends RefCounted

# The steps of his knee shuffle, laid over the butterfly while he scoots
# across: the pad on the side he goes comes off the ice and is set down a step
# further on, the other closes up after it, and his weight rocks onto whichever
# is down. A knee that is down stays where it is on the ice, so the steps are
# paced by how far he has gone, not by a clock. Where he is is the motor's;
# only his own sideways travel steps, a scoot forward or back sliding on both
# pads. Pure, stepped at the tick.

# How far he goes in one pair of steps, which is also how far apart his knees
# come at the widest.
const STRIDE_M: float = 0.16
# How high a pad comes off the ice to step: under a puck's thickness.
const LIFT_M: float = 0.015
# How far his hips roll, and shift, onto the knee that is down.
const ROCK_RAD: float = 0.05
const SHIFT_M: float = 0.015
# How long the steps take to come in as he sets off and to settle out of him.
const SETTLE_S: float = 0.1

# The side he goes, his own (−1 the glove's); 0 at rest.
var side: float = 0.0
# How far through a pair of steps he is: the leading knee stepping out over
# the first half, the trailing one closing up over the second.
var phase: float = 0.0
var share: float = 0.0


# `across`: how far he scooted this tick to his own right (the blocker's side),
# 0 when he did not or his legs are not free to step.
func step(dt: float, across: float) -> void:
	if is_zero_approx(across):
		share = maxf(share - dt / SETTLE_S, 0.0)
		if share <= 0.0:
			side = 0.0
			phase = 0.0
		return
	var goes: float = signf(across)
	# Turned back the other way, each knee keeps its place and its part of the
	# step: the one stepping out is the one now closing up.
	if side == -goes:
		phase = 1.0 - phase
	side = goes
	phase = fposmod(phase + absf(across) / STRIDE_M, 1.0)
	share = minf(share + dt / SETTLE_S, 1.0)


# Taken into the pose a save cuts in from: nothing more of it to lay over.
func cut() -> void:
	side = 0.0
	phase = 0.0
	share = 0.0


# `p`, on his knees, with his legs as far through their steps as they are.
func lay_over(p: KeeperPose) -> void:
	if share <= 0.0:
		return
	var lead: int = 0 if side < 0.0 else 1
	var stepping_out: bool = phase < 0.5
	# 0 with his knees together, 1 at their widest.
	var apart: float = 2.0 * (phase if stepping_out else 1.0 - phase)
	var lift: float = sin(TAU * phase)
	lift *= lift * LIFT_M * share
	var half: float = 0.5 * STRIDE_M * apart * share
	_move(p.legs[lead], side * half, lift if stepping_out else 0.0)
	_move(p.legs[1 - lead], -side * half, 0.0 if stepping_out else lift)
	# Onto the trailing knee while the leading one steps, and back.
	var onto: float = -side * sin(TAU * phase) * share
	p.pelvis.x += onto * SHIFT_M
	p.pelvis_rot.z -= onto * ROCK_RAD
	p.lumbar_rot.z += onto * ROCK_RAD * 0.5
	p.chest_rot.z += onto * ROCK_RAD * 0.5


static func _move(leg: KeeperPose.Leg, across: float, up: float) -> void:
	var by := Vector3(across, up, 0.0)
	leg.knee += by
	leg.ankle += by


func wire(w: KeeperWire) -> void:
	side = w.s16(side, KeeperWire.MM)
	phase = w.s16(phase, KeeperWire.FRACTION)
	share = w.s16(share, KeeperWire.FRACTION)
