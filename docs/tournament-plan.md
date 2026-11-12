# Tournament — design plan

Status: **proposed; nothing built.** The four decisions in the first table are
agreed. The five under *Open questions* carry a recommendation each and need a
yes or a change before Phase 1 starts.

A tournament is an eight-club single-elimination bracket. The player picks a
club, is drawn a seed, and wins three games to take the cup: quarterfinal,
semifinal, final. Every opponent is a team of bots. The player's own side is the
host plus whoever joins the lobby, with bots in the seats nobody takes. The
bracket is saved on the host's machine after every game and picked up again from
the Play menu.

**Club** in this document means one of the twelve fruit teams in
`data/team_colors.json` (a `TeamColorRegistry` slot). **Side** means team 0 or
team 1 on the ice. A club plays on a different side from one game to the next;
the two are kept apart in the names below for that reason.

## Decisions already made (from chat, 2026-11-12)

| Question | Answer |
|---|---|
| Format | **Eight clubs, single elimination.** The player's club plus seven drawn from the other eleven. Three wins takes the cup. |
| Opponents | **Bots only.** No human ever sits on the opposing side. |
| Opponent strength | **Seeding is cosmetic.** One Bot Difficulty and one Goalie setting apply to every bot on the ice, as they do in any lobby match. A seed decides who meets whom and who is at home; it does not make a club play better. No per-side skill plumbing. |
| Persistence | **Saved on the host.** The bracket outlives the session. Human teammates may differ from round to round; whoever is in the lobby plays the next game. |

## 1. The bracket (domain)

Two new pure files, no engine APIs.

**`Scripts/domain/state/tournament_state.gd`** (`TournamentState`, RefCounted)
holds only what cannot be derived:

| Field | Meaning |
|---|---|
| `version` | Save format. A save with another version is discarded, not migrated. |
| `rng_seed` | Drew the field and the seeds; also seeds every simulated game. |
| `clubs_by_seed` | Eight club slots, index 0 = first seed. |
| `player_club` | The club slot the player picked. |
| `team_size`, `num_periods`, `period_duration`, `rule_set`, `fighting` | Match settings, latched when the tournament is created. |
| `results` | Seven entries in bracket order, each a home score, an away score and an overtime flag, or empty for a game not yet played. |

Who advanced, which round is current, the player's next opponent and whether
the tournament is over are all read off `results` by `TournamentRules`, never
stored. `to_dict` / `from_dict` are the save format and the wire format.

**`Scripts/domain/rules/tournament_rules.gd`** (`TournamentRules`, static):

- `draw(rng_seed, player_club, all_clubs)` picks the seven other clubs and
  shuffles the eight into seeds.
- `matchup(state, game_index)` returns the two clubs of a game, or nothing when
  a feeder game is unplayed. Quarterfinals pair 1v8 and 4v5 in the top half,
  3v6 and 2v7 in the bottom, so the first and second seeds can meet only in the
  final.
- `home_club(state, game_index)` is the better seed of the two. Home takes
  side 0, the home kit and the home bench.
- `player_game(state)` is the index of the game the player plays next, or -1
  once eliminated or champion.
- `record(state, game_index, home_score, away_score, overtime)` writes one
  result. A tied score is rejected: an elimination game has a winner.
- `simulate_round(state, round)` fills in every unplayed game of that round
  that has both clubs. Each game's RNG is seeded from `rng_seed` and its game
  index, so a result does not depend on the order games are resolved in.
- `round_name_key(round)` returns `TOURNAMENT_ROUND_QF` / `_SF` / `_FINAL`;
  the UI calls `tr()` on it.

Tests: `tests/unit/rules/test_tournament_rules.gd` (the draw always contains
the player's club and eight distinct clubs; the pairing table; a result
advances the right club into the right slot; simulation is deterministic per
seed and never ties; a full bracket of seven results names one champion) and
`tests/unit/state/test_tournament_state.gd` (the dict round trip, and a
wrong-version dict is refused).

## 2. A tournament game is an ordinary match

Nothing about the match itself changes. The tournament decides its inputs and
reads its final score.

- **Inputs.** The lobby's Start builds the same config dictionary it builds
  today. In a tournament the two color slots are the home and away clubs of the
  player's game, the match settings come from `TournamentState`, and
  `ot_enabled` is forced on. `GameStateMachine` already plays further overtime
  periods until someone scores, so a game cannot end level.
- **Result.** On the host, at `GAME_OVER`, the score is recorded, the rest of
  that round is simulated, and the state is saved and sent to clients. If the
  player's club lost, every later round is simulated too, so the bracket shows a
  champion.
- **A game that does not reach `GAME_OVER` was not played.** Leaving, a crash,
  or the pause menu's instant Return to Lobby all leave the bracket where it
  was, and the game is played again. (Open question 3.)
- **Stats and Game Pucks count as they do in any match against bots.** No new
  gate; `_achievements_active()` already covers it.

## 3. Session and persistence (application)

**`Scripts/game/tournament_coordinator.gd`** (`TournamentCoordinator`,
RefCounted, owned by `GameManager`) holds the live `TournamentState`, or null
outside a tournament. `GameManager` is past the god-class limits, so it gets
three call sites and no logic: read the config at Start, hand over the score in
`_on_game_over`, drop the state when the session ends.

The save is a `[tournament]` section of the preferences file, written the way
the trophy ledger is. That file already mirrors to Steam Cloud, so a bracket
follows the player between machines with no new Cloud file. There is one save:
starting a new tournament replaces the one in progress, behind a confirm.

A finished tournament stays in the save as finished, which is what lets the
Play menu say how the last one ended, until a new one replaces it.

## 4. Networking

The host owns the bracket. Clients hold a mirror so their lobby and game-over
screens can draw it.

- One new reliable host-to-client RPC, `sync_tournament(data: Dictionary)`,
  sent to a peer when they join and to everyone when a result lands. An empty
  dictionary means the session is not a tournament. It surfaces as a
  `tournament_synced` signal wired in `GameManager._wire_network_signals()`.
- Adding an RPC shifts the method table, so `BuildInfo.PROTOCOL_VERSION` goes
  104 → 105, with an entry in `docs/protocol-history.md`.
- No match-time wire changes: nothing in the world state, inputs or claims
  knows a tournament exists.

Seating is where a tournament differs from a lobby match, and it has three
paths that all need the same rule (*a human sits on the player's side or
spectates, never on the opponent's*):

1. The lobby's slot picker and `_find_balanced_slot`.
2. A mid-match joiner, which today goes through auto-balance in
   `GameManager.on_player_connected`.
3. A reconnect reservation, which already restores the original seat and needs
   no change, but gets a test.

A human who joins a full side spectates. A human who takes a seat a bot held
replaces the bot, as the lobby does now.

## 5. Screens

All new strings are `KEY,en,es` rows in `locale/translations.csv`. Every popup
closes on `ui_cancel`.

- **Play popup.** A **Tournament** button beside Start Game. With a tournament
  in progress it reads as a continue ("Continue: Semifinal vs Plum") with a
  smaller New Tournament beside it.
- **Setup popup** (`TournamentSetupPopup`, new). Pick a club from the twelve
  crests; set Mode, Periods, Period Length, Rules and Fighting. Overtime is not
  offered. Confirming draws the bracket, saves it and opens the lobby.
- **Bracket panel** (`BracketPanel`, new). One control that draws the eight
  clubs, their seeds, the scores so far and the path still to play, with the
  player's club marked. Used by the lobby, the game-over screen and the Play
  popup's continue row. Club colors on the dark panel go through
  `TeamColorRegistry.get_score_ink_pair`, never a raw primary.
- **Lobby in tournament mode.** A `LobbyTournamentMode` collaborator, so the
  rules below are one object and not conditions spread through `LobbyManager`:
  - The header names the round and the matchup; a Bracket button opens the
    bracket panel.
  - The opponent's side is all bots and cannot be edited. Open seats on the
    player's side are filled with bots at Start, so both rosters are always
    full.
  - Color pickers and color votes are hidden; the bracket chose the kits.
  - Match settings are shown read-only.
  - The visibility selector works as it does today. Flipping it to Friends or
    Public is how teammates get in.
  - When the tournament is over the lobby shows the finished bracket and one
    **Finish** button for the host. Finish ends tournament mode and leaves
    everyone in a normal lobby.
- **Game over.** Rematch is hidden. Return to Lobby reads **Continue**, and the
  top block gains one line: the round the club advances to, *Eliminated*, or
  *Champions*.
- **Matchup intro.** The existing overlay gains the round name above the two
  rosters.

`tools/ui_preview_runner.gd` gets shots for the setup popup, the tournament
lobby, the bracket mid-run and the bracket finished.

## 6. Phases

Each phase ends with the suite green and something to test locally.

1. **The bracket.** `TournamentState`, `TournamentRules`, their tests. Nothing
   visible in the game.
2. **Playable alone.** The coordinator, the save, the Play popup entry, the
   setup popup, the bracket panel, the lobby's tournament mode, result
   recording and the game-over changes. The visibility selector is held at
   Offline in tournament mode for this phase, so a whole cup can be played with
   bot teammates before any networking changes.
3. **With friends.** The sync RPC and protocol bump, the client's mirror, the
   three seating paths, and a tournament tag on the Steam lobby so the browser
   can say what a joiner is walking into.
4. **Dressing.** The matchup intro's round line, a champion moment after the
   final, Spanish strings checked in context, the preview shots, and a Game
   Puck for winning a cup (`GamePucks.ALL`, per `docs/game-pucks-plan.md`).

Phases 2 and 3 change gameplay flow and networking, so each stops for a local
playtest before the next begins.

## Open questions

Each has a recommendation; the plan above is written as if it were accepted.

1. **How is the player's seed chosen?** Recommended: a random draw, so one cup
   is a favorite's run and the next an eighth seed's. The alternative is letting
   the player pick the seed, which turns it into a difficulty-flavored choice
   that changes no difficulty.
2. **Do seeds weigh on simulated games?** Recommended: lightly. The better seed
   wins a simulated game somewhat more often than not, so the bracket behaves
   like one on paper, with upsets. This touches only games nobody plays. The
   alternative is a coin flip.
3. **Is an abandoned game a loss?** Recommended: no, it is unplayed. That lets
   a player quit a game they are losing and try it again. Counting it as a loss
   closes that, at the price of a crash or a dropped host ending a cup. Worth
   revisiting once the mode has been played.
4. **Is the better seed at home?** Recommended: yes. The cost is that the
   player's side is sometimes side 1, in the away kit and on the away bench.
   The alternative pins the player's club to side 0 in the home kit every game.
5. **Are Bot Difficulty and Goalie latched for the whole tournament?**
   Recommended: yes, picked in the setup popup and stored with the other
   settings, so a cup is won at one difficulty. The alternative leaves them as
   the host's lobby preferences, editable between rounds.

## Not in the first version

- **Human opponents.** Two human sides in one bracket need the bracket to span
  sessions, which is a different feature.
- **A season** (a schedule, standings, then playoffs). `TournamentState` is the
  playoff half of one; a season would add a schedule and a table in front of it.
- **Clubs that play differently.** Decided against for now (seeding is
  cosmetic). The route, if it is wanted later, is a skill profile per side in
  place of the single `GameManager.bot_skill_profile` and
  `goalie_skill_profile`, and a shot model (`AIGoalieModel`) that knows which
  goalie it is shooting at.
- **Fixed rosters per club.** Opposing bots are drawn from
  `data/bot_identities.json` as lobby bots are today, so a club's players can
  change between rounds. Thirty identities cannot give eight clubs five skaters
  each without repeats.
- **A tournament column in `career_stats`.** Each game still posts its usual
  row; nothing marks it as a cup game.
