class_name SkaterBodySkeleton
extends RefCounted

const UpperBone = SkaterMeshBuilder.UpperBone

# One Skeleton3D carries the whole figure, so it is one chain on one clock. The
# upper bones keep their indices, the leg bones follow them (the leg mesh binds
# through LEG_BONE_OFFSET), and four bones carry no vertices: HIPS, the frame the
# legs hang from; WAIST, the pelvis the pants ride, turned part of the way toward
# the shoulders; SPINE, the trunk frame the torso hangs from; and NECK, which
# levels the head on it (SkaterSpineRig poses all four). TAIL, on the waist, is
# the torso as the hips hold it, for the share of the jersey's lower half they
# carry (SkaterJerseyHem). After those, the skin's deform bones
# (SkaterConnectedMesh.Deform), then the jersey's tail below the belt: two bones
# per tail column, the segment from the belt to the bend and the one from the
# bend to the hem, each a root SkaterHemFlaps poses in skeleton space.
const LEG_BONE_OFFSET: int = SkaterMeshBuilder.UPPER_BONE_COUNT
const HIPS_BONE: int = SkaterMeshBuilder.UPPER_BONE_COUNT + SkaterMeshBuilder.LEG_BONE_COUNT
const WAIST_BONE: int = HIPS_BONE + 1
const SPINE_BONE: int = WAIST_BONE + 1
const NECK_BONE: int = SPINE_BONE + 1
const TAIL_BONE: int = NECK_BONE + 1
const DEFORM_BONE_BASE: int = TAIL_BONE + 1
const COLUMN_BONE_BASE: int = DEFORM_BONE_BASE + SkaterConnectedMesh.DEFORM_COUNT
const BODY_BONE_COUNT: int = COLUMN_BONE_BASE + 2 * SkaterConnectedMesh.TAIL_COLUMNS


static func deform_bone(deform: int) -> int:
	return DEFORM_BONE_BASE + deform


# A tail column's segment bone: `joint` 0 from the belt to the bend, 1 on to
# the hem.
static func column_bone(column: int, joint: int) -> int:
	return COLUMN_BONE_BASE + column * 2 + joint


static func upper_bone_parent(bone: int) -> int:
	match bone:
		UpperBone.TORSO:
			return SPINE_BONE
		UpperBone.HELMET:
			return NECK_BONE
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
	skeleton.add_bone("Neck")
	skeleton.add_bone("Tail")
	for deform: int in SkaterConnectedMesh.DEFORM_COUNT:
		skeleton.add_bone("Deform%d" % deform)
	for column: int in SkaterConnectedMesh.TAIL_COLUMNS:
		skeleton.add_bone("Tail%d" % column)
		skeleton.add_bone("Hem%d" % column)
	skeleton.set_bone_parent(WAIST_BONE, HIPS_BONE)
	skeleton.set_bone_parent(SPINE_BONE, WAIST_BONE)
	skeleton.set_bone_parent(NECK_BONE, SPINE_BONE)
	skeleton.set_bone_parent(TAIL_BONE, WAIST_BONE)
	for bone: int in SkaterMeshBuilder.UPPER_BONE_COUNT:
		skeleton.set_bone_parent(bone, upper_bone_parent(bone))
	for bone: int in SkaterMeshBuilder.LEG_BONE_COUNT:
		var parent: int = SkaterMeshBuilder.LEG_BONE_PARENT[bone]
		skeleton.set_bone_parent(LEG_BONE_OFFSET + bone,
				HIPS_BONE if parent < 0 else LEG_BONE_OFFSET + parent)
	skeleton.set_bone_parent(deform_bone(SkaterConnectedMesh.Deform.KNEE_L),
			LEG_BONE_OFFSET + SkaterMeshBuilder.LegBone.LEG_L)
	skeleton.set_bone_parent(deform_bone(SkaterConnectedMesh.Deform.KNEE_R),
			LEG_BONE_OFFSET + SkaterMeshBuilder.LegBone.LEG_R)
	for bone: int in skeleton.get_bone_count():
		skeleton.set_bone_rest(bone, Transform3D.IDENTITY)
	return skeleton
