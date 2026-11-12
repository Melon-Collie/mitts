# Steam achievements

Mitts' achievements are the Steam mirror of its **Game Pucks**
(`docs/game-pucks-plan.md`). The catalogue is `Scripts/domain/config/game_pucks.gd`;
a puck row's `steam` (or a ladder's `steam_tiers`) is the Steamworks **API Name**
it mirrors. `GamePuckRules` decides what's earned (pure, unit-tested) and
`TrophyService` (owned by `GameManager`) asks `SteamManager` to unlock it. A puck
with no Steam id stays in-game and needs nothing here.

This file is the bridge to the part the code **can't** do: the achievement
definitions live in the Steamworks partner site, one per API Name below.
`test_game_puck_catalogue.gd` fails when a mirrored id is missing from this
table — and if an id has no matching, *published* achievement in Steamworks, its
unlock silently no-ops.

> **Two apps.** Achievements are configured per-app. The closed beta runs under
> the **Playtest** child app **4893650** as well as the main app **4892600**
> (see README → "Playtest app"). To see unlocks during the live playtest, define
> the achievements on **4893650** too — same API Names, same icons.

---

## One-time setup (Steamworks website — can't be scripted)

For each app (4892600 and, for the playtest, 4893650):

1. **Stats & Achievements → Achievements**: create one achievement per `id`
   below. Set its display **name** and **description** (these come from
   Steamworks, *not* from the registry). The name is the puck's in-game name,
   a ladder tier's numeral included, so the two never disagree.
2. Upload a **locked** and **unlocked** icon for each (Steamworks requires both;
   64×64 PNG). Placeholder art is fine for the beta.
3. Leave **"Hidden"** off unless the row below says hidden.
4. **Publish** the changes (Stats & Achievements changes need an explicit
   publish, like Store/build changes).

The **game / special / event / roster** achievements unlock directly from code.
The **ladder** ones read Steam User Stats, which you must also define — see
STATS.md for that checklist.

---

## The achievements

`when` = how it's evaluated (see the catalogue header for the `cond` kinds):
- **game** — a single game's stat reached the bar (any mode, incl. vs bots).
- **special** — a compound game-over condition.
- **event** — fired live the moment it happens (a big hit mid-match), or from a
  meta-progression moment outside a match (finishing the tutorial course,
  editing your build) — those bypass the game-over sweep and its mode gate.
- **roster** — earned by playing an online game whose lobby includes a specific
  person, and never by that person themselves.
- **ladder** — a tier of a career ladder, a lifetime total backed by **Steam
  User Stats** (every real match, bots included; NOT gated on stat-sharing, and
  no Supabase dependency). The mirrored stats must be defined too — see STATS.md.

| API Name (`id`)     | Name              | When    | Unlocks when…                                  |
|---------------------|-------------------|---------|------------------------------------------------|
| `ACH_HAT_TRICK`     | Hat Trick         | game    | 3 goals in a single game                       |
| `ACH_THREE_HELPERS` | Three Helpers     | game    | 3 assists in a single game                     |
| `ACH_BIG_NIGHT`     | Big Night         | game    | 5 points (G+A) in a single game                |
| `ACH_BRICK_WALL`    | Brick Wall        | game    | 3 blocked shots in a single game               |
| `ACH_FIRST_GOAL`    | Lamp Lighter      | game    | score your first goal (any mode)               |
| `ACH_ONE_TIMER`     | One-Timer         | game    | score off a one-timer                          |
| `ACH_TIP_IN`        | Redirect          | game    | tip a teammate's shot into the net             |
| `ACH_OVERTIME_HERO` | Overtime Hero     | game    | score the overtime winner                      |
| `ACH_FACEOFF_BOSS`  | Master of the Dot | game    | win 5 faceoffs in a single game                |
| `ACH_PICKPOCKET`    | Pickpocket        | game    | 5 takeaways in a single game                   |
| `ACH_SHUTOUT`       | Shutout           | special | win a game conceding 0 goals                   |
| `ACH_FIRST_WIN`     | W                 | special | win your first game (any mode)                 |
| `ACH_FREIGHT_TRAIN` | Freight Train     | event   | land a body check above the big-hit threshold  |
| `ACH_STUDENT`       | Student of the Game| event  | complete every tutorial                        |
| `ACH_CUSTOM_BUILD`  | Make It Yours     | event   | edit your player's build                       |
| `ACH_PLAY_WITH_BUUKIE` | Buukie's Buddy | roster  | play an online game with Buukie (hidden)       |
| `ACH_GOALS_50`      | Goal Scorer II    | ladder  | 50 career goals                                |
| `ACH_SETUP_ARTIST`  | Setup Man II      | ladder  | 50 career assists                              |
| `ACH_ENFORCER`      | Hitter III        | ladder  | 100 career hits                                |
| `ACH_VETERAN`       | Veteran II        | ladder  | 25 career games                                |

---

## Adding / changing an achievement

A new puck is a row in `GamePucks.ALL` plus its `PUCK_<ID>` and `PUCK_<ID>_DESC`
rows in `locale/translations.csv` — no Steamworks work. A new compound condition
also needs a branch in `GamePuckRules._special_met()`. To mirror a puck to Steam
as well:

1. Give its row a `steam` API Name (or a ladder tier a `steam_tiers` entry).
2. Create the achievement in Steamworks under that name (both apps) and publish.
3. Add the row to the table above; the catalogue test holds the two together.
4. Run the rule tests: `bash .claude/hooks/run-gut.sh -gdir=res://tests/unit/rules`.

Changing a threshold is a one-line edit to a row's `min` — no Steamworks change
needed (the bar is enforced in code).

## Testing on a dev machine

Unlocks only fire when Steam is running and the achievement is **published** for
the app you launched under. In a debug build, `SteamManager.reset_all_achievements()`
clears every registered achievement (and stats) so you can re-earn them — it's a
no-op in release.
