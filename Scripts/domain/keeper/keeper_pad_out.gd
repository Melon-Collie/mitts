class_name KeeperPadOut
extends RefCounted

# A pad driven out along the ice toward a post while he is on his knees, laid
# over what his legs are doing there (the butterfly at rest, a scoot, a slide
# that pad leads): the butterfly extension's leg and the body that goes with
# it, as far out as `share`. Asked for a side it goes out over `out_s`, and
# comes back under him as quick once it is not, or once the motor needs the
# leg (`step`'s `free`). Pure, stepped at the tick.

# How long the leg takes to go out: the drop's time, as a save's extension.
var out_s: float = GoalieSkillProfile.hard().butterfly_drop_s
# The side asked for, the side out or on its way, his own (−1 the glove's);
# 0 none.
var asked: float = 0.0
var side: float = 0.0
var share: float = 0.0

var _down := KeeperPose.new()
# Extended toward the glove side (index 0) and the blocker side (1).
var _out: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]


func _init() -> void:
	KeeperPoses.butterfly(_down)
	KeeperPoses.butterfly_extension(_out[0], -1.0)
	KeeperPoses.butterfly_extension(_out[1], 1.0)


# `free`: on his knees with that leg kneeling and no move needing it.
func step(dt: float, free: bool) -> void:
	var want: float = asked if free else 0.0
	if side != 0.0 and want != side:
		share = maxf(share - dt / out_s, 0.0)
		if share <= 0.0:
			side = 0.0
	elif want != 0.0:
		side = want
		share = minf(share + dt / out_s, 1.0)


# Taken into the pose a save cuts in from: nothing more of it to lay over.
func cut() -> void:
	side = 0.0
	share = 0.0


# `p`, on his knees, with the pad out as far as it has got: what the extension
# moves from the butterfly, added to whatever `p` holds.
func lay_over(p: KeeperPose) -> void:
	if share <= 0.0:
		return
	var i: int = 0 if side < 0.0 else 1
	var to: KeeperPose = _out[i]
	var t: float = smoothstep(0.0, 1.0, share)
	p.pelvis += (to.pelvis - _down.pelvis) * t
	p.pelvis_rot += (to.pelvis_rot - _down.pelvis_rot) * t
	p.lumbar_rot += (to.lumbar_rot - _down.lumbar_rot) * t
	p.chest_rot += (to.chest_rot - _down.chest_rot) * t
	p.neck_rot += (to.neck_rot - _down.neck_rot) * t
	p.glove_hand += (to.glove_hand - _down.glove_hand) * t
	p.blade_center += (to.blade_center - _down.blade_center) * t
	var leg: KeeperPose.Leg = p.legs[i]
	leg.knee += (to.legs[i].knee - _down.legs[i].knee) * t
	leg.ankle += (to.legs[i].ankle - _down.legs[i].ankle) * t


# His state on the wire (KeeperWire); `out_s` is the tier's and the stances are
# built once.
func wire(w: KeeperWire) -> void:
	asked = w.s16(asked, KeeperWire.MM)
	side = w.s16(side, KeeperWire.MM)
	share = w.s16(share, KeeperWire.FRACTION)
