class_name ClubCrest
extends Control
## One club's crest, drawn to fit this control. A club with no fruit drawing
## shows a disc of its primary color.

# The crest's two keylines reach this far past the unit circle the fruit fills.
const _KEYLINE_REACH: float = 1.0 + TeamCrest.KEYLINE_WIDTH * 2.0

var _club: int = -1


func _init(side_px: float = 24.0, club: int = -1) -> void:
	custom_minimum_size = Vector2(side_px, side_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_club = club


# -1 draws nothing.
func set_club(club: int) -> void:
	_club = club
	queue_redraw()


func _draw() -> void:
	if _club < 0:
		return
	var preset: Dictionary = TeamColorRegistry.get_preset(_club)
	var radius: float = minf(size.x, size.y) * 0.5 / _KEYLINE_REACH
	var fruit: String = TeamCrest.fruit_for(preset)
	if fruit.is_empty():
		draw_circle(size * 0.5, radius, preset.get("primary", MenuStyle.TEXT_DIM))
		return
	TeamCrest.draw(self, fruit, Transform2D(0.0, Vector2.ONE * radius, 0.0, size * 0.5), preset)
