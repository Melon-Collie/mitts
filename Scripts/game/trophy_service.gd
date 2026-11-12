class_name TrophyService extends RefCounted
## Application glue between the Game Puck domain (GamePucks, GamePuckRules) and its two stores: the ledger in PlayerPrefs, synced through
## Steam Cloud, and the Steam achievements a puck is flagged to mirror. Owned by
## GameManager: evaluated at game-over and poked from live hooks. The domain
## decides what is earned; this records it, announces it and tells Steam.
##
## `totals_provider` returns the Steam User Stats totals
## (SteamStatRecorder.totals): ladders and the combos that need them are read
## off them.
## `ledger_provider` returns the ledger to write and `persist` saves it; both
## default to PlayerPrefs, whose ledger is a fresh object after a Steam Cloud
## adopt, so it is fetched on every use rather than held.

signal puck_earned(puck_id: String, target: int)  # target 0 for a single puck

var _totals_provider: Callable = Callable()
var _ledger_provider: Callable = Callable()
var _persist: Callable = Callable()
# Steam ids already handled this session, so a re-evaluation at every game-over
# does not re-query or re-issue them.
var _mirrored_this_session: Dictionary = {}


func _init(totals_provider: Callable = Callable(), ledger_provider: Callable = Callable(),
		persist: Callable = Callable()) -> void:
	_totals_provider = totals_provider
	_ledger_provider = ledger_provider if ledger_provider.is_valid() \
			else func() -> TrophyLedger: return PlayerPrefs.trophy_ledger
	_persist = persist if persist.is_valid() else PlayerPrefs.save


# The sweep at a finished game. `totals_before` is the Steam totals as they were
# before this game was recorded; the provider now answers with it counted.
# `ctx` is GamePuckRules.earned_game's context.
func evaluate_game_over(stats: PlayerStats, ctx: Dictionary, present_steam_ids: Array,
		local_steam_id: int, totals_before: Dictionary) -> void:
	var ledger: TrophyLedger = _ledger_provider.call()
	var changed: bool = import_steam_unlocks(ledger)
	var combos_before: Array[String] = GamePuckRules.earned_combos(totals_before, ledger)
	var earned: Array[String] = GamePuckRules.earned_roster(present_steam_ids, local_steam_id)
	if stats != null:
		earned.append_array(GamePuckRules.earned_game(GamePuckRules.game_dict(stats), ctx))
	var now: int = int(Time.get_unix_time_from_system())
	for id: String in earned:
		if ledger.earn(id, now):
			changed = true
			puck_earned.emit(id, 0)
	var totals_after: Dictionary = _totals()
	for crossed: Dictionary in GamePuckRules.crossed_tiers(totals_before, totals_after):
		puck_earned.emit(String(crossed["id"]), int(crossed["target"]))
	_announce_combos(combos_before, totals_after, ledger)
	if changed:
		_persist.call()
	_mirror(totals_after, ledger)


# The local player landed a body check of `impulse` (SkaterVFX's units).
func on_local_hit(impulse: float) -> void:
	var threshold: float = GamePucks.event_threshold("big_hit")
	if threshold >= 0.0 and impulse >= threshold:
		_earn_now(GamePucks.event_puck("big_hit"))


# Every tutorial is complete. Outside a match, so it bypasses the game-over
# sweep and its free-play gate.
func on_tutorials_complete() -> void:
	_earn_now(GamePucks.event_puck("tutorials_done"))


# The host saw this player make a feat play (FeatRules); anything not a feat
# puck is ignored, so a forged id earns nothing.
func on_feat(puck_id: String) -> void:
	if GamePucks.kind_of(GamePucks.find(puck_id)) == "feat":
		_earn_now(puck_id)


# The player was on the ice when their club won a tournament's final.
func on_cup_won() -> void:
	_earn_now(GamePucks.event_puck("cup_won"))


# The player applied a custom build in free play.
func on_build_edited() -> void:
	_earn_now(GamePucks.event_puck("build_edited"))


# Records in `ledger` every mirrored stored puck Steam already shows unlocked —
# an achievement earned before the ledger existed, or on a machine whose prefs
# never synced — with an unknown date. Returns true when the ledger grew.
static func import_steam_unlocks(ledger: TrophyLedger) -> bool:
	if not SteamManager.is_available:
		return false
	var changed: bool = false
	for entry: Dictionary in GamePucks.ALL:
		if not entry.has("steam") or GamePucks.is_combo(entry) \
				or ledger.has(String(entry["id"])):
			continue
		if SteamManager.is_achievement_unlocked(String(entry["steam"])):
			changed = ledger.earn(String(entry["id"]), 0) or changed
	return changed


func _earn_now(id: String) -> void:
	var ledger: TrophyLedger = _ledger_provider.call()
	if id.is_empty() or ledger.has(id):
		return
	var totals: Dictionary = _totals()
	var combos_before: Array[String] = GamePuckRules.earned_combos(totals, ledger)
	ledger.earn(id, int(Time.get_unix_time_from_system()))
	puck_earned.emit(id, 0)
	_announce_combos(combos_before, totals, ledger)
	_persist.call()
	_mirror(totals, ledger)


# A combo is announced like any puck, once the last thing it needs is earned.
func _announce_combos(combos_before: Array[String], totals: Dictionary,
		ledger: TrophyLedger) -> void:
	for id: String in GamePuckRules.earned_combos(totals, ledger):
		if not combos_before.has(id):
			puck_earned.emit(id, 0)


# Unlocks every flagged Steam achievement the ledger and totals have earned that
# Steam does not show yet, including any earned while Steam was unavailable.
func _mirror(totals: Dictionary, ledger: TrophyLedger) -> void:
	if not SteamManager.is_available:
		return
	for id: String in GamePuckRules.earned_steam_ids(totals, ledger):
		if _mirrored_this_session.has(id):
			continue
		_mirrored_this_session[id] = true
		if not SteamManager.is_achievement_unlocked(id):
			SteamManager.unlock_achievement(id)


func _totals() -> Dictionary:
	return _totals_provider.call() if _totals_provider.is_valid() else {}
