class_name CustomDataFile
extends RefCounted

# One bundled data file the player can take an editable copy of (team colors,
# the bot roster): the buttons that create, reveal and drop the copy, and the
# line saying which file is in use. The registries read their file once per
# launch, so this reports what the game WILL use next to what it IS using, and
# asks for a restart when the two differ.
#
# The tab lays the widgets out in its own rows (build_buttons, build_status);
# this owns them and their state.

enum State { NONE, IN_USE, OUTDATED, UNREADABLE }

const _ERROR_COLOR: Color = Color(0.9, 0.3, 0.3, 1.0)
const _WARN_COLOR: Color = Color(0.95, 0.75, 0.3, 1.0)
const _BUTTON_FONT_SIZE: int = 15
const _BUTTON_HEIGHT: int = 40

var _bundled_path: String
var _user_path: String
var _accepts: Callable
var _loaded_path: Callable
# The array whose length says how much a copy holds; empty skips the
# out-of-date check (a shorter bot roster is a choice, fewer teams is not).
var _entries_key: String
var _outdated_key: String
var _host: Control = null

var _create_btn: Button = null
var _drop_btn: Button = null
var _status: Label = null
var _confirm: ConfirmDialog = null
var _pending: Callable


# `accepts` is the registry's own test for a parsed file and `loaded_path`
# the file it loaded, so this never disagrees with the loader about either.
func _init(bundled_path: String, user_path: String, accepts: Callable,
		loaded_path: Callable, entries_key: String = "", outdated_key: String = "") -> void:
	_bundled_path = bundled_path
	_user_path = user_path
	_accepts = accepts
	_loaded_path = loaded_path
	_entries_key = entries_key
	_outdated_key = outdated_key


func build_buttons(host: Control) -> HBoxContainer:
	_host = host
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_create_btn = _button(_on_create_pressed)
	row.add_child(_create_btn)
	var open_btn := _button(_on_open_pressed)
	open_btn.text = host.tr("CUSTOM_FILE_OPEN_FOLDER")
	row.add_child(open_btn)
	_drop_btn = _button(_on_drop_pressed)
	_drop_btn.text = host.tr("CUSTOM_FILE_USE_BUILT_IN")
	row.add_child(_drop_btn)
	return row


# The status line, indented under the buttons like the tab's row notes, with
# the confirm dialog parked beside it in the tree.
func build_status() -> Control:
	var box := MarginContainer.new()
	box.add_theme_constant_override("margin_left",
			OptionsTab._LABEL_COL_WIDTH + OptionsTab._ROW_SEPARATION)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_confirm = ConfirmDialog.new()
	_confirm.confirmed.connect(func() -> void: _pending.call())
	box.add_child(_confirm)
	refresh()
	return box


func refresh(error_key: String = "") -> void:
	var has_copy: bool = FileAccess.file_exists(_user_path)
	_create_btn.text = _host.tr("CUSTOM_FILE_RECREATE" if has_copy else "CUSTOM_FILE_CREATE")
	_drop_btn.disabled = not has_copy
	if not error_key.is_empty():
		_show(_host.tr(error_key), _ERROR_COLOR)
		return
	var bundled: String = FileAccess.get_file_as_string(_bundled_path)
	var user: String = FileAccess.get_file_as_string(_user_path) if has_copy else ""
	var state: State = assess(has_copy, user, bundled, _accepts, _entries_key)
	var path: String = ProjectSettings.globalize_path(_user_path)
	var text: String
	var color: Color = MenuStyle.TEXT_DIM
	match state:
		State.NONE:
			text = _host.tr("CUSTOM_FILE_STATUS_BUILT_IN")
		State.IN_USE:
			text = _host.tr("CUSTOM_FILE_STATUS_IN_USE") + "\n" + path
		State.OUTDATED:
			text = _host.tr(_outdated_key) % [_count(user), _count(bundled)] + "\n" + path
			color = _WARN_COLOR
		State.UNREADABLE:
			text = _host.tr("CUSTOM_FILE_STATUS_UNREADABLE") + "\n" + path
			color = _WARN_COLOR
	if needs_restart(state, _loaded_path.call(), _user_path):
		text += "\n" + _host.tr("CUSTOM_FILE_RESTART")
	_show(text, color)


# Which file the next launch reads. A copy the loader would reject is no copy
# as far as the game is concerned, so it reads UNREADABLE, never IN_USE.
static func assess(has_copy: bool, user_text: String, bundled_text: String,
		accepts: Callable, entries_key: String) -> State:
	if not has_copy:
		return State.NONE
	var user: Variant = _parse(user_text)
	if not accepts.call(user):
		return State.UNREADABLE
	if entries_key.is_empty():
		return State.IN_USE
	var bundled: Variant = _parse(bundled_text)
	if not bundled is Dictionary or not (bundled as Dictionary).get(entries_key) is Array:
		return State.IN_USE
	var have: int = ((user as Dictionary)[entries_key] as Array).size()
	var ship: int = ((bundled as Dictionary)[entries_key] as Array).size()
	return State.OUTDATED if have < ship else State.IN_USE


# Whether the file in use this session is not the one the next launch reads.
static func needs_restart(state: State, loaded_path: String, user_path: String) -> bool:
	var copy_next: bool = state == State.IN_USE or state == State.OUTDATED
	return copy_next != (loaded_path == user_path)


func _on_create_pressed() -> void:
	if FileAccess.file_exists(_user_path):
		_ask("CUSTOM_FILE_CONFIRM_RECREATE", _write_copy)
	else:
		_write_copy()


func _on_drop_pressed() -> void:
	_ask("CUSTOM_FILE_CONFIRM_USE_BUILT_IN", _drop_copy)


func _on_open_pressed() -> void:
	var target: String = _user_path if FileAccess.file_exists(_user_path) \
			else _user_path.get_base_dir()
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(target))


func _write_copy() -> void:
	var src := FileAccess.open(_bundled_path, FileAccess.READ)
	if src == null:
		refresh("CUSTOM_FILE_ERROR_NO_BUILT_IN")
		return
	var content: String = src.get_as_text()
	src.close()
	var dst := FileAccess.open(_user_path, FileAccess.WRITE)
	if dst == null:
		refresh("CUSTOM_FILE_ERROR_WRITE")
		return
	dst.store_string(content)
	dst.close()
	refresh()


func _drop_copy() -> void:
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(_user_path)) != OK:
		refresh("CUSTOM_FILE_ERROR_DELETE")
		return
	refresh()


func _ask(message_key: String, then: Callable) -> void:
	_pending = then
	_confirm.open(_host.tr(message_key), _host)


func _count(text: String) -> int:
	var data: Variant = _parse(text)
	if not data is Dictionary or not (data as Dictionary).get(_entries_key) is Array:
		return 0
	return ((data as Dictionary)[_entries_key] as Array).size()


# Null for text that is not JSON. JSON.parse_string would also log an engine
# error, and a player's half-edited copy is an expected state, not a fault.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


func _show(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _button(on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, _BUTTON_HEIGHT)
	btn.add_theme_font_size_override("font_size", _BUTTON_FONT_SIZE)
	btn.pressed.connect(on_pressed)
	SoundManager.wire_button(btn)
	return btn
