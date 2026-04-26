class_name NameFilter

const _WORD_LIST_PATH := "res://Data/censored_words.txt"

static var _words: Array[String] = []
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var file := FileAccess.open(_WORD_LIST_PATH, FileAccess.READ)
	if not file:
		_loaded = true
		return
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges().to_lower()
		if not line.is_empty():
			_words.append(line)
	_loaded = true

static func _normalize(name: String) -> String:
	var s: String = name.to_lower()
	s = s.replace("4", "a").replace("@", "a")
	s = s.replace("3", "e")
	s = s.replace("0", "o")
	s = s.replace("1", "i").replace("!", "i")
	s = s.replace("5", "s").replace("$", "s")
	return s

static func is_alphanumeric(player_name: String) -> bool:
	for i: int in range(player_name.length()):
		var code: int = player_name.unicode_at(i)
		var digit: bool = code >= 48 and code <= 57
		var upper: bool = code >= 65 and code <= 90
		var lower: bool = code >= 97 and code <= 122
		if not (digit or upper or lower):
			return false
	return true

static func is_clean(player_name: String) -> bool:
	_ensure_loaded()
	var normalized: String = _normalize(player_name)
	for word: String in _words:
		if normalized.contains(word):
			return false
	return true
