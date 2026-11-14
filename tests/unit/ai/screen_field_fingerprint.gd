extends RefCounted

# What the screen field was measured against: the goalie as the shot field's
# fingerprint reads him (its goalie directories and GameRules lines), plus the
# code that measures his screened shots. test_screen_field_is_current.gd fails when it
# no longer matches (.claude/hooks/generate-screen-field.sh). No class_name.

const ShotFingerprint := preload("res://tests/unit/ai/shot_field_fingerprint.gd")

const SOURCES: Array[String] = [
	"res://Scenes/Goalie.tscn",
	"res://Scripts/actors/goalie.gd",
	"res://Scripts/actors/keeper/keeper.gd",
	"res://Scripts/game/goalie_contact_detector.gd",
	"res://Scripts/domain/ai/goalie_skill_profile.gd",
	"res://Scripts/domain/rules/puck_authority_rules.gd",
	"res://Scripts/domain/rules/puck_geometry_collision.gd",
	"res://Scripts/domain/rules/shot_mechanics.gd",
	"res://Scripts/domain/rules/swept_disc_obb.gd",
	"res://tests/unit/ai/real_goalie_shot_harness.gd",
	"res://tests/unit/ai/shot_odds_stager.gd",
	"res://tests/instruments/keeper/keeper_state_cloner.gd",
	"res://tests/instruments/ai/test_generate_screen_field.gd",
]


static func compute() -> String:
	var paths: Array[String] = SOURCES.duplicate()
	for d: int in ShotFingerprint.GOALIE_DIRS.size():
		var dir: String = ShotFingerprint.GOALIE_DIRS[d]
		for f: String in DirAccess.get_files_at(dir):
			if f.begins_with(ShotFingerprint.GOALIE_PREFIXES[d]) and f.ends_with(".gd"):
				paths.append(dir.path_join(f))
	paths.sort()
	var text: String = ""
	for p: String in paths:
		text += p + "\n" + FileAccess.get_file_as_string(p)
	for line: String in FileAccess.get_file_as_string(ShotFingerprint.GAME_RULES).split("\n"):
		if line.contains("GOALIE") or line.contains("NET_") or line.begins_with("const GOAL_LINE_Z") \
				or line.contains("PUCK_COLLISION"):
			text += line + "\n"
	return text.replace("\r", "").md5_text()
