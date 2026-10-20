class_name ReplayStinger
extends CanvasLayer

# Broadcast replay wipe: a slanted band in the scoring team's colors sweeps in
# from the left until it fills the screen, holds on the Mitts mark, and sweeps
# off to the right. `covered` fires at full cover — the instant a camera cut
# behind it is invisible. Built in code, input-transparent, and independent of
# whoever started it, so a replay torn down mid-wipe still sees the band off.

signal covered

const COVER_TIME: float = 0.22
const HOLD_TIME: float = 0.18
const REVEAL_TIME: float = 0.22
const SLANT: float = 0.3          # horizontal lean of the band's edges, as a fraction of screen height
const EDGE_STRIPE: float = 0.035  # secondary-color stripe at each edge, as a fraction of screen width
const LOGO_HEIGHT: float = 0.3    # of screen height
const _LOGO: Texture2D = preload("res://Assets/logos/Mitts_logo_full.png")

var _canvas: Control = null
var _primary: Color = Color.BLACK
var _secondary: Color = Color.WHITE
# Seconds into the current wipe; < 0 while idle.
var _elapsed: float = -1.0
var _covered_emitted: bool = false


func _ready() -> void:
	layer = 3  # over the HUD, under the intermission / game-over overlays
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_band)
	add_child(_canvas)
	visible = false


# Starts a wipe from the beginning, even over one already running.
func play(primary: Color, secondary: Color) -> void:
	_primary = primary
	_secondary = secondary
	_elapsed = 0.0
	_covered_emitted = false
	visible = true
	_canvas.queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if not _covered_emitted and _elapsed >= COVER_TIME:
		_covered_emitted = true
		covered.emit()
	if _elapsed >= COVER_TIME + HOLD_TIME + REVEAL_TIME:
		_elapsed = -1.0
		visible = false
		return
	_canvas.queue_redraw()


# Leading edge sweeps across during the cover, trailing edge during the reveal;
# each is eased so the band snaps in and out rather than sliding at a constant rate.
func _draw_band() -> void:
	if _elapsed < 0.0:
		return
	var size: Vector2 = _canvas.size
	var lean: float = SLANT * size.y
	var off_left: float = -lean - EDGE_STRIPE * size.x
	var off_right: float = size.x + lean + EDGE_STRIPE * size.x
	var cover_t: float = _ease(_elapsed / COVER_TIME)
	var reveal_t: float = _ease((_elapsed - COVER_TIME - HOLD_TIME) / REVEAL_TIME)
	var lead: float = lerpf(off_left, off_right, cover_t)
	var trail: float = lerpf(off_left, off_right, reveal_t)
	var stripe: float = EDGE_STRIPE * size.x
	_canvas.draw_colored_polygon(_slab(trail, lead, size.y, lean), _primary)
	_canvas.draw_colored_polygon(_slab(lead - stripe, lead, size.y, lean), _secondary)
	_canvas.draw_colored_polygon(_slab(trail, trail + stripe, size.y, lean), _secondary)
	# The mark shows only while the band's slanted edges clear it entirely.
	var logo_h: float = LOGO_HEIGHT * size.y
	var logo_size := Vector2(logo_h * _LOGO.get_width() / _LOGO.get_height(), logo_h)
	var logo_rect := Rect2((size - logo_size) * 0.5, logo_size)
	if trail + lean * 0.5 + stripe < logo_rect.position.x \
			and lead - lean * 0.5 - stripe > logo_rect.end.x:
		_canvas.draw_texture_rect(_LOGO, logo_rect, false)


# The band between two edge positions measured at mid-height, leaning right.
static func _slab(from_x: float, to_x: float, height: float, lean: float) -> PackedVector2Array:
	var half_lean: float = lean * 0.5
	return PackedVector2Array([
		Vector2(from_x + half_lean, 0.0), Vector2(to_x + half_lean, 0.0),
		Vector2(to_x - half_lean, height), Vector2(from_x - half_lean, height),
	])


static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)
