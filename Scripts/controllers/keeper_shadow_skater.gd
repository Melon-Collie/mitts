class_name KeeperShadowSkater
extends Skater

# A skater in a predicted keeper's shadow world (KeeperPredictor): what the
# keeper reads of a body (place, velocity, shot state, team, ghost, girth, and a
# carrier's blade for his poke), set by the world source for each stepped
# instant. No rig, no mesh, in no group, never processed: only the nodes the
# skater's own ready-time lookups name exist.

var shadow_team: int = -1
var shadow_blade := Vector3.ZERO


func _init() -> void:
	var root := Node3D.new()
	root.name = "MeshRoot"
	add_child(root)
	var lower := Node3D.new()
	lower.name = "LowerBody"
	root.add_child(lower)
	var upper := Node3D.new()
	upper.name = "UpperBody"
	root.add_child(upper)
	for marker: String in ["Blade", "Shoulder"]:
		var m := Marker3D.new()
		m.name = marker
		upper.add_child(m)
	var stick := MeshInstance3D.new()
	stick.name = "StickMesh"
	upper.add_child(stick)


# Not the skater's: no group, no rig, no tick hook.
func _ready() -> void:
	pass


func get_team_id() -> int:
	return shadow_team


func get_blade_contact_global() -> Vector3:
	return shadow_blade
