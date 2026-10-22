extends SceneTree

# Compiles every project script so the analyzer reports on each — the half of
# .claude/hooks/check-godot-warnings.sh that runs inside Godot. Run it through
# that hook: it is the hook's override.cfg, raising every warning to an error,
# that makes a warning print at all outside the editor's debugger.
#
#   -- --levels   print the override lines: every warning the project leaves at
#                 WARN, raised to ERROR. Read from ProjectSettings, so a warning
#                 a newer engine adds is gated without editing this file, and
#                 one the project silences (integer_division) stays silent.
#   (no args)     load every .gd outside addons/, dot-directories, and any
#                 directory holding a project.godot or .gdignore.

const _WARNINGS_PREFIX: String = "debug/gdscript/warnings/"
const _WARN: int = 1
const _ERROR: int = 2


func _init() -> void:
	if OS.get_cmdline_user_args().has("--levels"):
		_print_levels()
	else:
		var paths: PackedStringArray = []
		_collect("res://", paths)
		for path: String in paths:
			load(path)
		print("[gdscript-warning-scan] compiled %d scripts" % paths.size())
	quit()


func _print_levels() -> void:
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key: String = prop.name
		if not key.begins_with(_WARNINGS_PREFIX):
			continue
		var level: Variant = ProjectSettings.get_setting(key)
		if typeof(level) == TYPE_INT and int(level) == _WARN:
			print("%s=%d" % [key.trim_prefix("debug/"), _ERROR])


func _collect(dir: String, out: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or sub == "addons":
			continue
		var path: String = dir.path_join(sub)
		# Skipped as the editor's filesystem scan skips them: a nested project
		# (godot-cpp's test project) is not ours to compile.
		if FileAccess.file_exists(path.path_join("project.godot")) \
				or FileAccess.file_exists(path.path_join(".gdignore")):
			continue
		_collect(path, out)
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			out.append(dir.path_join(file))
