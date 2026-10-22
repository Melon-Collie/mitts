extends RefCounted

# What the shot field was measured against: a hash of every source that decides
# whether the live goalie stops a shot, plus the code that measures him. The
# generator stamps it into AIShotFieldData; test_shot_field_is_current.gd fails
# when it no longer matches, which is the cue to regenerate
# (.claude/hooks/generate-shot-field.sh). No class_name (test infra).

const SOURCES: Array[String] = [
	"res://Scenes/Goalie.tscn",
	"res://Scripts/actors/goalie.gd",
	"res://Scripts/actors/goalie_skates.gd",
	"res://Scripts/actors/goalie_toe_bridge.gd",
	"res://Scripts/game/goalie_contact_detector.gd",
	"res://Scripts/domain/ai/goalie_skill_profile.gd",
	"res://Scripts/domain/rules/puck_authority_rules.gd",
	"res://Scripts/domain/rules/puck_geometry_collision.gd",
	"res://Scripts/domain/rules/shot_mechanics.gd",
	"res://Scripts/domain/rules/swept_disc_obb.gd",
	"res://tests/unit/ai/real_goalie_shot_harness.gd",
	"res://tests/unit/ai/shot_odds_stager.gd",
	"res://tests/instruments/ai/test_generate_shot_field.gd",
]
# Every file in these directories whose name starts with "goalie_".
const GOALIE_DIRS: Array[String] = [
	"res://Scripts/controllers",
	"res://Scripts/domain/rules",
]
# GameRules holds the goalie's league defaults among everything else; only its
# goalie lines and the puck's size count, so an unrelated rule change does not
# stale the field.
const GAME_RULES: String = "res://Scripts/domain/config/game_rules.gd"


static func compute() -> String:
	var paths: Array[String] = SOURCES.duplicate()
	for dir: String in GOALIE_DIRS:
		for f: String in DirAccess.get_files_at(dir):
			if f.begins_with("goalie_") and f.ends_with(".gd"):
				paths.append(dir.path_join(f))
	paths.sort()
	var text: String = ""
	for p: String in paths:
		text += p + "\n" + FileAccess.get_file_as_string(p)
	for line: String in FileAccess.get_file_as_string(GAME_RULES).split("\n"):
		if line.contains("GOALIE") or line.contains("PUCK_COLLISION"):
			text += line + "\n"
	# A Windows checkout may carry CRLF; the hash must not depend on it.
	return text.replace("\r", "").md5_text()
