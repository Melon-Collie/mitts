class_name TapeCoverageList
extends RefCounted

# The player screen's tape-coverage pick: the spans the player may wear in the
# list's reading order, then the reward spans still to earn, greyed and naming
# the Game Puck that unlocks them (CosmeticUnlocks).

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
	var locked: Array[int] = CosmeticUnlocks.locked(CosmeticUnlocks.TAPE_SPAN, earned)
	for span: int in _ORDER:
		if open.has(span):
			_add(span, TrophyCopy.t(StickTapeConfig.SPAN_NAME_KEYS[span]), false)
	for span: int in _ORDER:
		if locked.has(span):
			var req: String = CosmeticUnlocks.reward_puck(CosmeticUnlocks.TAPE_SPAN, span)
			_add(span, TrophyCopy.t(&"TAPE_SPAN_LOCKED") % [
					TrophyCopy.t(StickTapeConfig.SPAN_NAME_KEYS[span]),
					TrophyCopy.requirement_name(req)], true)


func select(span: int) -> void:
	_btn.select(maxi(_ids.find(span), 0))


func _add(span: int, text: String, disabled: bool) -> void:
	_btn.add_item(text, span)
	_btn.set_item_disabled(_btn.item_count - 1, disabled)
	_ids.append(span)
