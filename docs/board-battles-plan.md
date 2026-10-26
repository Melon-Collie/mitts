# Board battles — the dig, and folding the pin into the press

Status: **draft, awaiting review.** Amends the physicality paragraph of
`docs/gameplay-design.md` (the pin sentences), retires the pin of
`docs/physicality-plan.md` Phase A and `docs/defensive-play-plan.md`'s *Pin
revision*, and is the board half of what `docs/net-front-battles-plan.md` is
for the crease. Each phase is its own PR and playtest.

## Decisions banked

- **A board battle is a dig contest.** A slow puck on the boards with sticks of
  both teams on it is not picked up on touch: every blade in reach digs at it at
  once, and possession goes to the side that out-digs the other. It is a contest
  over time, not a race decided in one tick.
- **The pin is folded into the press.** There is no pin verb, no onset, no stick
  button hold. A man pressed into the boards is **sealed**: he digs at a fraction
  of his leverage, which is what a pin is for. Escaping is sliding along the
  wall out of the press, as any press ends.
- **Battles usually resolve.** The leverage terms are asymmetric by
  construction, the puck creeps toward the side winning it, and the frozen-puck
  whistle is kept only for a contest that genuinely stalls.
- **No new input.** Your blade on the puck digs. Ctrl seals (and takes your own
  stick off the ice, as it already does). F lifts or ties the other man's stick,
  which takes his blade out of the dig. Shift gets you low.
- **The bots learn each verb in the phase that adds it** (the rule from
  `docs/defensive-play-plan.md`).
- **Decided with the user:** a dig contest rather than emergent puck physics;
  fold the pin into the press; battles should usually resolve.

## Why — what the boards do today

A probe that plays a full bot-vs-bot match headless and logs every contact
(scratch, not committed; becomes the Phase 1 instrument, below):

| match | play | carrier time on the boards | contacts with any carrier | pins |
|---|---|---|---|---|
| Normal 5v5 | 176 s | 10 s of 113 s | not measured | 0 |
| Hard 5v5 | 172 s | 5 s of 100 s | 3 (1 committed) | 0 |
| Hard 3v3 | 152 s | 1 s of 63 s | 0 | 0 |

"On the boards" is the pin's own margin: body edge within 0.25 m.

- **Possession on the wall is decided in one tick.** A loose puck attaches to the
  first blade whose swept path reaches it (`PuckController._check_interactions`,
  `PuckInteractionRules.check_pickup`); two blades on the same tick squirt it
  (`apply_contested_pickup`). That is a race, so the boards play like open ice
  with a wall beside it.
- **The pin is a narrow combo that rarely lines up.** It needs a held stick
  button past the hook (0.2 s), touching within 5 cm, the victim's edge within
  25 cm of the boards, an approach within 45° of square, a drive into the wall,
  and an unbraced victim, all on one tick. F under Ctrl is dead and the commit
  cancels the stick phase, so "check then pin" has to be played as release Ctrl,
  fresh F press, hold. A bot carrier on Normal or Hard braces inside the 0.2 s
  it takes to reach the hold.
- **The bots never get there.** Their pin is reached for only from a committed
  check on a man on the boards, and in the probe they touched a carrier about
  once a minute.
- **There is no dump-in** (`Scripts/domain/ai/CLAUDE.md`, *There is no dump-in
  and no defensive-zone clear*), because a puck given away could only be priced
  as a loss. A board battle with a measurable win rate is the missing half of
  that price. Dump-and-chase and the cycle are a follow-up plan (Phase 4).

## The model

### When a battle is on

The puck is a **wall puck** when it is on the ice, within `BATTLE_WALL_MARGIN_M`
of the boards (`wall_normal` at a zero radius, the frozen-puck rule's test) and
slower than `BATTLE_MAX_SPEED_M_S`. Fast pucks along the boards are rims and
stay the reception doctrine's.

A **battle** starts on a wall puck when either:

- blades of **both teams** are in dig reach of it (`DIG_REACH_M` of the blade
  contact point, the pickup radius), or
- a blade in reach belongs to a **sealed** skater (below). The seal makes a
  battle by itself: a man pressed into the boards with the puck at his feet does
  not just pick it up while the presser has his stick off the ice. That window
  is the pin's whole purpose: the presser's support has it to arrive.

A lone uncontested blade on a wall puck picks it up as today. Clean retrievals
keep their pace; only contested ones slow down.

Phase 1 covers loose pucks. A carrier on the boards is Phase 2.

### Who digs

Every skater whose blade is in reach and on the ice: not committed (Ctrl),
not tied, not mid-lift or forced up (`blade_up`, `is_stick_busy`), not rocked
(a rocked skater's stick is jarred off the ice already), not down or ghosted,
not in a planted shot state. These are the pickup gates of
`_check_interactions` unchanged, so a stick out of the play for a pickup is out
of the dig.

Each digger's **leverage** is a product of what he can physically do with the
stick from where he stands:

```
leverage = reach_term × inside_term × seal_term × stance_term
```

| term | value | grounded in |
|---|---|---|
| `reach_term` | 1 with the blade at his feet, falling linearly to `REACH_FLOOR` at full stick reach | a stick choked in tight works the puck; one at the rim taps it |
| `inside_term` | `OUTSIDE_SHARE` when an opponent's body disc lies on the line from his body to the puck, else 1 | reaching around a man; the man with his body between the puck and the other man has inside position |
| `seal_term` | `SEALED_SHARE` when sealed, else 1 | pressed into the glass, the stick has no room |
| `stance_term` | `STANCE_DIG` in the stance, else 1 | low and wide wins the puck; it costs the stride, as the stance always does |

### The meter

One signed meter per battle, `m ∈ [−1, 1]`, positive toward team 0. Each tick

```
dm/dt = (Σ leverage_team0 − Σ leverage_team1) / DIG_S
```

so one free digger alone at full leverage wins from even in `DIG_S`, a sealed
man alone takes `DIG_S / SEALED_SHARE`, and two diggers beat one. At `|m| = 1`
the leading team's highest-leverage digger is granted the puck at rest
(`_grant_catch` with zero relative velocity), and the battle ends.

**The puck creeps.** While a battle holds, the host places the puck at its
anchor plus `|m| × CREEP_M` toward the leading team's best digger's blade, at
rest. It is the read of who is winning (no HUD needed), it replicates as the
puck's position already does, and it is self-resolving: the winner pulls it to
his feet, the loser's reach lengthens and his `reach_term` falls.

### How a battle ends

- **Won:** `|m|` reaches 1 (above).
- **Abandoned:** no blade of either team in reach. The puck is loose where it
  sits, and the next blade to touch it starts over (a battle again if contested).
- **One side left:** only one team still in reach. It digs on from the current
  meter, so a side already ahead finishes quickly.
- **Knocked out:** anything that gives the puck speed (a check through it, a
  deflect) or takes it off the wall ends the battle.
- **Stalled:** the meter makes less than `STALL_PROGRESS` of progress over
  `FrozenPuckRules.FROZEN_S`. NHL whistles it and faces off at the nearest dot
  (unchanged); ARCADE squirts it along the boards away from the nearest body
  (unchanged). With the asymmetric terms above and the creep, this should be
  rare. The Phase 1 instrument measures how rare.
- **A stoppage** clears every battle.

### The seal

A skater is **sealed** when he is in a press (`PressRules`, the partner the
press already finds), the press normal points into the boards he is against
(body edge within `SEAL_WALL_MARGIN_M`), and the presser's drive into the wall
beats his own drive out:

```
m_presser × drive_presser > m_sealed × drive_sealed     (along the normal into the wall)
```

The wall stops the motion, so hold does not enter: who is sealed is decided by
who is pushing harder into the glass. An uncommitted presser (drive at the
passive share) seals a man who does nothing; a man who drives back off the wall
with Ctrl beats an uncommitted presser and is not sealed; committed against
committed, weight decides. All of it reads replicated state the press already
reads, so every machine derives the seal the same way and nothing goes on the
wire.

Escaping is the press's own geometry: slide along the boards until the bodies
part. There is no slide cap, no escape offset and no 3 s limit.

### What the existing verbs become on the boards

| verb | in a battle |
|---|---|
| blade on the puck | digs |
| Ctrl into a man on the boards | seals him; your own stick is off the ice, so you trade your dig for his |
| body check into the boards | strips the puck at his feet, as today (`backstop_hit_strength`); a rocked man's stick is out of the dig |
| F lift | his blade is forced up for 0.4–0.9 s: out of the dig |
| F tie | a tied blade receives nothing: out of the dig |
| Shift | `STANCE_DIG` |
| a teammate on the same puck | two diggers' leverage adds; or one digs and one seals |

## Networking

- **The battle is host-only state** (`BoardBattleTracker`, beside where
  `BoardPinTracker` ticks today), and the host is the only writer of the puck
  while a battle holds, the same rail as a carrier's pinned puck.
- **The dig reads host-side blades.** A client's blade on the host is its own
  input stream's, late by the one-way trip but self-consistent, and the puck is
  at rest: what a client sees its blade touch is what the host's does. The
  contest's time scale (`DIG_S` and up) is well above the network lag budget,
  so ping does not decide a battle.
- **Claims:** `PickupClaimResolver` rejects a claim on a puck in a battle (the
  host's contest decides it). A client never provisionally picks up a wall puck
  (`try_provisional_pickup` already declines contested grabs; the wall gate
  makes it unconditional on the boards). Poke, lift, tie and hit claims are
  unchanged.
- **The seal is derived, not sent**: it reads the press partner and the boards,
  both from replicated state.
- **No wire change in Phase 1.** The meter is read from where the puck sits; the
  bots read the tracker through the host-built `WorldSnapshot` (a host-only
  field, like `real_puck_carrier_peer_id`). Replays carry it in the puck's
  recorded position.
- **No native twin**: the dig is not in a movement kernel.

## Bots (Phase 1)

- **Joining a battle is a race against its resolution, not to the puck.**
  `AILoosePuckChase`'s race-lost decline does not apply to a wall puck in a
  battle: the question is whether we get a stick on it before the meter resolves
  (`AIBoardBattleRead.time_to_resolve` from the meter and the diggers'
  leverage, the same formula the host runs).
- **The first man digs, the second seals.** A teammate who yields the puck
  (`teammate_first_to_puck`) does not stand off: if an opponent is digging,
  he presses that man into the boards (`SkaterAgentPress`, a new case beside the
  screen press and the dig-in), priced on how much the seal moves the meter
  (`time_to_resolve` with and without). It rides `check_aggression` (zero on
  Easy), as the press does.
- **A bot alone with a sealed opponent** has its stick off the ice; it holds the
  seal while its support wins the race to the puck (the pin's coached rule,
  `_pin_worth_holding`, moves here), else lets go and digs.
- **Lift and tie:** the stick-play collaborator already lifts a carrier's stick
  and ties a covered man; in a battle, taking the leading opponent digger's
  blade out of the dig is a lift target when it is in reach.
- **Every tier digs** (it is just a blade on the puck); sealing is pace, as
  above.

## Phases

### Phase 1 — the loose-puck battle

- `Scripts/domain/rules/board_battle_rules.gd`: wall puck, leverage terms, meter
  step, creep target, seal, stall. Pure and GUT-tested.
- `Scripts/game/board_battle_tracker.gd`: host-only start/hold/end, the puck
  placement, the grant. Ticked where the pin tracker is.
- `PuckController._check_interactions`: a wall puck with a battle on it is the
  tracker's, not the pickup pass's.
- `FrozenPuckRules`: `trapped` is a stalled battle, not a pinned body.
- Bots as above; `AIBoardBattleRead` in `Scripts/domain/ai/`.
- The pin stays in the build untouched until Phase 3, so a playtest can compare.
- **Instrument:** `tests/instruments/game/test_board_battles.gd`, the probe made
  real: a full bot-vs-bot match headless, reporting battles a minute, how they
  start (rim, strip, retrieval), time to resolve, who wins, seals, and stalls.
  It needs the real `GameManager`, so it lives with the instruments, outside
  the default suite.

### Phase 2 — the carrier on the boards

- A carrier is **protecting** when his puck is on the boards and he is slower
  than `PROTECT_MAX_SPEED_M_S`. An opponent's blade on a protecting carrier's
  puck digs instead of poking: the meter starts at the carrier's side, his own
  blade is a digger, and when it crosses zero the puck comes loose at his feet
  (no launch) and the loose battle carries on from there.
- A carrier skating along the boards faster than that is poked as today. Slowing
  down on the wall is what buys protection, as it does in real hockey.
- Bot carriers on the boards protect when pressed and the carry search finds no
  better move (priced on `time_to_resolve`); defenders who meet one dig, seal or
  lift as in Phase 1.

### Phase 3 — retire the pin

Delete the pin as a verb once Phase 1 and 2 have been played. The inventory is
below (*Retiring the pin*). It is a wire change (`pin_role`, `pin_strength`)
and a protocol bump.

### Phase 4 — dump-and-chase and the cycle (its own plan)

Out of scope here, and the reason for the rest. With battles measurable, a dump
is priced as the odds we win the battle where it stops × our possession value of
that spot, and the cycle is a carrier on the boards leaving it, or chipping it
along the wall, for the man coming down. Both need the carrier's compete to
gain a new candidate, so they get their own plan once Phase 1's instrument has
real win rates to price with.

## Retiring the pin

_Inventory pending._

## Tests

- `test_board_battle_rules.gd` (properties): leverage is monotone in each term;
  the meter is antisymmetric in the teams; one free digger wins from even in
  `DIG_S`; two beat one; a sealed man alone takes `DIG_S / SEALED_SHARE`; the
  creep is toward the leader and zero at even; a fast or off-wall puck is no
  battle.
- `test_board_battle_tracker.gd`: a contested wall puck starts a battle and an
  uncontested one is picked up as today; a sealed digger starts one alone; each
  end condition; a stoppage clears; a stall whistles under NHL and squirts under
  ARCADE.
- Seal on the live rig (`tests/harness/press_harness.gd`): pressed into the
  boards by an uncommitted man he is sealed; driving back out with Ctrl he is
  not; committed against committed, the heavier side wins; sliding along the
  wall ends it.
- Claim gates: a pickup claim on a battling puck is rejected; a client's
  provisional pickup never fires on a wall puck.
- Bots: the yielding teammate seals the opponent digger; a bot joins a battle it
  would lose as a race; Easy never seals.

## Open questions

1. **Passive dig, or a raking input?** As drafted, a blade in reach digs at its
   leverage. The alternative multiplies leverage by how fast the blade is pulled
   back toward the digger's feet, so working the stick wins it. Recommended:
   passive for Phase 1 (bots need nothing new, and the skill is position, seal,
   stance and stick lifts); add the rake if battles read as standing around.
2. **Should a won battle always be a pickup?** Real battles are often won by
   chipping or kicking the puck to support without possessing it. Recommended:
   pickup in Phase 1, and the winner passes or rims as any carrier does; revisit
   with the cycle in Phase 4.
3. **Battles away from the boards?** The same contest could run for a slow puck
   in a net-front scramble. Recommended: boards only until it has been played;
   the crease is `docs/net-play-plan.md`'s.
4. **Is the creep enough feedback?** Alternatives: a dig pose (the stick
   working), stick-on-stick and skate sounds, or a small team-colored mark under
   the puck. Recommended: the creep plus sounds first, and judge in the
   playtest.
5. **Does weight count in the dig?** It already counts in the seal, through the
   press. Recommended: not in the dig until played.

## Starting values

| constant | value | why |
|---|---|---|
| `BATTLE_WALL_MARGIN_M` | 0.6 | `FrozenPuckRules.BOARD_MARGIN_M`: a puck in the feet of a body on the boards |
| `BATTLE_MAX_SPEED_M_S` | 1.0 | `FrozenPuckRules.SPEED_MAX_M_S`: a puck sitting in the feet, not moving along the wall |
| `DIG_REACH_M` | 0.5 | `PuckController.PICKUP_RADIUS` |
| `DIG_S` | 0.4 | one free stick out-digs nobody in a beat; long enough to read and answer over the network |
| `REACH_FLOOR` | 0.5 | a stick at the rim still works the puck, at half |
| `OUTSIDE_SHARE` | 0.5 | reaching around a man |
| `SEALED_SHARE` | 0.25 | sealed and alone, he wins it in 1.6 s: the support's window |
| `STANCE_DIG` | 1.25 | low and wide, against the stride it costs |
| `CREEP_M` | 0.3 | about a blade's length, from even to won |
| `SEAL_WALL_MARGIN_M` | 0.25 | `BoardPinRules.PIN_WALL_MARGIN_M` |
| `STALL_PROGRESS` | 0.1 | a meter that has moved less than a tenth in 2 s is stuck |
| `PROTECT_MAX_SPEED_M_S` | 2.0 | Phase 2; walking it along the wall, not skating |

## Where it lives

| piece | file |
|---|---|
| battle math | `Scripts/domain/rules/board_battle_rules.gd` |
| host contest | `Scripts/game/board_battle_tracker.gd` |
| pickup hand-off | `PuckController._check_interactions` |
| claim gate | `Scripts/game/pickup_claim_resolver.gd`, `PuckController.try_provisional_pickup` |
| frozen puck | `Scripts/domain/rules/frozen_puck_rules.gd`, `GameManager._check_frozen_puck` |
| bot read | `Scripts/domain/ai/board_battle_read.gd` |
| bot seal | `Scripts/ai/skater_agent_press.gd` |
| instrument | `tests/instruments/game/test_board_battles.gd` |

## Docs that change when each phase lands

- `docs/gameplay-design.md`: the physicality paragraph's pin sentences become
  the battle and the seal (1, 3).
- `Scripts/domain/ai/CLAUDE.md`: *On the boards, the checker's extra is the
  pin* becomes the battle; *There is no dump-in* stays until Phase 4 (1, 3).
- `Scripts/domain/ai/DECISIONS.md`: a row for the battle read (1).
- `Scripts/ai/CLAUDE.md`: the collaborator table (1, 3).
- `docs/physicality-plan.md`, `docs/defensive-play-plan.md`: the pin retired
  (3).
- The tutorial's line "Held into a man on the boards, {stick_check} pins him
  there" (`tutorial_manager.gd`) (3).
