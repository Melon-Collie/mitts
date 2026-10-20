extends GutTest

# Two ratchets on the shape of Scripts/: how long a file may be, and how wide
# its public surface may be. Both only ever tighten.
#
# The audit that produced them found five root causes, and this is the guard for
# the one no cleanup can fix by itself: nothing stopped a file from growing.
# Every god class here got that way one reasonable commit at a time, and each of
# those commits was correct in isolation. A ratchet is the only thing that makes
# the aggregate visible at the moment it moves.
#
# HOW IT WORKS. A file not named in the table must stay under the limit — that
# is the real guard, covering ~310 of the 341 files. The tables are the
# grandfather list: every file already over the limit when the ratchet went in,
# pinned at the size it was. They are the backlog, made un-growable rather than
# hidden.
#
# WHEN IT FIRES, there are three things it can be saying:
#
#   · "grew past its allowance" — you added lines to a file that is already too
#     big. Splitting is the intended answer. Bumping the number is ALLOWED and
#     is not cheating: the ratchet's job is to make growth deliberate and
#     visible in the diff, not impossible. Say why in the commit message.
#   · "shrank well below its allowance" — you won something; bank it. Tighten
#     the entry to the new number so the space cannot be re-spent quietly. This
#     is the click that makes it a ratchet instead of a cap.
#   · "is now under the limit" — the file graduated. Delete its entry.
#
# WHAT THE NUMBERS MEAN. 800 lines is roughly the point past which an agent
# reads a file partially and edits it blind, which is the failure this codebase
# actually suffers. 25 public functions is the point past which "what does this
# class do" stops having a one-sentence answer. Neither is a law of nature;
# both are the line where the cost showed up here.
#
# Two entries in the API table are deliberate and will never come down, and it
# is worth knowing which before trying:
#   · network_manager.gd (204) — 115 are receive_*/send_*/notify_*. Godot
#     dispatches @rpc by name on the node, so that IS the wire protocol.
#   · player_attributes.gd (41) — one accessor per body dial, by design.
#
# Scope is Scripts/ only. A long test is not the same cost as a long subsystem,
# and addons/ is vendored. Generated data under _GENERATED_DIR is a measurement
# written as constants, never read or edited by hand, so it is not counted.

const _SIZE_LIMIT: int = 800
const _GENERATED_DIR: String = "res://Scripts/domain/ai/generated/"
# Slack before an un-banked win is reported, so ordinary edits inside a listed
# file don't demand a table update on every commit.
const _SIZE_SLACK: int = 40

const _SIZE_ALLOWANCE: Dictionary[String, int] = {
	# +11: the cross-check collaborator held and applied (apply_cross_check).
	"res://Scripts/ai/skater_agent_state_machine.gd": 3680,
	# +6: tutorial_place_puck, the tutorial's seam onto the scripted park below.
	# +61: the cross-check — its tracker and resolver wired, the claim deferred,
	# the landed shove's burst, thud and knockback lead on every machine, and its
	# replay event; the pin ticked before the tie.
	# +5: the spectator set is marked before a demotion's despawn and around a
	# promotion's spawn, which RosterAnnouncer reads to label the move.
	# +11: the goal replay's frame signal and its relay, the team on every replay
	# touch event, and the recorder's post-goal tail gate.
	"res://Scripts/game/game_manager.gd": 5870,
	# +17: the threat tracker's jitter filter moved onto the puck offset, which
	# needs a second filter state and its priming. The design prose went to
	# Scripts/controllers/CLAUDE.md rather than inline, and the tunable
	# doc-blocks it duplicated were trimmed, so the growth here is code.
	# +7: the puck-velocity estimate is bounded by the puck's own speed limit.
	# It is a one-tick finite difference feeding a positional decision, so a
	# teleport read as travel moved the tracked threat metres in a tick.
	"res://Scripts/controllers/goalie_controller.gd": 5075,
	"res://Scripts/domain/ai/role_behaviors/carrier.gd": 842,
	# +33: the dive takes the knockdown's fall its own way — a thrown tip rate,
	# no rebound, legs long, the belt kept on his line — and stays down while
	# block is held. +5: a bot's caps carry its wrist-shot load and facing configs.
	# +10: the staged get-up's one clock (knockdown_getup_left) and the stagger
	# he finds his legs through once it ends. +36: the get-up's stick hold. +5:
	# the down flags in one place, a diver's stick dead from the get-up.
	# +3: rom_forward_reach_max, the half-ellipse rim's straight-ahead reach.
	# +50: the cross-check — its phase stepped from the Ctrl+F chord and adopted on
	# reconcile, and the victim's answer to it (take_cross_check).
	# +3: the stagger reads how hard a hit landed, apart from the knockdown.
	# +6: the press latches the cursor's aim, as far round as the chest turns.
	"res://Scripts/controllers/skater_controller.gd": 3606,
	# +1: dive_laid_out, the diver's stick and low block until the get-up.
	# +11: the physicality plan — a locked pin pair's flat contact, the
	# cross-check's phase fields (read by puck play and the pose), and the
	# body_check_received signal carrying the stagger strength.
	# +2: the aim the cross-check was thrown at.
	"res://Scripts/actors/skater.gd": 2823,
	# +33: the cross-check claim and its landed broadcast (two RPC pairs).
	"res://Scripts/networking/network_manager.gd": 2899,
	"res://Scripts/game/tutorial_manager.gd": 2067,
	# +54: the top hand is solved in the arm's level frame from the drawn
	# shoulder, and a carrier's reach stops where the bottom hand lets go
	# (_two_hand_reach, _carry_backhand_stop).
	# +39: the cross-check pose — the shaft across the chest, the wide grip.
	# +8: _glove_spacing, the shaft the top glove takes up, which the drawn
	# bottom grip and the carry's two-handed reach both keep clear of.
	"res://Scripts/controllers/skater_ik_coordinator.gd": 1185,
	# +21: apply_scripted_grant / stage_scripted — the tutorial's teleports
	# restart the swept interaction tests where the puck lands instead of
	# sweeping the jump. +6: the pinch hop composed onto the contest exit.
	# +4: a cross-checking stick plays no puck.
	"res://Scripts/controllers/puck_controller.gd": 1668,
	"res://Scripts/actors/hockey_rink.gd": 1469,
	"res://Scripts/game/player_prefs.gd": 1342,
	# +20: helmet_rim_y, the rim's height as built, which the hair reads to hide
	# its top edge under the shell — the one source of the rim profile.
	# +41: the glove's stations (knuckle and finger rolls) and the forearm's
	# wrist neck, the mesh that keeps the sleeve inside the glove. +2:
	# GLOVE_FIST_SPAN, the fist's width the bottom grip keeps clear of.
	"res://Scripts/actors/skater_mesh_builder.gd": 1525,
	"res://Scripts/domain/rules/goalie_behavior_rules.gd": 1304,
	"res://Scripts/ui/career_stats_screen.gd": 1271,
	"res://Scripts/ui/lobby_manager.gd": 1247,
	# +8: the strip reads the wall-backed hit when the boards are behind the carrier.
	"res://Scripts/actors/puck.gd": 1137,
	"res://Scripts/ui/side_menu.gd": 995,
	"res://Scripts/controllers/goalie_body_config_builder.gd": 1131,
	"res://Scripts/ui/network_debug_overlay.gd": 956,
	"res://Scripts/networking/network_telemetry.gd": 968,
	# +1: a cross-checking stick sends no pickup or poke claim.
	"res://Scripts/controllers/local_controller.gd": 950,
	# Main's resumable sample prediction and the board pin's forward cap crossed the
	# limit together, each from under it, at the merge that joined them.
	# +2: the cross-check phase applied off the wire.
	"res://Scripts/controllers/remote_controller.gd": 824,
	# +65: the hair rows (style, beard, colour) beside the skin, and the
	# option/swatch row builders the skin and hair share.
	"res://Scripts/ui/player_settings_popup.gd": 908,
	"res://Scripts/ui/slot_grid_panel.gd": 839,
	"res://Scripts/domain/state/game_state_machine.gd": 816,
	"res://Scripts/ui/locker_popup.gd": 823,
	"res://Scripts/ui/hud.gd": 822,
}

const _API_LIMIT: int = 25
const _API_SLACK: int = 3

const _API_ALLOWANCE: Dictionary[String, int] = {
	# +4: send/receive_cross_check_claim, send_cross_check_to_all, notify_cross_check.
	"res://Scripts/networking/network_manager.gd": 212,
	"res://Scripts/actors/skater.gd": 148,
	"res://Scripts/game/game_manager.gd": 63,
	"res://Scripts/domain/state/player_attributes.gd": 41,
	"res://Scripts/networking/network_telemetry.gd": 54,
	# +1: knockdown_drop_m, which the gait's crumple and the sprawl's buckle share.
	# +1: knockdown_getup_left, the get-up clock the gait and the torso fold read.
	# +1: take_cross_check, the victim's answer the host's CrossCheckTracker calls.
	"res://Scripts/controllers/skater_controller.gd": 45,
	"res://Scripts/actors/puck.gd": 44,
	"res://Scripts/domain/state/game_state_machine.gd": 39,
	"res://Scripts/domain/rules/goalie_behavior_rules.gd": 36,
	# +1: helmet_rim_y (see the size entry).
	# +1: shared_forearm_bone, which the locker mannequin and lobby dummies wear.
	"res://Scripts/actors/skater_mesh_builder.gd": 32,
	"res://Scripts/controllers/puck_controller.gd": 32,
	"res://Scripts/game/shot_on_goal_tracker.gd": 26,
	"res://Scripts/actors/goalie.gd": 26,
}


func _all_files(root: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	for d: String in dir.get_directories():
		out.append_array(_all_files("%s/%s" % [root, d], suffix))
	for f: String in dir.get_files():
		if f.ends_with(suffix):
			out.append("%s/%s" % [root, f])
	return out


# Lines as an editor shows them: a trailing newline does not open a new one.
func _line_count(path: String) -> int:
	var src: String = FileAccess.get_file_as_string(path)
	if src.ends_with("\n"):
		src = src.substr(0, src.length() - 1)
	return src.split("\n").size()


# Functions the file offers to other files: declared at column 0 (an inner
# class's methods are that class's surface, not this one's) and not `_`-prefixed.
func _public_func_count(path: String) -> int:
	var re := RegEx.create_from_string("^(static )?func [a-z][a-zA-Z0-9_]*\\(")
	var n: int = 0
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if re.search(line) != null:
			n += 1
	return n


# The shared ratchet. `measure` maps a path to its number; everything else is
# the same four rules for both axes.
func _assert_ratchet(allowance: Dictionary[String, int], limit: int, slack: int,
		unit: String, measure: Callable, remedy: String) -> void:
	var seen: Dictionary[String, bool] = {}
	for path: String in _all_files("res://Scripts", ".gd"):
		if path.begins_with(_GENERATED_DIR):
			continue
		var measured: int = measure.call(path)
		seen[path] = true
		if not allowance.has(path):
			if measured > limit:
				fail_test(("%s is %d %s, over the %d limit. %s — or add it to the " +
						"table in test_no_god_class_growth.gd if it genuinely has to " +
						"be this big, and say why in the commit.")
						% [path, measured, unit, limit, remedy])
			continue
		var allowed: int = allowance[path]
		if measured <= limit:
			fail_test(("%s is down to %d %s, under the %d limit — it graduated. " +
					"Delete its entry from the table.") % [path, measured, unit, limit])
		elif measured > allowed:
			fail_test(("%s grew to %d %s, past its allowance of %d. %s. Bumping the " +
					"entry is allowed and visible in the diff — but it is a decision, " +
					"so say why in the commit message.")
					% [path, measured, unit, allowed, remedy])
		elif measured < allowed - slack:
			fail_test(("%s is down to %d %s from an allowance of %d. Bank it: tighten " +
					"the entry to %d so the space cannot be re-spent quietly.")
					% [path, measured, unit, allowed, measured])
	for path: String in allowance:
		if not seen.has(path):
			fail_test("%s no longer exists; drop its stale entry from the table." % path)
	# A ratchet that scanned nothing passes silently, which is the one way this
	# can rot into decoration. Scripts/ has ~340 .gd files.
	assert_gt(seen.size(), 250, "the %s scan must actually reach Scripts/" % unit)


func test_no_file_grows_past_its_allowance() -> void:
	_assert_ratchet(_SIZE_ALLOWANCE, _SIZE_LIMIT, _SIZE_SLACK, "lines",
			_line_count, "Split it, or move the prose to its area CLAUDE.md")


func test_no_class_widens_past_its_allowance() -> void:
	_assert_ratchet(_API_ALLOWANCE, _API_LIMIT, _API_SLACK, "public functions",
			_public_func_count,
			"Split it, or make the callers go through fewer entry points")
