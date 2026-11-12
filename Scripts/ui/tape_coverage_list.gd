class_name TapeCoverageList
extends RefCounted

# The player screen's tape-coverage pick: the spans the player may wear
# (CosmeticUnlocks), in the list's reading order. A reward span is listed only
# once its Game Puck is earned.

const _ORDER: Array[int] = [
	StickTapeConfig.Span.FULL, StickTapeConfig.Span.HEEL_TO_MID,
	StickTapeConfig.Span.MID_TO_TOE, StickTapeConfig.Span.MID,
	StickTapeConfig.Span.TOE, StickTapeConfig.Span.NONE,
	StickTapeConfig.Span.SPACED, StickTapeConfig.Span.BOTTOM_STRIP,
]

var _btn: OptionButton = null
var _ids: Array[int] = []


func _init(parent: Container, on_pick: Callable) -> void:
	_btn = PlayerRowKit.option_button(parent, func(i: int) -> void: on_pick.call(_ids[i]))


func button() -> OptionButton:
	return _btn


func reload(earned: Array[String]) -> void:
	_btn.clear()
	_ids.clear()
	var open: Array[int] = CosmeticUnlocks.available(CosmeticUnlocks.TAPE_SPAN, earned)
	for span: int in _ORDER:
		if open.has(span):
			_btn.add_item(TrophyCopy.t(StickTapeConfig.SPAN_NAME_KEYS[span]), span)
			_ids.append(span)


func select(span: int) -> void:
	_btn.select(maxi(_ids.find(span), 0))

