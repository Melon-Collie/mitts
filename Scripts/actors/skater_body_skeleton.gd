class_name SkaterBodySkeleton
extends RefCounted

const UpperBone = SkaterMeshBuilder.UpperBone

# One Skeleton3D carries both meshes, so the whole figure is one chain on one
# clock. The upper bones keep their indices, the leg bones follow them (the leg
# skin binds through LEG_BONE_OFFSET), and three bones carry no vertices: HIPS,
# the frame the legs hang from; WAIST, the pelvis the shorts ride, turned part of
# the way toward the shoulders; and SPINE, the trunk frame the shell hangs from
# (SkaterSpineRig poses all three).
const LEG_BONE_OFFSET: int = SkaterMeshBuilder.UPPER_BONE_COUNT
const HIPS_BONE: int = SkaterMeshBuilder.UPPER_BONE_COUNT + SkaterMeshBuilder.LEG_BONE_COUNT
const WAIST_BONE: int = HIPS_BONE + 1
const SPINE_BONE: int = WAIST_BONE + 1
const BODY_BONE_COUNT: int = SPINE_BONE + 1


static func upper_bone_parent(bone: int) -> int:
	match bone:
		UpperBone.TORSO, UpperBone.HELMET, UpperBone.SHOULDER_L, UpperBone.SHOULDER_R:
			return SPINE_BONE
		UpperBone.PELVIS:
			return WAIST_BONE
	return -1


# Every bone at identity rest, so a pose write is a plain local transform (the
# property SkaterMeshBuilder.UpperBone depends on).
static func new_body_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "BodyRig"
	for bone: int in SkaterMeshBuilder.UPPER_BONE_COUNT:
		skeleton.add_bone("U%d" % bone)
	for bone: int in SkaterMeshBuilder.LEG_BONE_COUNT:
		skeleton.add_bone("L%d" % bone)
	skeleton.add_bone("Hips")
	skeleton.add_bone("Waist")
	skeleton.add_bone("Spine")
	skeleton.set_bone_parent(WAIST_BONE, HIPS_BONE)
	skeleton.set_bone_parent(SPINE_BONE, WAIST_BONE)
	for bone: int in SkaterMeshBuilder.UPPER_BONE_COUNT:
		skeleton.set_bone_parent(bone, upper_bone_parent(bone))
	for bone: int in SkaterMeshBuilder.LEG_BONE_COUNT:
		var parent: int = SkaterMeshBuilder.LEG_BONE_PARENT[bone]
		skeleton.set_bone_parent(LEG_BONE_OFFSET + bone,
				HIPS_BONE if parent < 0 else LEG_BONE_OFFSET + parent)
	for bone: int in BODY_BONE_COUNT:
		skeleton.set_bone_rest(bone, Transform3D.IDENTITY)
	return skeleton
