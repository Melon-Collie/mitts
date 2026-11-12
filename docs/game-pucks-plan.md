# Game Pucks — progression design record

Status: **Phases 1–4 built** (the catalogue, the ledger, the Trophy Case,
titles, feats, and cosmetic rewards: free colours, signature tape jobs, sticks
as patterns), and Phase 5 (one kind of puck: banners became combo pucks, any
puck or tier can unlock something, and the cosmetics are priced on them).

A progression system on the model of Darktide's Penances. A long catalogue of
achievements (**Game Pucks**) records what a player has done, and a puck can
unlock a reward: a **title** or a cosmetic. Some pucks are a single play or a
single game, some a career milestone, and some are earned by earning other
pucks. They all live on one screen, the **Trophy Case**.

The name comes from hockey: a player keeps the puck from a milestone — the
first goal, the hundredth point — taped and dated.

## Decisions banked

- **Rewards are cosmetic or a title, never play.** `docs/attributes-v4-plan.md`
  rules out unlocking anything that changes how a skater plays ("no unlocks,
  ever" for gear; cosmetics are "orthogonal, zero balance cost"). That line is
  this system's first rule: a gear option with a tradeoff on a mechanic is never
  a reward, and a cosmetic that is a reward changes nothing gameplay reads.
- **Colour picks are team, team 2, white and black.** The shared tape palette
  (blade tape, knob, laces, and the stick's paint) offers only the kit's
  primary and secondary colours, white and black. The other colours leave the
  picker but stay in the data, so old codes and bots still decode them; one
  comes back only as a specific reward where it makes sense. A saved pick that
  is no longer available switches to the team colour. (This replaces an
  earlier "nothing anyone has today gets locked" rule: the other colours looked
  wrong against most kits, and players were not using them.)
- **An unlock is one item and one option** — yellow *laces*, not yellow
  everywhere — so a reward never leaks into a slot it was not meant for.
- **A picker lists only what the player may wear.** A reward option appears in
  the player screen once its puck is earned, never before; the Trophy Case is
  where a player sees what is still to earn.
- **Counting pucks reward play that wins hockey games.** Mitts is PvP; a player
  chasing a puck spends their teammates' and opponents' game, not only their
  own (Darktide is co-op against AI, where it mostly costs the player's own
  run). So no puck pays for losing, for padding a stat in a blowout, or for
  playing badly on purpose. Goals, assists, interceptions, blocks, wins and
  hits are all safe to count.
- **Games against bots count for everything**, every tier and every combo,
  exactly as Steam career stats and achievements already count them
  (`GameManager._achievements_active`: any real match, never free play, the
  tutorial or drills). A player who wants to grind a reward out offline may.
- **Hits count as credited.** `HitTracker` already credits a hit only where the
  NHL would: on the puck carrier when the contact costs them the puck, or on a
  player finished just after they released it. So a hit puck counts the existing
  `hits` stat. Hit hunting within that definition is a real way to play.
- **Everything is a Game Puck.** A puck is one of three things: a single play
  or a single game (a snipe, a hat trick), a career milestone (a ladder of
  tiers: 10 / 50 / 250 / 1000 goals), or a **combo** of other pucks — all of
  them, and a combo may name other combos (*nesting is allowed*). There is no
  separate banner concept and no separate section for combos: a combo is a
  puck that lists the pucks it needs.
- **Any puck or tier can unlock something.** A reward names the puck that
  unlocks it — a single puck (`hat_trick`), a ladder tier (`goals@250`) or a
  combo — so pricing a reward is choosing its puck, and a hard reward is a hard
  puck rather than a long list.
- **Title combos are named for how a player plays.** Power Forward is the
  model: 50 goals and 50 hits, unlocking the Power Forward title. They are
  hockey archetypes, so the title a player wears says something true about
  their game.
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
  every time, and combos off the pucks they need, so neither is stored. What is stored —
  the earned game, feat, event and roster pucks, and the equipped title — is a
  section of the preferences file Steam Cloud already syncs (`PlayerPrefs`), so
  no new Cloud file or Steamworks Cloud setting is involved. That file
  reconciles newest-write-wins; the ledger section merges as a union instead,
  since an earned puck is never un-earned.
- **Steam achievements are opt-in per puck.** A puck is mirrored to Steam only
  when its registry row is flagged for it. The existing 20 are flagged; nothing
  new is until it is worth the Steamworks setup (below). Puck and title
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

Pucks, tiers, combos, titles and cosmetic rewards need no Steamworks work.


## The model

### Game Pucks

One registry row per puck. Kinds:

| kind | earned when | evaluated |
|---|---|---|
| **count** | a lifetime counter reaches a tier | game-over, from `SteamStatRecorder.totals()` |
| **game** | one game's stat reaches a bar (3 goals in a game) | game-over (`GamePuckRules.earned_game`) |
| **feat** | a specific play happens (below) | the moment it happens, host-detected |
| **event** | a moment (a big hit, finishing the tutorial course, winning a tournament) | its hook (`TrophyService.on_*`) |
| **roster** | a match whose lobby includes a named person | game-over (`GamePuckRules.earned_roster`) |
| **combo** | every puck, tier or combo it names is earned | whenever one of them is (`GamePuckRules.requirement_met`) |

A count puck is a ladder: one row with tiers (10 / 50 / 250 / 1000 goals), each
tier its own puck to earn. Tiers ascend strictly, and anything that needs a
tier names it by its target (`goals@50`).

A combo names the pucks, tiers or other combos it needs, all of them. It is
derived from what it names every time, never stored, so changing a combo's
list re-decides it for everyone. Its progress is how many of what it names are
earned. The chain must never come back to the combo itself: a test walks every
combo and fails on a cycle.

### Rewards

A reward row names its unlock and the puck requirement that unlocks it (`id` or
`id@tier`). Cosmetics are `CosmeticUnlocks.REWARDS` rows (a slot, an option, a
puck); a title is a `Titles.ALL` row naming its puck. A puck may unlock several
things, and the Trophy Case shows each puck's unlocks on its card.

### Titles

A title is an id plus a locale key (`Titles`, `TITLE_<ID>`). A player wears at
most one, picked from the titles their earned pucks have unlocked
(`GamePuckRules.earned_titles`) on the player screen's Title row, saved as a
pref, and it travels with their look: the join and spawn handshakes, the lobby
roster, the existing-player sync and the replay header. In v1 every title comes
from a combo. It shows under the name on the lobby slot card, after the name on
the scoreboard (`SCOREBOARD_NAME_TITLE`) and beside the name in the Three Stars
on the game-over screen.

### Catalogue

The rows live in `GamePucks.ALL`. The title combos:

| combo | needs | title |
|---|---|---|
| Power Forward | `goals@50` + `hits@50` | Power Forward |
| Shutdown | `interceptions@50` + `takeaways@50` + `shots_blocked@50` | Shutdown |
| Two-Way | `goals@50` + `assists@50` + `interceptions@50` + `takeaways@50` | Two-Way |
| Iron Man | `games_played@100` | Iron Man |

| Playmaker | `assists@250` + `one_timer_feed` | Playmaker |
| Sniper | `goals@250` + `snipe` | Sniper |

| Enforcer | `hits@100` + `fight_wins@10` | Enforcer |

Playmaker and Sniper arrived with the feats in Phase 3, Enforcer with the
fight pucks. Phase 5's cosmetic pricing is
below, under *Phases*.

Ladders: goals, assists, points, hits, interceptions, takeaways, blocks, faceoff
wins, wins and games, four or five tiers each. Every counter is a `SteamStats`
row (`STAT_INTERCEPTIONS` was added for this); points are goals + assists. A
ladder has at most as many tiers as `TrophyCopy.TIER_KEYS` has numerals.

Feats are where Mitts can stand out, since the mechanics are deep enough to
name specific plays. All are read off a credited goal (`FeatRules`, from the
host's `GoalFeatContext`):

| feat | the play | earned by |
|---|---|---|
| `snipe` | a HIGH-loft shot released beyond the end-zone faceoff dots (6.1 m off the goal line) | the scorer |
| `backhand_shelf` | a backhand at MID or HIGH loft | the scorer |
| `one_timer_feed` | the primary assist on a one-timer goal | the passer |
| `pick_and_finish` | a goal on the possession your own interception started | the scorer |
| `strip_and_finish` | the same, after your own takeaway (poke, lift, check or pin) | the scorer |
| `one_timer_dot` (*The Office*) | a one-timer released inside either faceoff circle in the zone scored on (4.572 m round the dot) | the scorer |

The shot's loft level and hand are recorded on the host at release
(`ShotOnGoalTracker.note_release_style`); a tipped goal earns no shot-style feat,
since the shot was not the scorer's. A won possession (`FeatTracker`) lasts
until the other team establishes one or play stops. A Transition title waits on
a carried-zone-entry counter, which nothing records yet.

### Fight pucks

Fighting (`docs/fighting-plan.md`) counts per game on the host: `fights`, every
fight a player was in, and `fight_wins`, those he won. A fight is won by the
man left standing when the other goes down (`FightRules.result_of`); a fight
that ends with both down, a disengage or the linesmen is a draw. Both stats
ride the broadcast `PlayerStats`, so the player's own machine reads them at
game-over like any game puck. Bots fight, so these are earned against bots
too.

| puck | kind | earned by |
|---|---|---|
| Dropped the Gloves (`dropped_gloves`) | game | a fight |
| Won the Fight (`won_fight`) | game | a fight won |
| Gordie Howe Hat Trick (`gordie_howe`) | game | a goal, an assist and a fight in one game |
| Heavyweight (`fight_wins`) | ladder | 5 / 10 / 25 / 50 fights won (`STAT_FIGHT_WINS`) |
| Enforcer | combo | `hits@100` + `fight_wins@10`: the Enforcer title |

The ladder counts wins, not fights: outside `NHL` 5v5 a fight costs nothing,
so a ladder on fights would pay for starting them. A game puck's condition is a
`mins` map of game stats, so one puck can ask for several at once.

### Penalty pucks

Penalties (`docs/penalties-plan.md`) count a goal by the strength it went in
at, on the host, and the counts ride the broadcast `PlayerStats` like the
fight stats. All three are `NHL`-only: the first two need a minor, so 5v5,
and the third a penalty shot, so 3v3.

| puck | kind | earned by |
|---|---|---|
| Man Advantage (`power_play_goal`) | game | a power-play goal |
| Shorty (`shorty`) | game | a short-handed goal |
| Ice in the Veins (`penalty_shot_goal`) | game | a penalty-shot goal |

Penalty minutes, power-play goals and power-play points are Steam stats
(`STAT_PIM`, `STAT_PP_GOALS`, `STAT_PP_POINTS`) with no ladder on them yet. A
ladder on penalty minutes would pay for fouling.

## Architecture

Lower layers never reach up (CLAUDE.md → *Layer Architecture*).

**Domain** — pure, unit-tested:
- `domain/config/game_pucks.gd`: the puck registry. It replaced the old
  achievement registry and keeps its condition kinds, adding `count` ladders
  and `feat` pucks.
- `domain/config/titles.gd`: title ids, the puck requirement each is unlocked
  by, and their locale keys.
- `domain/state/trophy_ledger.gd`: the stored part only — the earned game,
  feat, event and roster pucks, and the equipped title — with its serialization
  and the union merge.
- `domain/rules/game_puck_rules.gd`: given the Steam counters, one game's stats
  and the ledger, which pucks, tiers and banners are earned, and each one's
  progress. Earning is idempotent: evaluating twice earns nothing new.
  It resolves combos recursively, so a combo may name other combos.

**Application:**
- `TrophyService` replaced the old achievement service: it evaluates at game-over
  and on events, writes the ledger into `PlayerPrefs`, unlocks the pucks flagged
  for Steam through `SteamManager`, and emits a signal for the earn toast.
- The feat channel. A feat is detected on the host, where the authoritative
  events are, and only the earning player records it. One RPC,
  `notify_feat(feat_id)`, carries every feat (CLAUDE.md → *New RPC*:
  `NetworkManager` → signal → `GameManager._wire_network_signals()`). Adding a
  feat is then a registry row and a host detector, never a wire change.
  `PhaseCoordinator.goal_credited` fires before the shot tracker's pending state
  clears; `GameManager` builds the context, and earns each feat itself for the
  local player, sends it to a remote one and drops it for a bot. A peer earns
  only an id that is a feat puck.

**Infrastructure and UI:**
- The Trophy Case screen (`TrophyCaseScreen`), beside Career on the side menu:
  one list of pucks in catalogue order, each card showing what earns it (its
  description, its tiers, or a combo's prerequisite pucks, each ticked when
  earned) and what it unlocks (`TrophyCopy.unlock_lines`).
  `TrophyCopy` holds the words it and the toast share.
- An earn toast on the HUD's toast stack, at game-over and live for moments.
- A title row in the player screen's YOU region (`PlayerTitleRow`).
- The title on the lobby slot card, the scoreboard and the Three Stars on the
  game-over screen.
- Locked cosmetics (Phase 4): `CosmeticUnlocks` holds what is free in each slot
  and the reward rows, each a slot, an option and the puck requirement that
  unlocks it.
  The picker shows only what the player may wear; a pick that is not available
  is worn as the team colour (`CosmeticUnlocks.worn_*`). The lobby relays what a
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
4. **Cosmetic rewards**, in three steps, each its own commit:
   1. **Free colours and the unlock machinery.** The second team colour joins
      the palette; `CosmeticUnlocks` and the coercion to the team colour; the
      player screen's swatches show only what is available. Protocol bump.
   2. **Signature tape jobs** (built), as new entries in the existing
      tape-coverage list: *Spaced* (four 1 cm wraps spread from mid-blade to
      the toe), the Sniper banner's reward, and *Bottom strip* (one tape width
      laid along the blade's bottom edge, heel to toe, ending at a 4 cm toe cap
      in its own colour — the toe-colour pick shows only for it), the
      Playmaker banner's. Homages to two players' real tape jobs, never naming
      them. The player screen lists a job once it is earned; an unearned one is
      worn heel-to-mid.
   3. **Sticks as patterns** (built). A stick is a pattern
      (`StickModelRegistry`) — Solid, Kick, Block, Split, Wood — whose zones
      (shaft, up to two bands, wordmark, blade) the player paints from the
      palette under the same rules; Wood's shaft and blade stay varnished ash.
      The pattern stays in the gear code's `stick_model` field, so a saved
      stick keeps its index; the old colourways became patterns whose defaults
      put the team colour where the accent was. The zone colours ride the tape
      code behind a paint flag, so an unpainted stick, a bot and an older code
      draw the pattern's defaults, and picking a new pattern drops the paint.
      The old white colourway is an unlisted alias, rewritten on load as Solid
      painted white. Protocol bump.
5. **One kind of puck**, in two steps:
   1. **Flatten** (built). The banners became `combo` rows in `GamePucks.ALL`
      (nesting allowed, cycles failed by a test); titles and cosmetic rewards
      name a puck requirement instead of a banner; the Trophy Case becomes one
      list whose cards show prerequisites and unlocks; the earn toast fires for
      a combo like any puck. No wire change: titles and cosmetics travel as
      before, and nothing is on `main` yet, so no saved progress moves.
   2. **Price the cosmetics** (built) on single pucks, tiers and combos:

      | reward | unlocked by |
      |---|---|
      | *Spaced* tape | `hat_trick` — a player's first hat trick |
      | *Bottom strip* tape | *Breadman*, a combo: `assists@50` + `three_helpers` (3 assists in a game) |
      | Yellow laces | *The Office* (`one_timer_dot`), a feat: a one-timer goal released inside any offensive-zone faceoff circle |

      The host's goal context carries the release point (`release_xz`, the
      goal scored on at +z) beside the release distance the snipe reads.
      Titles stay on their combos.

   **Names.** A combo that unlocks a title carries the title's name
   (Playmaker, Sniper). Where an existing puck already had that name, the
   existing puck is renamed and so is its Steam achievement — only the
   Playtest app's achievements are live, and losing or changing them there is
   accepted. A Steam achievement's display name is its puck's in-game name, a
   ladder tier's included ("Goal Scorer II", not "Sniper"); the 3-assist game
   puck is *Three Helpers* (`three_helpers`, `ACH_THREE_HELPERS`).

   Later rewards (helmet stickers, a spray-painted stick, signature laces) are
   new content on the same machinery.

## Tests

- **Registry integrity:** every combo requirement and every reward names a real
  puck and an existing tier; no combo reaches itself through its chain; tiers ascend; every count puck's counter is backed by a
  `SteamStats` row (extending the consistency test in
  `tests/unit/game/test_steam_stat_recorder.gd`); every title and puck has its
  locale rows.
- **Rules properties:** a puck earned stays earned; a higher counter never earns
  fewer tiers; a combo is earned exactly when its last requirement is, through
  any depth of nesting.
- **Ledger round-trip:** serialize, reload, compare; an unknown id in a saved
  ledger is kept (a newer build's puck survives a round trip through an older
  one), and a malformed entry is skipped rather than failing the load.
- **Ledger merge:** merging two ledgers keeps every puck either holds, whichever
  copy is newer, so a Steam Cloud adopt never loses one.
- **Steam mirror:** every puck flagged for Steam is listed in
  `steam/ACHIEVEMENTS.md`, held by a test, not a comment.

## Not in scope

- The automatic play-style label (career and recent form) discussed alongside
  this. It can coexist — the label says how you play now, a title says what you
  have done — and is its own plan.
- Drill medals and personal bests, which would become event pucks once drills
  record them.
