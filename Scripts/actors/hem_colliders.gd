class_name HemColliders
extends RefCounted

# What a hem's flaps (HemFlaps) drape over, in skeleton space, as of the bones'
# poses this frame. Each figure's own shapes extend it: the skater's thighs and
# lathe pants (SkaterHemColliders), the keeper's pants and thigh guards
# (KeeperTailColliders). The port collides against the same shapes, handed to
# it by configure_native.


func update(_skeleton: Skeleton3D) -> void:
	pass


# `p` moved out of every collider it is inside, to `margin` past its surface.
func push_out(p: Vector3, _margin: float) -> Vector3:
	return p


# Hands the shapes, and the bones they ride, to a NativeHemFlaps.
func configure_native(_native: RefCounted) -> void:
	pass
