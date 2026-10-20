class_name GoalieCrestDecal
extends Node2D

# Renders the team's chest crest on a fully transparent background. Consumed by
# goalie_jersey.gdshader as the `crest_decal` sampler, which projects it onto
# the body's front face in GoalieTextDecal's frame — U across the body's width,
# V down its full height — so the crest is placed and sized in metres exactly
# as a skater's chest is (JerseyDecal.draw_chest_crest).

var fruit: String = ""
var preset: Dictionary = {}


func _draw() -> void:
	if fruit.is_empty():
		return
	JerseyDecal.draw_chest_crest(self, fruit, preset, GoalieTextDecal.IMG_W * 0.5,
			GoalieTextDecal.PX_PER_M, GoalieMeshBuilder.YOKE_DEPTH_M)


func update_crest(p_fruit: String, p_preset: Dictionary) -> void:
	fruit = p_fruit
	preset = p_preset
	queue_redraw()
