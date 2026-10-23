# Hit outcomes — balance, the rocked hit, and both bodies

Status: **Phases 0–3 built**, playtest pending. Amends the physicality paragraphs of
`docs/gameplay-design.md` and the body-check verbs of
`docs/physicality-plan.md`. Four phases plus a small controls pass, each its
own PR and playtest. The cross-check this plan names was retired at v87
(`docs/net-front-battles-plan.md`); its rows here record what was decided then.

## Decisions banked

- **Hits should land hard without flooring someone every time.** A committed
  check at game pace usually **rocks** its man: he's stripped, his stick and
  edges are gone for a beat, and he stays on his skates. Knocking him down is
  the reward for catching him off balance, not for closing speed alone.
- **The knockdown is the victim's balance, not a league line.** It compares the
  part of the hit that tips him over against what his base and posture can
  absorb. How he stands, which way the hit comes from and what he's doing
  decide it, as well as how hard it lands.
- **Both bodies take an outcome.** The impulse is shared, and each body is
  judged on its own share against its own balance. Who is faster along the
  line no longer decides who can be hit, so standing a carrier up works.
- **Phases 2 and 3 ship together or in that order.** On its own, Phase 3 lets a
  defender standing still with Ctrl held flatten every carrier who skates into
  him; the balance model is what keeps that to a rocked hit.
- **The bots learn each change in the phase that makes it** (the rule from
  `docs/defensive-play-plan.md`).

## Why

### The knockdown is one line, and game pace is past it

`BodyCheckRules.Config.knockdown_impulse` (1.8 m/s of victim Δv) is the whole
decision. A committed check kicks its victim `closing × 0.65 × m_a/(m_a+m_b)`,
so in closing speed:

| matchup | stagger only | knockdown |
|---|---|---|
| equal builds | 1.8–5.5 m/s | ≥ 5.5 m/s |
| heavy into light | 1.5–4.5 m/s | ≥ 4.5 m/s |
| light into heavy | 2.4–7.3 m/s | ≥ 7.3 m/s |
| victim braced (Ctrl) | 4.6–13.8 m/s | ≥ 13.8 m/s |

Base top speed is 10 m/s (`GameRules.DEFAULT_SKATER_MAX_SPEED_M_S`). The
in-between outcome only shows up when someone barely skates into his man; a
committed check thrown at game pace lands past the line almost every time.

### The line ignores the man it lands on

Beyond his mass, nothing about the victim enters the decision:

- **Stance.** The loaded stance (Shift: a wide base, twice the edge grip) does
  nothing against a check, although `CrossCheckRules` already reads it against
  the cross-check.
- **Direction.** Square from the front, from the side and from behind all land
  the same. `CrossCheckRules` already splits a push along and across the
  blades; the check does not.
- **What he's doing.** A slapper wind-up, a follow-through, a one-handed reach
  or a tight turn costs nothing.
- **Bracing** (Ctrl, ×0.4 on the delivered impulse) is the only defense, and for
  a man without the puck it also means taking the commit posture.

### The middle outcome barely shows

A full stagger is a 13° recoil (`stagger_recoil_deg`), a 9° wobble and up to
a second of thrust and grip penalty. Beside a fall and a staged get-up it reads
as nothing happening, so hits feel binary even when the stagger fires.

### The faster body cannot be hit

`Skater._resolve_player_collisions` resolves each pair once, from the body
moving toward the other more (`(v_self + v_other)·n > 0`), and only its partner
takes the outcome: the stagger and knockdown through `body_check_received`, and
the strip through `body_checked_player`, which names that partner as the
victim. A carrier delivers only the passive bump (`hit_passive_transfer_mult`),
and a committed defender on the far side of the contact counts only as braced.

`tests/unit/actors/test_contact_aggressor_side.gd` measures it at 8 m/s
closing, equal builds, the defender committed:

| who is faster | carrier's outcome | carrier's Δv | defender's Δv |
|---|---|---|---|
| defender (carrier at 1 m/s) | knocked down, stripped | 2.60 m/s | — |
| carrier, defender set (stand-up) | nothing, keeps the puck, skates on at 7.7 m/s | 0.31 m/s | 0.31 m/s |
| carrier, defender stepping up at 3 m/s | nothing | 0.31 m/s | 0.31 m/s |

The stand-up at the blue line, the defensive hit the transition-defense plan
asks the bots to make (`EVEN_OR_UP` → *stand up at the line*), cannot take the
puck. A check lands only from the side, or when the checker is the faster body
along the line of contact.

A second copy of the delivery rule disagrees with the first:
`Puck.on_body_check` gives the checker full transfer whenever `hit_committed`
is set, while the resolver excludes a carrier (`state_has_puck`). A braced
carrier bulldozing a man without the puck denies him a pickup as if he'd thrown
a check.

## Phase 0 — controls pass

Small, independent, its own PR.

- **Labels.** The Options row "Hit" becomes "Hit / Brace", since Ctrl also
  braces and chords the cross-check. "Hit" and "Deflect" move to
  `locale/translations.csv` keys like the stick-lift row
  (`test_ui_uses_the_locale_seam.gd` ratchets the file down). The section
  header loses "(Experimental)": the design doc treats the pad as first-class.
- **Hit takes RB and the deflect takes L3** (decided with the user): Ctrl's
  whole family — the commit, the brace, the cross-check chord with X — sits on
  a shoulder held under the index finger instead of a stick click held while
  steering. `PlayerPrefs.PAD_DEFAULT_BUTTONS` plus pad scheme 3
  (`PadSchemeMigration.to_scheme_3`), which moves a saved config still on the
  scheme-2 defaults and leaves a rebound one alone. The tutorial prose names
  binds through `{hit}` / `{stick_lift}`, so it follows on its own.

## Phase 1 — the rocked hit (built)

A new rung between the stagger and the knockdown: what a hard hit at game pace
usually does.

### Rules

- **Onset:** a hit whose stagger strength reaches `ref_impulse` (1.35 m/s, the
  full check, which is already the puck-strip threshold). For equal builds
  that is about 4.2 m/s closing.
- **It is the top of the stagger timer** (`BodyCheckRules.is_rocked`,
  `rocked_share`). A rocked hit sets `stagger_timer` above
  `max_stagger_seconds`, by `rocked_min_seconds` at onset up to
  `rocked_max_seconds` at `rocked_ref_impulse`. He is rocked while the timer is
  above that floor; the ordinary full-stagger tail eases out below it. One
  replicated float still encodes everything, so the wire layout is unchanged
  (`stagger_timer` is a u8 at 0.01 s, room to 2.55 s).
- **A knockdown takes no rocked band.** He is going down, and a rocked band
  running under the fall carried the stagger's recoil onto a body lying on the
  ice. The knockdown poses render pixel-identical to before. Until Phase 2
  moves the knockdown line, that caps the rocked band at what a 1.8 m/s hit
  gives (about 0.61 s); `rocked_ref_impulse` comes into reach with Phase 2.
- **While rocked:**
  - the puck is stripped (as today at this strength) and pickup is denied
    (`hit_pickup_cooldown`, as today);
  - the stick is off the ice: `Skater.stick_jarred`, which the controller sets
    each tick from the timer, makes `is_forced_lift_active()` true, so every
    gate an opponent's stick lift closes (pickup, deflect, lift, tie, the
    raised blade) closes for him too;
  - the stance and the commit drop and can't be re-entered, so he can't brace
    either;
  - the edges go further (`rocked_grip_penalty`), continuously into the
    stagger's own grip penalty as he comes out of it, so he glides along the
    hit rather than cutting out of it.
- **It reads.** The torso reels the way the hit drove it, up to
  `rocked_recoil_deg` at the top of the band and eased down onto the stagger's
  recoil as he comes out. The skates splay and he sits into them as he catches
  himself for as long as he is rocked (`GaitStaggerLayer`'s floor stage, on a
  spring at `rocked_catch_rate`, a step out in about 0.15 s). The stick rises as a
  lifted one does. Not built: the free hand touching the ice, and the stick
  hand flying off the shaft line.
- **The cross-check never rocks.** It "staggers him on the check's ladder but
  never knocks him down and strips nothing", and that stays true:
  `take_cross_check` caps what it adds at the full stagger, and a shove on a
  man already rocked leaves his window alone.

### Networking

No new wire field. Every rocked effect is a function of `stagger_timer`, which
is already snapped to the host at replay start and decayed deterministically.
Protocol v83: the field's legal range grows. The native movement kernel
(`NativeSkaterMovement.integrate_forward`, which remote prediction and the
host's rewind run) carries the rocked grip too, through `set_stagger_params`'
two new arguments, and the parity fuzz now covers the rocked band.

The reconcile replay's contact read the raw `input.hit_held` where the live
resolver reads the controller's `hit_committed`; it now reads the same value
the live tick produced, which a rocked player holding Ctrl needs and which
also closes the old cases (knocked down, pinned, mid-slapper).

### Bots

No change to the bar: `AIBodyCheck.COMMIT_IMPULSE_M_S` (1.6) was "a full
stagger and strip with margin", and a full check is now the rocked onset, so
it already reads "rocks him". `test_body_check.gd` now holds it between the
rocked onset and the knockdown line. A rocked carrier needs no special read:
the strip has already put the puck loose.

### Tests

- `test_body_check_rules.gd`: the bands, their ceiling against the wire,
  continuity of the grip at the floor, and no rocked band on a knockdown.
- `test_rocked_hit.gd`: through the real controller, a full check jars the
  stick and refuses the stance and commit, both come back at the full stagger,
  a hit short of a full check never rocks, a cross-check never rocks, and the
  rules' defaults are the controller's tuning.
- `test_native_movement_parity.gd`: the fuzz's stagger range covers the band.
- `render-poses.sh --only=rocked`: `rocked_onset` and `rocked_mid`.

## Phase 2 — the knockdown is balance (built)

### The model

A body knocked off its skates is one tipped over its base. Treat it as an
inverted pendulum about the edge of its base: the hit tips it if the Δv that
the feet can't follow exceeds what lifting the centre of mass over that edge
costs, `½Δv² = g(√(h² + b²) − h) ≈ g·b²/2h`, so **`Δv_tip ≈ b·√(g/h)`**: the
budget grows with the half-base `b` in the hit's direction and shrinks with
the centre-of-mass height `h`. A static pendulum tips far more easily than a
skater, who steps and rides a hit, so the absolute level is a feel tunable
(`balance_ref_dv`). The model contributes the *shape*: which way each term
moves the budget, and by how much relative to the others.

New pure rule class `BodyBalanceRules` (`Scripts/domain/rules/`), two numbers:

- **The tipping share of the hit.** Split the body's Δv along and across its
  skates' heading (his facing, which is where the blades point, forward or
  backward). Along the blades the skates roll with the body, so
  most of it is carried off as travel; across them the edges bite and the top
  keeps going.
  `tip_dv = √((along_share · Δv_along)² + Δv_across²)`.
- **His balance budget.** `balance_ref_dv × posture × sight × √(h_ref / h)`:
  - **posture:** stance by its base-width ratio, derived rather than picked:
    each skate `stance_width_m` out from under a hip `GaitPose.HIP_HALF_WIDTH`
    off centre, (0.13 + 0.125) / 0.13 = 1.96. A vulnerable body
    ×`vulnerable_mult`: the shot states that commit the body
    (`SkaterStateMachine.state_off_balance`: wrister load, slapper wind-up,
    follow-through, one-timer hold). Not modelled: a one-handed reach and a
    tight turn or pivot, which no replicated field states cleanly. Ctrl is
    already in the impulse (the brace) and, from Phase 3, in the checker's own
    share, so it takes no posture term;
  - **sight:** how square he is to the hitter, from 1 facing him down to
    `sight_behind` with his back to him — a man who sees it coming rides it;
  - **height:** the build's height over the reference build's, which the
    centre of mass scales with (`SkaterController._build_height_mult`, and
    `AISkaterCaps.height_mult` for the bots).

**Knockdown when `tip_dv > budget`.** He is down for the fall to the ice
(`KnockdownFallRules.first_impact_time`, from the hit's own shove), a lie that
grows with how far past it landed (`BodyCheckRules.lie_seconds_from_overshoot`:
0.15 s just past it to 0.7 s at `knockdown_ref_overshoot` 1.7), and the 0.8 s
get-up, so the get-up never starts before he is on the ice: about 1.5 s for a
hit just past his balance, 1.9 s for the hardest. (Built first as the old
`min/max_knockdown_seconds` ramp over the overshoot, 1.1–1.9 s; a 1.1 s window
started the get-up a quarter-second before he landed.) `knockdown_impulse` and its reference are
gone. A cross-check is never a full check, so it never reaches it. The board rule stands: the knockdown reads how far his
body was driven, so a check into the wall rocks and strips him at the
backstopped strength but leaves him up and pinnable.

Every input is replicated state the client already has: velocity, the hips'
yaw, `stance_active`, `hit_committed`, `current_shot_state`, the reach and the
build. So the local victim predicts the same verdict the host reaches
(`Scripts/networking/CLAUDE.md`: contact is reconstructed identically by all
three parties).

### What it does, at the starting values

Closing speed (m/s) for a committed check to knock its man down; rocked and
stripped from 4.2 for equal builds everywhere (heavy into light 3.4, light
into heavy 5.5). The full grid is the snapshot
`tests/unit/rules/snapshots/body_balance.txt`:

| victim | square front | 45° | side | from behind, square |
|---|---|---|---|---|
| upright, equal builds | 14.8 | 8.8 | 5.9 | 8.9 |
| upright, heavy into light | 11.9 | 7.1 | 4.8 | 7.2 |
| upright, light into heavy | 19.3 | 11.5 | 7.7 | 11.6 |
| in the stance, equal | 29.0 | 17.2 | 11.6 | 17.4 |
| vulnerable, equal | 8.9 | 5.3 | 3.5 | 5.3 |

Read against 10 m/s top speed: a square, upright man rides any one-sided
check and goes down only to a head-on collision where both are skating hard;
a side hit floors him from about the pace it does today; the stance holds
against all but a maximal hit; a man caught shooting or reaching can be taken
off his feet at modest pace, below the rocked line when hit from the side.

### Bots

- **Built:** `skater_agent_board_play.gd`'s pin reach asks the host's own
  question, `BodyBalanceRules.overshoot` on the man's replicated facing,
  stance and shot state and his build's height, instead of the knockdown line.
- **Built:** the commit bar already prices a rocked hit; `test_body_check.gd`
  holds it under what floors a square, upright man.
- **Not built** (a new decision each, #842): the checker
  angling for the side or the vulnerable beat when a knockdown is in reach,
  and an open-ice carrier squaring up or bracing against a check he can't
  avoid.

### Tests

- `test_body_balance_rules.gd`, properties: the budget never falls as the
  stance comes in or the sight squares up, never rises with height or a
  vulnerable posture; the tip share never rises as the hit swings from across
  the blades to along them; the along/across split is an identity at 0° and
  90°.
- The grid above as a snapshot (`tests/snapshot.gd`), so a tuning change shows
  as a reviewed table diff.
- `test_rocked_hit.gd`: square on he rides what floors him from the side; in
  the stance he rides the side hit; a cross-check never knocks down; the
  balance defaults are the controller's.
- The fixtures that hit a man square from the front at 3 m/s to put him down
  (`test_knockdown_lies_on_the_ice.gd`, `test_arms_reach_their_hands.gd`, the
  `knockdown_lying_back` pose) hit him at 6, since he now rides 3 on his feet;
  the board-backstop and get-up tests pass unchanged.
- The smoothness gate (`test_body_stays_smooth.gd`) holds a knockdown just
  past his balance beside the side knockdown, from t136, once the softest
  fall has landed. Its get-up pop was two things: the get-up starting before
  he reached the ice (the window above), and the drawn bottom hand turning a
  corner where the arm's reach ran out mid-stand, sharper or softer with the
  stride's phase — a hit a few hundredths of a m/s harder moved it from 12 to
  28 mm/tick². The drawn grip now eases into that limit
  (`BottomHandIK.soft_reachable_grip`; the gameplay reach keeps the hard
  one). What is left: when the fall's second bounce lands on the get-up's
  first frame, head and stick reach ~13–14 mm/tick² (bounds 13 and 11), over
  a narrow band of hits.

## Phase 3 — both bodies take an outcome (built)

### Rules

- **Delivery is one function**, `SkaterCollisionRules.contact_transfer`,
  symmetric in the two bodies and read by the resolver
  (`Skater.contact_transfer_with`), the reconcile replay (whose records now
  carry each other skater's possession) and the strip (`Puck.on_body_check`,
  whose own copy disagreed with the resolver's about a braced carrier):
  - **Full transfer** when either body is a committed checker: holding Ctrl
    without the puck. Two committed checkers meeting both deliver.
  - **The passive bump** when neither is.
  - **The brace** (×`body_check_brace_resistance`) for a carrier holding Ctrl,
    which a puckless man holding it never is: he is the checker.
- **Both bodies are judged.** The shared impulse kicks each by `J/m`, and each
  takes his own outcome (stagger, rocked, knockdown) from his own Δv against
  his own budget. The aggressor gate stays, because it decides which machine
  resolves the pair deterministically, but it no longer decides who can be hit.
- **The checker rides his own hit.** A committed checker leans into the
  contact, so the part of his Δv that drives him back the way he faces counts
  at `checker_front_share` for every outcome (stagger, rocked, knockdown).
  Landing a check slows him without rocking him; a much heavier man or
  another committed checker still rocks him. At the starting values, with
  each body's own outcome:

  | contact | checker's Δv, as he reads it | other body's Δv |
  |---|---|---|
  | full-speed check on a stationary equal man | 3.25 → 1.30, stagger | 3.25 |
  | stand-up, carrier at 8 m/s, equal | 2.60 → 1.04, stagger | 2.60, rocked |
  | stand-up, carrier at 10 m/s, equal | 3.25 → 1.30, stagger | 3.25, rocked |
  | light checker into heavy, full speed | 4.02 → 1.61, rocked | 2.48 |
  | two checkers head-on, 16 m/s closing | 5.20 → 2.08 each, both rocked, neither down | — |

  The first row sits 0.05 m/s under the rocked line, so it goes in the
  snapshot rather than being asserted as a property.
- **The strip and the credit are the committed checker's.** When the body
  whose resolver ran is the carrier and the other is a committed checker,
  `body_checked_player` fires from the checker's side naming the carrier, so
  the strip, the hit credit and the client's hit claim all see the defender
  check the carrier, whoever was faster.

The stand-up then plays out like this: a set defender holding Ctrl meets a
carrier skating in at 8 m/s, and both are kicked 2.6 m/s. The carrier,
upright and square, is rocked and stripped; the defender, leaning into it,
reads 1.04 and is only staggered.

### Networking

Read `Scripts/networking/CLAUDE.md` first. What changes:

- `body_check_received` fires on both bodies of a pair, each on the machine
  with authority over it (the host for all; a client for its own predicted
  skater, in either role). The design doc's "victim-only, so a delivered
  hit's bounce never self-staggers the attacker" is retired deliberately: the
  checker's outcome is now real, and `checker_front_share` is what keeps a
  normal check from rocking him.
- The local skater predicts its own outcome as the checker too, so a check
  that rocks its thrower (into a heavier man) shows at once and reconciles
  through the snapped `stagger_timer` / `knockdown_timer`, like the victim
  side today.
- Contact geometry is untouched, so the three reconstructions stay
  identical; only which outcomes are read from them changes. The client's
  hit claim (`HitClaimResolver`) rebuilds the closing speed from the rewound
  velocities along the hitter's line, which never asked who was faster, so
  it validates a stand-up unchanged.
- Protocol v84, for Phases 2 and 3 together.

### Bots

Built: **any defender meets a carrier about to skate into him with the
shoulder** (`AIStandUpRead.meets`, applied by the new `SkaterAgentStandUp`
ahead of the board play): Ctrl held inside `MEET_S` (0.15 s) of contact when,
committed, the contact rocks him. It is not the body-check commit — the
contact is happening anyway, so no containment is given up and the gap
roles keep their doctrine — so the `EVEN_OR_UP` stand-up at the line lands
as a check. Rides `check_aggression` (zero on Easy). At the wall the board
play may still turn it into a pin.

Not built (#842, with the Phase 2 bot items): a carrier reading a set
defender holding Ctrl in his lane as a hit coming and cutting, passing or
bracing.

### Tests

- `test_contact_aggressor_side.gd` inverts: the stand-up rocks and strips the
  carrier and leaves the defender set; stepping up slower than the carrier
  lands the same hit as stepping up faster at the same closing speed.
- `test_skater_collision_rules.gd`: `contact_transfer` is the same from
  either side for every commit and possession pair, a committed checker
  delivers whoever is faster, a braced carrier never delivers.
- `test_body_balance_rules.gd`: the checker leans into what drives him back
  only, and the checker's table above as the snapshot `checker_share.txt`.
- `test_rocked_hit.gd`: through the controller, a committed checker rides
  his own full-speed check, and the same hit rocks him uncommitted.
- `test_stand_up_read.gd`: the bot meets a carrier a beat from contact, not
  while he can still turn, not for a hit that wouldn't rock him.

## Phase 4 — feel pass

After the playtests of 1–3: tune `balance_ref_dv`, the posture and sight
factors and the rocked window against the feel targets below, and update the
snapshot with the commit saying the new numbers are intended.

### Feel targets

1. A square, upright carrier taking a full-speed committed check from an equal
   build: rocked and stripped, stays up.
2. The same hit from the side: down.
3. Caught in a slapper wind-up or a one-handed reach: down from the side at
   modest pace, from the front at speed.
4. In the stance, or braced: down only to a maximal hit.
5. Weight counts both ways: heavy into light floors him at a shallower angle;
   light into heavy rocks at most.
6. Standing up a carrier at the blue line rocks and strips him.
7. Into the boards: rocked and stripped at lower pace, never floored, pinnable.
8. An uncommitted bump stays a jostle.

## Docs that change when each phase lands

- `docs/gameplay-design.md`: the physicality and stagger paragraphs (1, 2, 3)
  and the boards paragraph's knockdown sentence (2).
- `Scripts/domain/ai/DECISIONS.md`: the body-check and pin-reach rows (1, 2,
  3); `Scripts/ai/CLAUDE.md`'s defensive verbs (3).
- Tutorial body-check step and its `locale/translations.csv` rows, if they
  describe a knockdown (1).
- The comments on `SkaterController.knockdown_impulse` and the stagger ladder,
  `AIBodyCheck.COMMIT_IMPULSE_M_S`, `HitRules`' landmarks (each phase that
  moves them).

## Where it lives

| What | Where |
|---|---|
| Stagger, rocked and knockdown timers | `Scripts/domain/rules/body_check_rules.gd` |
| Balance budget and tip share | new `Scripts/domain/rules/body_balance_rules.gd` |
| Delivery (transfer from commit, possession, brace) | one function beside `SkaterCollisionRules.victim_kick` |
| Both-body outcomes | `Skater._resolve_player_collisions`, `LocalController`'s replay contact |
| Rocked effects (stick, stance, commit, grip) | `SkaterController`, keyed off `stagger_timer` |
| Rocked pose | `Scripts/controllers/gait/gait_stagger_layer.gd` |
| Bot hit pricing | `Scripts/domain/ai/body_check.gd`, `skater_agent_board_play.gd` |

## Decided with the user

1. **Hits from behind** stay as the table has them: a square hit from behind
   floors an upright man from 8.9 m/s closing, against 14.8 from the front.
   There is no penalty system; closing from behind is usually low, since the
   checker has to run his man down. Revisit if the playtest shows hunting from
   behind.
2. **The pad's Hit button moves to RB**, the deflect to L3 (Phase 0). The
   deflect is held while waiting on a puck, so it inherits the stick click's
   cost; the playtest says whether it can live there.
3. **The stick is off the ice for the whole rocked band.** If the playtest
   wants the strip without the whole beat of no stick, it becomes
   `rocked_stick_seconds`, the first part of the band.

## Starting values

| Constant | Value | Why |
|---|---|---|
| `ref_impulse` (rocked onset) | 1.35 m/s | unchanged: the full check and the strip threshold |
| `rocked_ref_impulse` | 2.6 m/s | a full-speed committed check at equal builds |
| `rocked_min_seconds` / `rocked_max_seconds` | 0.5 / 0.8 s | a beat out of the play, well short of a knockdown's 1.5–1.9 s |
| `rocked_grip_penalty` | 0.75 | off his edges (grip 0.25 at the top of the band): glides along the hit |
| `rocked_recoil_deg` | 30° | reads beside the stagger's 13° |
| `rocked_splay_m` / `rocked_crouch` | 0.16 m / 1.0 | the catch: wider than the stance's base, a lighter sit than its 1.7 |
| `balance_ref_dv` | 2.4 m/s | square, upright, equal builds survive any one-sided check below top speed |
| `along_share` | 0.5 | a hit along the blades is half carried off as travel |
| `sight_behind` | 0.6 | budget with his back to the hitter, linear in (1 + cos) / 2 |
| stance posture | base-width ratio | derived from `stance_width_m`; the grid assumes 1.8 until the skating base is measured |
| `checker_front_share` | 0.4 | a full-speed check on a stationary equal man staggers its thrower, never rocks him |
| `vulnerable_mult` | 0.6 | shooting, reaching one-handed, turning tight |
