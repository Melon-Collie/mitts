class_name UpdateChecker
extends Label

# Queries the GitHub Releases API on startup and shows an "update available"
# message when the running build's version doesn't match the latest release's
# name. No downloading, no file manipulation — just a nudge to go grab the
# new zip. Skipped entirely when BuildInfo.VERSION == "dev" so local editor
# runs don't spam the API or flash an "update available" label.

const _API_URL_FMT: String = "https://api.github.com/repos/%s/releases/tags/%s"
const _DOWNLOAD_URL_FMT: String = "https://github.com/%s/releases/tag/%s"
const _REQUEST_TIMEOUT: float = 5.0

var _http: HTTPRequest

func _ready() -> void:
	visible = false
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_color", Color(1.00, 0.85, 0.20, 1.00))
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if BuildInfo.VERSION == "dev":
		return

	_http = HTTPRequest.new()
	_http.timeout = _REQUEST_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	var url: String = _API_URL_FMT % [BuildInfo.REPO, BuildInfo.RELEASE_TAG]
	var headers: PackedStringArray = ["Accept: application/vnd.github+json", "User-Agent: HockeyGame-UpdateChecker"]
	var err: int = _http.request(url, headers)
	if err != OK:
		push_warning("UpdateChecker: HTTPRequest.request() failed with error %d" % err)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var latest: String = String(parsed.get("name", ""))
	if latest.is_empty() or latest == BuildInfo.VERSION:
		return
	text = "Update available: %s (you have %s)\n%s" % [latest, BuildInfo.VERSION, _DOWNLOAD_URL_FMT % [BuildInfo.REPO, BuildInfo.RELEASE_TAG]]
	visible = true
