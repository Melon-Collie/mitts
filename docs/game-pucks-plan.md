# Game Pucks and Banners — progression design record

Status: **Phases 1–2 built** (the catalogue, the ledger, the Trophy Case and
titles); Phases 3–4 not started. Each phase ships as its own PR.

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
  playing badly on purpose. Goals, assists, interceptions, blocks, wins and
  hits are all safe to count.
- **Games against bots count for everything**, every tier and every banner,
  exactly as Steam career stats and achievements already count them
  (`GameManager._achievements_active`: any real match, never free play, the
  tutorial or drills). A player who wants to grind a banner out offline may.
- **Hits count as credited.** `HitTracker` already credits a hit only where the
  NHL would: on the puck carrier when the contact costs them the puck, or on a
  player finished just after they released it. So a hit puck counts the existing
  `hits` stat. Hit hunting within that definition is a real way to play.
- **Banners are named for how a player plays.** Power Forward is the model:
  50 goals and 50 hits raise it, and it unlocks the Power Forward title. The
  catalogue's banners are hockey archetypes, so the title a player wears says
  something true about their game.
- **Existing achievements fold into the catalogue.** The 20 achievements that
  shipped before it are Game Pucks now and keep their Steam ids, so nothing
  already unlocked on Steam is lost. The four career ones (Sniper, Setup Artist,
  Enforcer, Veteran) are tiers on the goals, assists, hits and games ladders.
  A puck already unlocked on Steam is imported into the ledger, with an unknown
  date, the next time the Trophy Case opens or a game ends.
- **Titles show on the lobby bench card, the scoreboard, the Three Stars and
  the post-game screen.** The on-ice nameplate stays name-only, since it is read
  at speed.
- **Store only what cannot be derived.** Count tiers are read off the Steam
  User Stats totals (`SteamStats`, cross-machine and independent of Supabase)
  every time, and banners off the pucks, so neither is stored. What is stored —
  the earned game, feat, event and roster pucks, and the equipped title — is a
  section of the preferences file Steam Cloud already syncs (`PlayerPrefs`), so
  no new Cloud file or Steamworks Cloud setting is involved. That file
  reconciles newest-write-wins; the ledger section merges as a union instead,
  since an earned puck is never un-earned.
- **Steam achievements are opt-in per puck.** A puck is mirrored to Steam only
  when its registry row is flagged for it. The existing 20 are flagged; nothing
  new is until it is worth the Steamworks setup (below). Puck, banner and title
  names are `locale/translations.csv` rows, never Steamworks strings.
- **No anti-cheat.** Pucks are evaluated on the player's own machine and anyone
  can set a Steam achievement directly, so a determined player can unlock any
  reward. For cosmetics and titles that is accepted. The host does not check
  that a peer owns the title or cosmetic it wears; it only clamps an unknown id
  to none, as `GearStyleConfig.from_code` does for gear codes.
- **Bots wear anything.** A bot's look may use reward cosmetics as freely as the
  free ones. Hand-tailored bot identities come later, once the cosmetics are
  stable.
- **Bots wear no title.** A title says what a player earned, so a bot's look
  never carries one.
- **The automatic career style is not a title yet.** The play-style label that
  would update itself from a player's career waits on its own plan.

## Steamworks work

Everything the code cannot do, per phase. Each item is done on both apps
(4892600 and the Playtest 4893650) and then published.

| when | item |
|---|---|
| Phase 1 | Define one INT stat, `STAT_INTERCEPTIONS` (`steam/STATS.md`). Points are goals + assists, so they need no stat. |
| any new counter | One INT stat per counter a ladder reads. |
| any puck flagged for Steam | One achievement: name, description, locked and unlocked icons (`steam/ACHIEVEMENTS.md`). Optional, so as many or as few as wanted. |

Pucks, tiers, banners, titles and cosmetic rewards need no Steamworks work.


## The model

### Game Pucks

One registry row per puck. Kinds:

| kind | earned when | evaluated |
|---|---|---|
| **count** | a lifetime counter reaches a tier | game-over, from `SteamStatRecorder.totals()` |
| **game** | one game's stat reaches a bar (3 goals in a game) | game-over (`GamePuckRules.earned_game`) |
| **feat** | a specific play happens (below) | the moment it happens, host-detected |
| **event** | a moment (a big hit, finishing the tutorial course) | its hook (`TrophyService.on_*`) |
| **roster** | a match whose lobby includes a named person | game-over (`GamePuckRules.earned_roster`) |

A count puck is a ladder: one row with tiers (10 / 50 / 250 / 1000 goals), each
tier its own puck to earn. Tiers ascend strictly, and a banner names the tier it
needs by its target (`goals@50`).

### Banners

A banner names the pucks (or puck tiers) it needs, all of them, and its reward.
Flat in v1: a banner needs pucks, never other banners. Its progress is how many
of its pucks are earned.

### Titles

A title is an id plus a locale key (`Titles`, `TITLE_<ID>`). A player wears at
most one, picked from the titles their raised banners have earned
(`GamePuckRules.earned_titles`) on the player screen's Title row, saved as a
pref, and it travels with their look: the join and spawn handshakes, the lobby
roster, the existing-player sync and the replay header. In v1 every title comes
from a banner. It shows under the name on the lobby slot card, after the name on
the scoreboard (`SCOREBOARD_NAME_TITLE`) and beside the name in the Three Stars
on the game-over screen.

### Catalogue

The rows live in `GamePucks.ALL` and `Banners.ALL`; Phase 1 shipped:

| banner | needs | title (Phase 2) |
|---|---|---|
| Power Forward | `goals@50` + `hits@50` | Power Forward |
| Shutdown | `interceptions@50` + `takeaways@50` + `shots_blocked@50` | Shutdown |
| Two-Way | `goals@50` + `assists@50` + `interceptions@50` + `takeaways@50` | Two-Way |
| Iron Man | `games_played@100` | Iron Man |

Planned with Phase 3, since each needs a feat: Playmaker (`assists@250` + a
one-timer assist feat) and Sniper (`goals@250` + a HIGH-loft goal from beyond
the dots).

Ladders: goals, assists, points, hits, interceptions, takeaways, blocks, faceoff
wins, wins and games, four or five tiers each. Every counter is a `SteamStats`
row (`STAT_INTERCEPTIONS` was added for this); points are goals + assists. A
ladder has at most as many tiers as `TrophyCopy.TIER_KEYS` has numerals.

Feats are where Mitts can stand out, since the mechanics are deep enough to
name specific plays: a backhand roof goal, a HIGH-loft goal from beyond the
dots, a one-timer goal off your own interception, a pin then a takeaway then a
goal inside 10 s, a stick lift leading to a goal. A Transition banner waits on
a carried-zone-entry counter, which nothing records yet.

## Architecture

Lower layers never reach up (CLAUDE.md → *Layer Architecture*).

**Domain** — pure, unit-tested:
- `domain/config/game_pucks.gd`: the puck registry. It replaced the old
  achievement registry and keeps its condition kinds, adding `count` ladders
  (and `feat` in Phase 3).
- `domain/config/banners.gd`: banner requirements (and, from Phase 2, rewards).
  `domain/config/titles.gd` arrives in Phase 2: title ids and their locale keys.
- `domain/state/trophy_ledger.gd`: the stored part only — the earned game,
  feat, event and roster pucks, and the equipped title — with its serialization
  and the union merge.
- `domain/rules/game_puck_rules.gd`: given the Steam counters, one game's stats
  and the ledger, which pucks, tiers and banners are earned, and each one's
  progress. Earning is idempotent: evaluating twice earns nothing new.

**Application:**
- `TrophyService` replaced the old achievement service: it evaluates at game-over
  and on events, writes the ledger into `PlayerPrefs`, unlocks the pucks flagged
  for Steam through `SteamManager`, and emits a signal for the earn toast.
- The feat channel. A feat is detected on the host, where the authoritative
  events are, and only the earning player records it. One RPC,
  `notify_feat(feat_id)`, carries every feat (CLAUDE.md → *New RPC*:
  `NetworkManager` → signal → `GameManager._wire_network_signals()`). Adding a
  feat is then a registry row and a host detector, never a wire change. Today
  each goal flavour is a `PlayerStats` field, which bumps the protocol per feat.

**Infrastructure and UI:**
- The Trophy Case screen (`TrophyCaseScreen`), beside Career on the side menu:
  banners with their pucks and progress, the ladders, and the single pucks.
  `TrophyCopy` holds the words it and the toast share.
- An earn toast on the HUD's toast stack, at game-over and live for moments.
- A title row in the player screen's YOU region (`PlayerTitleRow`).
- The title on the lobby slot card, the scoreboard and the Three Stars on the
  game-over screen.
- Locked cosmetics. A cosmetic registry option (`GearModelRegistry`,
  `StickModelRegistry`, the tape palette) may carry the banner that unlocks it.
  The picker shows a locked option with what earns it; the lobby relays what a
  player wears whether or not it is earned (*No anti-cheat*).

**Wire.** The title id joins `PlayerLook.cosmetics_to_wire()` (Phase 2) and
`notify_feat` adds an RPC (Phase 3); each bumps the protocol in its phase.

## Phases

1. **Catalogue and Trophy Case.** The registries, rules, ledger and
   `TrophyService`; the 20 achievements migrated as pucks; count ladders on the
   Steam counters, with `STAT_INTERCEPTIONS` added; a read-only Trophy Case with
   progress; the earn toast. No rewards yet.
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
  ledger is kept (a newer build's puck survives a round trip through an older
  one), and a malformed entry is skipped rather than failing the load.
- **Ledger merge:** merging two ledgers keeps every puck either holds, whichever
  copy is newer, so a Steam Cloud adopt never loses one.
- **Steam mirror:** every puck flagged for Steam is listed in
  `steam/ACHIEVEMENTS.md`, held by a test, not a comment.

## Not in scope

- The automatic play-style label (career and recent form) discussed alongside
  this. It can coexist — the label says how you play now, a banner says what you
  have done — and is its own plan.
- Drill medals and personal bests, which would become event pucks once drills
  record them.
