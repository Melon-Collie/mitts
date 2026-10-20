class_name HemSimMode
extends RefCounted

# Which model moves the jersey's tail below the belt. SWAY swings it whole on a
# lag of the balance lean (SkaterJerseyHem); the other three are prototypes of a
# tail that drapes over the pants and thighs instead of passing through them:
# FLAPS is our own ring of two-segment flaps (SkaterHemFlaps), SPRINGS Godot's
# SpringBoneSimulator3D on per-column bone chains (SkaterHemSprings), and
# SOFT_BODY a SoftBody3D band pinned at the belt (SkaterHemSoftBody).
#
# A skater reads its mode once, when its rig is built (Skater.hem_sim_mode).
# The default is picked per run with `-- --hem-sim=<name>`.

enum { SWAY, FLAPS, SPRINGS, SOFT_BODY }

const NAMES: Array[String] = ["sway", "flaps", "springs", "soft_body"]

static var default_mode: int = _from_cmdline()


static func _from_cmdline() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hem-sim="):
			var mode: int = NAMES.find(arg.trim_prefix("--hem-sim="))
			if mode >= 0:
				return mode
	return SWAY


# Whether the tail's vertices ride per-column bones (one chain per lathe facet).
static func uses_columns(mode: int) -> bool:
	return mode == FLAPS or mode == SPRINGS
