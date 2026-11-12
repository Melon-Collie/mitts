class_name StickPaintRows
extends RefCounted

# The player screen's stick design: the pattern pick, then one colour row per
# paint zone (StickModelRegistry.Zone), each shown only when the pattern has
# that zone and offering what CosmeticUnlocks allows. Edits go straight to the
# screen's draft (PlayerDraft.set_stick_pattern / set_stick_zone).

const _STICK: int = LockerMannequin.Focus.STICK
const _BLADE: int = LockerMannequin.Focus.BLADE

var _pattern_btn: OptionButton = null
var _patterns: Array[int] = []
var _zone_dds: Array[SwatchDropdown] = []
var _draft: Callable = Callable()
var _edited: Callable = Callable()


# `make_row(label_key, focus)` adds a labelled row and returns its content box;
# `reach(controls, focus)` aims the case when a control is reached; `draft()`
# returns the live PlayerDraft; `edited()` refreshes after an edit.
func _init(make_row: Callable, reach: Callable, draft: Callable, edited: Callable) -> void:
	_draft = draft
	_edited = edited
	_pattern_btn = PlayerRowKit.option_button(make_row.call(&"STICK_PATTERN_LABEL", _STICK),
			func(i: int) -> void: _pick_pattern(_patterns[i]))
	reach.call([_pattern_btn], _STICK)
	for zone: int in StickModelRegistry.ZONE_COUNT:
		var focus: int = _BLADE if zone == StickModelRegistry.Zone.BLADE else _STICK
		var dd := SwatchDropdown.new(Vector2(PlayerRowKit.FIELD_W, PlayerRowKit.CONTROL_H))
		dd.selected.connect(_pick_zone.bind(zone))
		(make_row.call(StickModelRegistry.ZONE_NAME_KEYS[zone], focus) as Container).add_child(dd)
		reach.call([dd], focus)
		_zone_dds.append(dd)


func pattern_button() -> OptionButton:
	return _pattern_btn


func zone_dropdown(zone: int) -> SwatchDropdown:
	return _zone_dds[zone]


# Re-lists the patterns, drawn in their default colours on this kit, and each
# zone's palette.
func reload(primary: Color, secondary: Color, raised: Array[String]) -> void:
	_patterns = StickModelRegistry.listed()
	_pattern_btn.clear()
	for pattern: int in _patterns:
		var swatch: Array[Color] = []
		var defaults: Array[int] = StickModelRegistry.default_zones(pattern)
		for zone: int in StickModelRegistry.ZONE_COUNT:
			if zone != StickModelRegistry.Zone.BLADE and StickModelRegistry.has_zone(pattern, zone):
				swatch.append(TapeColorRegistry.resolve(defaults[zone], primary, secondary))
		if StickModelRegistry.is_wood(pattern):
			swatch.push_front(StickModelRegistry.WOOD_SHAFT)
		_pattern_btn.add_icon_item(PlayerRowKit.swatch_strip(swatch),
				TrophyCopy.t(StickModelRegistry.name_key(pattern)), pattern)
	for dd: SwatchDropdown in _zone_dds:
		CosmeticSwatches.fill(dd, CosmeticUnlocks.STICK_PAINT, primary, secondary, raised)


func show(pattern: int, tape: StickTapeConfig) -> void:
	_pattern_btn.select(maxi(_patterns.find(pattern), 0))
	var colors: Array[int] = StickModelRegistry.zone_colors(pattern, tape)
	for zone: int in StickModelRegistry.ZONE_COUNT:
		_zone_dds[zone].set_selected(colors[zone])
		_zone_dds[zone].get_parent().get_parent().visible = StickModelRegistry.has_zone(pattern, zone)


func _pick_pattern(pattern: int) -> void:
	(_draft.call() as PlayerDraft).set_stick_pattern(pattern)
	_edited.call()


func _pick_zone(color: int, zone: int) -> void:
	(_draft.call() as PlayerDraft).set_stick_zone(zone, color)
	_edited.call()
