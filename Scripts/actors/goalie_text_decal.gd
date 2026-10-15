class_name GoalieTextDecal
extends Node2D

# Renders name and number on a fully transparent background. Consumed by the
# goalie_jersey.gdshader as the `text_decal` sampler, which projects it onto the
# body's back face: U across the body's width, V down its full height — the
# same frame this texture's PX_PER_M measures, so the lettering is laid out in
# metres exactly as a skater's back is (JerseyDecal.draw_back_lettering).

const IMG_W: int = 512
const IMG_H: int = 640
const PX_PER_M: Vector2 = Vector2(IMG_W / (2.0 * GoalieMeshBuilder.BODY_HALF_W),
		IMG_H / (2.0 * GoalieMeshBuilder.BODY_TOP_Y))

var player_name: String = ""
var jersey_number: int = 0
var text_color: Color = Color.WHITE


func _draw() -> void:
	# Transparent background — only the glyphs are opaque.
	JerseyDecal.draw_back_lettering(self, player_name, jersey_number, text_color,
			IMG_W * 0.5, PX_PER_M, GoalieMeshBuilder.YOKE_DEPTH_M)


func update_text(p_name: String, number: int, t_color: Color) -> void:
	player_name = p_name
	jersey_number = number
	text_color = t_color
	queue_redraw()
