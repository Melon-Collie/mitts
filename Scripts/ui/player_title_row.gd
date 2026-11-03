class_name PlayerTitleRow
extends RefCounted

# The player screen's title pick: "None" and the titles the player's raised
# banners have earned (GamePuckRules.earned_titles), re-read each time the screen
# opens. A worn title the list no longer holds — a prefs file carried from
# another machine — is listed too rather than silently dropped.

var _btn: OptionButton = null
var _ids: Array[String] = []
var _hint: Label = null


func _init(parent: Container, on_pick: Callable) -> void:
	_btn = PlayerRowKit.option_button(parent, func(i: int) -> void: on_pick.call(_ids[i]))
	_hint = PlayerRowKit.hint(parent)
	_hint.text = TrophyCopy.t(&"PLAYER_TITLE_HINT")


func reload() -> void:
	_ids = [""]
	_ids.append_array(GamePuckRules.earned_titles(
			SteamStatRecorder.new().totals(), PlayerPrefs.trophy_ledger))
	_rebuild()


func select(title_id: String) -> void:
	if not _ids.has(title_id) and Titles.is_known(title_id):
		_ids.append(title_id)
		_rebuild()
	_btn.select(maxi(_ids.find(title_id), 0))


func _rebuild() -> void:
	_btn.clear()
	for i: int in _ids.size():
		_btn.add_item(TrophyCopy.title_name(_ids[i]), i)
	_hint.visible = _ids.size() == 1
