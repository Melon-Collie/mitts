class_name SkaterBodySkeleton
extends RefCounted

const UpperBone = SkaterMeshBuilder.UpperBone

# One Skeleton3D carries both meshes, so the whole figure is one chain on one
# clock. The upper bones keep their indices, the leg bones follow them (the leg
# skin binds through LEG_BONE_OFFSET), and four bones carry no vertices: HIPS,
# the frame the legs hang from; WAIST, the pelvis the shorts ride, turned part of
# the way toward the shoulders; SPINE, the trunk frame the shell hangs from; and
# NECK, which levels the head on it (SkaterSpineRig poses all four). The jersey's
# lower half has three (SkaterJerseyHem): HEM, under the torso, swings the share
# of it the chest carries; TAIL, on the waist, holds the share the hips carry,
# and TAIL_HEM, under TAIL, swings that.
const LEG_BONE_OFFSET: int = SkaterMeshBuilder.UPPER_BONE_COUNT
const HIPS_BONE: int = SkaterMeshBuilder.UPPER_BONE_COUNT + SkaterMeshBuilder.LEG_BONE_COUNT
const WAIST_BONE: int = HIPS_BONE + 1
const SPINE_BONE: int = WAIST_BONE + 1
const NECK_BONE: int = SPINE_BONE + 1
const HEM_BONE: int = NECK_BONE + 1
const TAIL_BONE: int = HEM_BONE + 1
const TAIL_HEM_BONE: int = TAIL_BONE + 1
const BODY_BONE_COUNT: int = TAIL_HEM_BONE + 1
# A hem sim that drapes the tail by columns (HemSimMode.uses_columns) adds one
# bone chain per torso facet after the body's own: a flap's two segments, each a
# root posed in skeleton space, or a spring chain's root, bend and tip under TAIL.
const COLUMN_BONE_BASE: int = BODY_BONE_COUNT


static func column_bone_stride(hem_sim: int) -> int:
	return 3 if hem_sim == HemSimMode.SPRINGS else 2


static func column_bone(hem_sim: int, column: int, joint: int) -> int:
	return COLUMN_BONE_BASE + column * column_bone_stride(hem_sim) + joint


static func upper_bone_parent(bone: int) -> int:
	match bone:
		UpperBone.TORSO, UpperBone.SHOULDER_L, UpperBone.SHOULDER_R:
			return SPINE_BONE
		UpperBone.HELMET:
			return NECK_BONE
		UpperBone.PELVIS:
			return WAIST_BONE
	return -1


# Every bone at identity rest, so a pose write is a plain local transform (the
# property SkaterMeshBuilder.UpperBone depends on) — but for a spring chain's,
# whose rests SkaterHemSprings sets, since the solver reads its lengths off them.
static func new_body_skeleton(hem_sim: int = HemSimMode.SWAY) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "BodyRig"
	for bone: int in SkaterMeshBuilder.UPPER_BONE_COUNT:
		skeleton.add_bone("U%d" % bone)
	for bone: int in SkaterMeshBuilder.LEG_BONE_COUNT:
		skeleton.add_bone("L%d" % bone)
	skeleton.add_bone("Hips")
	skeleton.add_bone("Waist")
	skeleton.add_bone("Spine")
	skeleton.add_bone("Neck")
	skeleton.add_bone("Hem")
	skeleton.add_bone("Tail")
	skeleton.add_bone("TailHem")
	skeleton.set_bone_parent(WAIST_BONE, HIPS_BONE)
	skeleton.set_bone_parent(SPINE_BONE, WAIST_BONE)
	skeleton.set_bone_parent(NECK_BONE, SPINE_BONE)
	skeleton.set_bone_parent(HEM_BONE, UpperBone.TORSO)
	skeleton.set_bone_parent(TAIL_BONE, WAIST_BONE)
	skeleton.set_bone_parent(TAIL_HEM_BONE, TAIL_BONE)
	for bone: int in SkaterMeshBuilder.UPPER_BONE_COUNT:
		skeleton.set_bone_parent(bone, upper_bone_parent(bone))
	for bone: int in SkaterMeshBuilder.LEG_BONE_COUNT:
		var parent: int = SkaterMeshBuilder.LEG_BONE_PARENT[bone]
		skeleton.set_bone_parent(LEG_BONE_OFFSET + bone,
				HIPS_BONE if parent < 0 else LEG_BONE_OFFSET + parent)
	for bone: int in BODY_BONE_COUNT:
		skeleton.set_bone_rest(bone, Transform3D.IDENTITY)
	if HemSimMode.uses_columns(hem_sim):
		var stride: int = column_bone_stride(hem_sim)
		for column: int in SkaterMeshBuilder.TORSO_SIDES:
			for joint: int in stride:
				var bone: int = skeleton.add_bone("Col%d_%d" % [column, joint])
				skeleton.set_bone_rest(bone, Transform3D.IDENTITY)
				if hem_sim == HemSimMode.SPRINGS:
					skeleton.set_bone_parent(bone, TAIL_BONE if joint == 0 else bone - 1)
	return skeleton
