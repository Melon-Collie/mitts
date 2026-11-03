# Game Pucks and Banners — progression design record

Status: **proposed**, nothing built. Each phase below ships as its own PR.

A progression system on the model of Darktide's Penances. A long catalogue of
achievements (**Game Pucks**) records what a player has done. Completing a named
set of them raises a **Banner**, and a banner unlocks a reward: a **title**
(new feature) or a cosmetic. Both live on one screen, the **Trophy Case**.

The names come from hockey. A player keeps the puck from a milestone — the
first goal, the hundredth point — taped and dated; a team raises a banner to the
rafters for something bigger.

## Decisions banked

- **Rewards are cosmetic or a title, never play.** `docs/attributes-v4-plan.md`
  rules out unlocking anything that changes how a skater plays ("no unlocks,
  ever" for gear; cosmetics are "orthogonal, zero balance cost"). That line is
  this system's first rule: a gear option with a tradeoff on a mechanic is never
  a reward, and a cosmetic that is a reward changes nothing gameplay reads.
- **Nothing anyone has today gets locked.** Every cosmetic in the player screen
  now stays free. Rewards are new content: titles, and new cosmetic options
  added for the purpose.
- **Counting pucks reward play that wins hockey games.** Mitts is PvP; a player
  chasing a puck spends their teammates' and opponents' game, not only their
  own (Darktide is co-op against AI, where it mostly costs the player's own
  run). So no puck pays for losing, for padding a stat in a blowout, or for
  playing badly on purpose. Goals, assists, interceptions, blocks and wins are
  safe to count. A raw hit count is the borderline case (see *Open questions*).
- **Banners are named for how a player plays.** Power Forward is the model:
  50 goals and 50 hits raise it, and it unlocks the Power Forward title. The
  catalogue's banners are hockey archetypes, so the title a player wears says
  something true about their game.
- **Existing achievements fold into the catalogue.** The 20 rows in
  `Achievements.ALL` become Game Pucks and keep their ids, so nothing already
  unlocked on Steam is lost.

## Open questions

Each has a recommendation; none is settled.

1. **Do games against bots count?** Today Steam career stats and achievements
   count every real match (`GameManager._achievements_active`), bots included,
   and most play is against bots. But bot games inflate numbers — a 55%
   shooting percentage over 22 games is the reference case. Options:
   - count every real match (accessible; farmable);
   - count bot games only at the top difficulty;
   - count everything for the lower tiers, and require games against humans for
     the top tiers and the banners.

   *Recommendation:* the third. It needs the Steam counters split by whether the
   match had human opponents (`career_stats.human_players` already records the
   headcount), so it is decided before Phase 1 fixes the counter set.
2. **Where unlocks are stored.** *Recommendation:* lifetime counters stay in
   Steam User Stats (`SteamStats`, already cross-machine and independent of
   Supabase). The set of earned pucks and banners lives in a local ledger file
   mirrored to Steam Cloud the way `PlayerPrefs` already is; the equipped title
   is a pref. Supabase is the alternative, but it needs stat sharing on and a
   reachable backend.
3. **Which pucks are also Steam achievements.** Every Steam achievement is hand
   set up in Steamworks for both apps, with two icons each (`steam/ACHIEVEMENTS.md`);
   a catalogue of a hundred-plus pucks makes that a burden. *Recommendation:* the
   catalogue is in-game, and a curated subset — the existing 20, the milestone
   tiers, the best feats — mirrors to Steam.
4. **Where a title shows.** *Recommendation:* the lobby bench card, the
   scoreboard, the Three Stars and the post-game screen. The on-ice nameplate
   stays name-only, since it is read at speed.
5. **Cheating.** Pucks are evaluated on the player's own machine and anyone can
   set a Steam achievement directly, so a determined player can unlock any
   reward. *Recommendation:* accept it for cosmetics and titles, and build no
   anti-cheat. The host does not check that a peer owns the title or cosmetic it
   wears; it only clamps an unknown id to none, as `GearStyleConfig.from_code`
   does for gear codes.
6. **What a hit puck counts.** Raw hits invite running around for contact.
   *Recommendation:* count hits that strip the puck (`HitTracker` already credits
   a hit through the strip path) or that land in the defensive zone, which needs
   a counter of its own.
7. **Do bots wear reward cosmetics?** *Recommendation:* no. A bot's look draws
   from the free options only, so a reward stays something a human earned.

## The model

### Game Pucks

One registry row per puck. Kinds:

| kind | earned when | evaluated |
|---|---|---|
| **count** | a lifetime counter reaches a tier | game-over, from `SteamStatRecorder.totals()` |
| **game** | one game's stat reaches a bar (3 goals in a game) | game-over (`AchievementRules.earned_game`) |
| **feat** | a specific play happens (below) | the moment it happens, host-detected |
| **event** | a moment outside a match (finish the tutorial course) | its hook (`AchievementService.on_*`) |
| **roster** | a match whose lobby includes a named person | game-over (`AchievementRules.earned_roster`) |

A count puck is a ladder: one row with tiers (10 / 50 / 250 / 1000 goals), each
tier its own puck to earn. Tiers ascend strictly, and a banner names the tier it
needs (`goals@2`).

### Banners

A banner names the pucks (or puck tiers) it needs, all of them, and its reward.
Flat in v1: a banner needs pucks, never other banners. Its progress is how many
of its pucks are earned.

### Titles

A title is an id plus a locale key. A player wears at most one, picked from the
titles they have earned, and it travels with their look. In v1 every title comes
from a banner.

### Starter catalogue (illustrative, not final)

| banner | needs | title |
|---|---|---|
| Power Forward | Goals II (50) + Hits II (50) | Power Forward |
| Playmaker | Assists III (250) + one-timer assist feat | Playmaker |
| Sniper | Goals III (250) + Snipe feat (HIGH loft from beyond the dots) | Sniper |
| Shutdown | Interceptions II + Takeaways II + Blocks II | Shutdown |
| Two-Way | Goals II + Assists II + Interceptions II + Takeaways II | Two-Way |
| Iron Man | Games III | Iron Man |

Count pucks for the ladders: goals, assists, points, wins, games, interceptions,
takeaways, blocks, faceoff wins, hits (see question 6). `SteamStats` has most of
these already; interceptions and points need rows.

Feats are where Mitts can stand out, since the mechanics are deep enough to
name specific plays: a backhand roof goal, a HIGH-loft goal from beyond the
dots, a one-timer goal off your own interception, a pin then a takeaway then a
goal inside 10 s, a stick lift leading to a goal. A Transition banner waits on
a carried-zone-entry counter, which nothing records yet.

## Architecture

Lower layers never reach up (CLAUDE.md → *Layer Architecture*).

**Domain** — pure, unit-tested:
- `domain/config/game_pucks.gd`: the puck registry. Replaces `Achievements.ALL`
  and keeps its condition kinds, adding `count` ladders and `feat`.
- `domain/config/banners.gd` and `domain/config/titles.gd`: banner
  requirements and rewards; title ids and their locale keys.
- `domain/state/trophy_ledger.gd`: the earned set (pucks, tiers, banners) and
  the equipped title, with its serialization.
- `domain/rules/game_puck_rules.gd`: given counters, one game's stats and the
  ledger, which pucks and banners are newly earned, and each one's progress.
  Earning is idempotent: evaluating twice earns nothing new.

**Application:**
- `TrophyService` grows out of `AchievementService`: it evaluates at game-over
  and on events, writes the ledger, mirrors the curated subset to Steam through
  `SteamManager`, and emits a signal for the earn toast.
- The feat channel. A feat is detected on the host, where the authoritative
  events are, and only the earning player records it. One RPC,
  `notify_feat(feat_id)`, carries every feat (CLAUDE.md → *New RPC*:
  `NetworkManager` → signal → `GameManager._wire_network_signals()`). Adding a
  feat is then a registry row and a host detector, never a wire change. Today
  each goal flavour is a `PlayerStats` field, which bumps the protocol per feat.

**Infrastructure and UI:**
- The Trophy Case screen, beside Career on the side menu: banners with their
  pucks and progress, the ladders, and what each banner unlocks.
- An earn toast at game-over, and live for feats.
- A title row in the player screen's YOU region.
- The title on the lobby bench card, scoreboard, Three Stars and post-game
  screen.
- Locked cosmetics. A cosmetic registry option (`GearModelRegistry`,
  `StickModelRegistry`, the tape palette) may carry the banner that unlocks it.
  The picker shows a locked option with what earns it; the lobby relays what a
  player wears whether or not it is earned (question 5).

**Wire.** The title id joins `PlayerLook.cosmetics_to_wire()`, and
`notify_feat` adds an RPC; one protocol bump covers both, in Phase 2.

## Phases

1. **Catalogue and Trophy Case.** The registries, rules, ledger and
   `TrophyService`; the 20 achievements migrated as pucks; count ladders on the
   Steam counters (with the human-game split if question 1 lands that way); a
   read-only Trophy Case with progress; the earn toast. No rewards yet.
2. **Titles.** The title registry, banners that award them, the title picker,
   the title on the wire and on screen. Protocol bump.
3. **Feats.** The `notify_feat` channel and the first feats, with their banners.
4. **Cosmetic rewards.** Lock flags on new cosmetic options and the art for
   them: helmet stickers, special stick colorways, tape patterns, glove designs.

## Tests

- **Registry integrity:** every banner requirement names a real puck and an
  existing tier; tiers ascend; every count puck's counter is backed by a
  `SteamStats` row (extending the consistency test in
  `tests/unit/game/test_steam_stat_recorder.gd`); every title and puck has its
  locale rows.
- **Rules properties:** a puck earned stays earned; a higher counter never earns
  fewer tiers; a banner is earned exactly when its last requirement is.
- **Ledger round-trip:** serialize, reload, compare; an unknown id in a saved
  ledger is dropped rather than failing the load.
- **Steam mirror:** every puck flagged for Steam is listed in
  `steam/ACHIEVEMENTS.md`, held by a test, not a comment.

## Not in scope

- The automatic play-style label (career and recent form) discussed alongside
  this. It can coexist — the label says how you play now, a banner says what you
  have done — and is its own plan.
- Drill medals and personal bests, which would become event pucks once drills
  record them.
