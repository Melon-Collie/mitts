# Fighting — design plan

Status: **approved; phases 1–4 built** (lifecycle, gloves off, the fist and
the grab, punches landing) plus the fight camera; phase 4 awaits a local
playtest. Phase 5 is not started. Where what is built
differs from the text below, the "as built" sections say how.

Two skaters can fight. Both must agree to it, the referee blows the play
dead, and the fight is played with the same hands the stick is: the cursor
places a fist exactly as it places the blade, and a button holds the other
man's sweater. There is no penalty; the fight ends, play restarts with a
faceoff, and both stay on.

## Decisions already made (from chat, 2026-11-11)

| Question | Answer |
|---|---|
| Consent | **Challenge + accept.** One player presses Fight squared up to an opponent nearby; the opponent has a short window to press it back. An unanswered challenge just lapses, with nothing lost. |
| When, and the whistle | **In live play**, the dropped puck included: the whistle goes the instant both have agreed, and a faceoff follows every fight. Not in a faceoff's set-up (a press there does nothing, and is not held for the drop; revised 2026-11-11), and not in the goal celebration (see *Phase 1 as built*). |
| Afterwards | **No penalty.** Both stay on. |
| Controls | **The cursor drives the fist, and a button grabs.** The fist uses the stick's IK, reach and speed limits; punch power is the fist's speed at contact. Holding a button grabs with the other hand and keeps the grip. A key swaps the hands. |
| Bots | A **grudge** per bot per opponent, filled by his body checks: past one level the bot accepts, past a higher one it challenges (2026-11-11, below). Before that, bots accepted every challenge and never challenged. |
| Setting | **A lobby toggle, "Fighting: On / Off".** Fights are **never** possible in free play or in the `OFF` ruleset, even if free play ever goes multiplayer. |
| Stat | **Deferred.** No "Fights" column yet. |

## 1. Lifecycle (host-authoritative)

A new host-only `FightTracker` (`Scripts/game/`), shaped like
`BoardPinTracker`: it owns which skaters are paired, and it is the only
writer of the replicated `Skater.fight_role`.

```
NONE ──Fight press, opponent in range──▶ CHALLENGING ──opponent presses back──▶ FIGHTING ──end──▶ NONE
                                           │ lapses after CHALLENGE_WINDOW_S
                                           ▼
                                          NONE (re-challenge cooldown)
```

- **Challenge onset** (`FightRules.can_challenge`, pure): a skater who is
  not carrying the puck, not down, not ghosted, not in a pin, and has an
  opponent within `CHALLENGE_RANGE_M` (~2.5 m) and inside a facing cone. The
  opponent picked is the nearest one in the cone. The challenger is
  `CHALLENGING` for `CHALLENGE_WINDOW_S` (~2 s). The challenge is
  **visible**: he squares up to the man, his stick comes up across his body,
  and the man gets a world-HUD prompt. A lapsed challenge goes on a cooldown,
  so the key can't be spammed as an alarm.
- **Accept**: the challenged skater presses Fight inside the window while
  still in range. Both become `FIGHTING`. Goalies can't fight.
- **The whistle**: from `PLAYING` the host blows it dead at once
  (`FIGHT_CALLED` signal and RPC, `FACEOFF_WHISTLE` sound, a toast). It
  stores where the puck was, for the faceoff dot
  (`GameRules.nearest_faceoff_dot`), and enters a **new phase
  `GamePhase.Phase.FIGHT`**, appended as ordinal 7 so `.mreplay` files stay
  valid.
- **The `FIGHT` phase**: the puck is dead and stays where it lies,
  pickup-locked as it is in `GOAL_CELEBRATION`. The clock is stopped.
  Bystanders can skate, but contact between a bystander and a fighter is
  suspended (there is no third man in). More than one pair may lock during
  the phase. It ends when the last fight ends, and then runs
  `_whistle_and_faceoff(stored_dot)` as any stoppage does.
- **A fight ends** when a fighter goes down (a knockdown, §4), when both have
  let go and are more than `DISENGAGE_M` apart for `DISENGAGE_S`, or at
  `FIGHT_MAX_S` (~20 s, the linesmen stepping in). At a period horn or game
  over it is cleared outright, as `BoardPinTracker.clear()` does.
- **The ruleset**: `NHL` and `ARCADE` whistle it. `OFF` has no whistles, so
  it never fights, and neither does free play, the tutorial or a drill,
  whatever their rule set (`FightRules.allowed`).

## 2. Gloves and sticks off

As the lock lands, each fighter **drops his stick and gloves**. They become
cosmetic props on the ice: a `RigidBody3D` per piece, spawned on every peer
from the fighter's drawn hands. They are never on the wire and never touch
the puck. They are cleared at the faceoff teleport, which also gives the
fighter his gear back. While `FIGHTING`:

- The stick is hidden (`SkaterStickRig`), the gloves' rigid parts are swapped
  for **bare fists** (new procedural geometry in `SkaterMeshBuilder`, beside
  `shared_glove_fist`), and the blade plays no puck. The blade marker parks
  at the fist (below), so nothing that reads the blade finds a stick.
- **A fight stance**: a `GaitFightLayer`, an `OVERRIDE` above the stance and
  below the knockdown. It sets a wide, square base and a crouch. Facing is
  pinned square to the opponent (`FacingRules` target = the opponent's
  bearing).

## 3. The hands: physical, the way the stick is

**The fist is the blade.** The tracked IK already turns a cursor into a
reach-limited, speed-limited, acceleration-limited hand target
(`SkaterIKCoordinator.apply_blade_toward`, the dangle's arrive law,
`TopHandIK`'s reach disc about the shoulder). The fight reuses that pipeline
with a different end effector:

- The cursor's ice point names where the **punching fist** goes, in XZ,
  clamped to the arm's reach (shoulder→fist, no stick length). Its height is
  solved, as `DeflectReachRules.lift_to_meet` solves the deflect blade's: it
  rises to the opponent's chin height as the target nears his head, and drops
  toward the chest as it pulls back. So the cursor never has to aim in 3D.
- The fist moves under the dangle's second-order arrive law, with arm-tuned
  caps (`fist_max_speed`, `fist_max_accel`, scaled per build in
  `PlayerAttributes`). A jab is a straight push at the man. A hook is the
  cursor swept round the side of him, so its fist arrives along a curve. Both
  come out of how the cursor moves, never from a move list. A cursor parked
  in his face is a fist resting on his chin, and does nothing.
- **Punch power is closing speed at contact**, the fist's speed toward the
  part it struck relative to that part's velocity. It is the wrister's
  "cursor speed is power" model, so a lazy push lands nothing and a committed
  swing lands hard.
- **The grab** (hold the grab button): the off hand reaches for the nearest
  grip point within its arm's reach. There are two kinds:
  - the **sweater** at the shoulder or collar (`GripTarget.JERSEY`);
  - **his punching arm**, at the sleeve between elbow and wrist
    (`GripTarget.ARM`). Grabbing it is the real fight skill of tying up his
    throwing hand: while you hold it, his fist's reach and speed caps
    collapse.
  Which one you get is physical: whatever your hand reaches first. Let go of
  the button and the grip opens.
- **The grip is a band, not a weld.** It holds the two bodies between a
  stiff-arm minimum and an arm's-length maximum (shoulder to the grip point),
  as a post-step on the integrated motion, the way the board pin's
  `forward_cap` is applied. The force through it is a `PressRules`-style
  contest: each man pulls or pushes with his stride on his own mass, and holds
  with his edges. So you can drag a man, turn him, or yank him off his
  skates. The tug's Δv on him goes to his balance (§4).
- **Swap hands** (a key): the punching and holding hands change over, with a
  short transfer (the grip lets go first). A lefty and a righty get the same
  default (the top hand punches), and can swap.

## 4. What a punch does

All of it host-authoritative, judged from the bodies at present time as body
checks are (§5):

- **Contact volumes**: the head sphere (full effect), the torso capsule (a
  fraction), and **his arms' capsules, which block**. An arm in the fist's
  path absorbs most of it, so keeping your free hand up between you is a
  guard, and grabbing his arm leaves you open on that side.
- **Rattle**: a landed punch adds to a replicated `fight_rattle` timer. Its
  shape is `stagger_timer`'s: one value is both how hard he is rattled and
  how long until it wears off. It pulls his fist caps and his balance
  threshold (`BodyBalanceRules`) down in proportion. A head shot also snaps
  his head back along the punch, a cosmetic reel like the stagger's.
- **The knockdown is his balance, not a hit count.** A punch's impulse and the
  grip's tug both go through `BodyBalanceRules`, the same rule that decides
  checks: the Δv his feet can't carry, against what he can ride, which rattle
  lowers. Past it he goes down (`knockdown_timer`, the existing fall and
  get-up), and that ends the fight. Tired and held at arm's length, both
  fighters are on their skates when the linesmen arrive at `FIGHT_MAX_S`.
- **Feedback**: a punch impact sound and a crowd surge
  (`CrowdEnergyRules`), both scaled by the punch's strength, the way
  `SkaterVFX` scales a check.

## 5. Network

Read `Scripts/networking/CLAUDE.md` before building this. The fight rides
the existing rails:

- **Input**: one new bit, `fight_pressed`, a latched edge like
  `stick_check_pressed`. The flags are full, so the record grows 24 → 25
  bytes. During `FIGHTING` the existing bits are reread rather than new ones
  added: `shoot_held` is grab, `slap_pressed` is swap hands. The cursor is
  already on the wire.
- **State** (`SkaterNetworkState` + `WorldStateCodec`): `fight_role`
  (2 bits), `fight_grip` (2 bits: none, jersey, arm), `fight_punch_side`
  (1 bit), `fight_rattle` (u8, replicated like `stagger_timer`). The opponent
  is not sent: there is one opponent at a time, and every peer finds him as
  the nearest `FIGHTING` opponent. The fists ride the existing
  `top_hand_position` / `blade_position` (punching fist, holding hand)
  `UpperBody`-local, so no new vectors cross the wire.
- **Prediction**: the local fighter predicts his own fist and his own grip
  band. The band's cap is a post-step that both the render and the rewind
  apply, exactly as the pin's `forward_cap` is. A punch's verdict is the
  host's. The locally hit fighter predicts his own rattle from the replicated
  inputs, as a check's victim predicts its stagger.
- **The phase**: `FIGHT` goes out over the existing phase replication, with
  `FIGHT_CALLED` as its whistle RPC.
- `PROTOCOL_VERSION` bump.

## 6. Bots and the HUD

- **Bots**: accept and challenge by their grudge (the decisions table; "The
  grudge", below). How a bot fights is phase 5, below.
- **HUD**: "⟨name⟩ wants to fight — V to drop the gloves" over the
  challenger, for the challenged player only. On the challenger's own screen
  a draining ring shows the window. A `FIGHT` toast at the whistle. All
  strings go through `locale/translations.csv`.
- **Input**: a new rebindable `drop_gloves` action, default **V**. On a pad, the
  right stick already drives the synthesized cursor, so it drives the fist
  with no new code. The default pad bindings are RT grab, RB swap, and D-pad
  up to challenge or accept.

## 7. Build order

Each phase ends with the suite green, lint clean and a local playtest by you.

1. **Lifecycle.** `FightRules` (pure, GUT-tested), `FightTracker`, the
   `drop_gloves` action and input bit, `fight_role` on the wire, the `FIGHT` phase
   with its whistle and faceoff, the HUD prompt and toast. Fighters only
   square up, with sticks still in hand. This proves consent, whistle and
   restart online before any arm work.
2. **Gloves off.** The stick and gloves become props, the bare fists, the
   fight stance layer.
3. **The fist and the grab.** The fist on the tracked IK, the grip targets,
   the grip band and its force contest, the swap. Rendered through
   `render-poses.sh` (a fight stance, a jab, a hook, a held jersey, a held
   arm).
4. **Punch contact.** The contact volumes, rattle, the knockdown through
   balance, sounds, VFX and crowd.
5. **Bots and polish.** How a bot fights and when it would challenge, the camera framing,
   the tutorial line.

## Phase 1 as built

- **Rules and tracker**: `FightRules` (`Scripts/domain/rules/`) and
  `FightTracker` (`Scripts/game/`), tested by `test_fight_rules.gd` and
  `test_fight_tracker.gd`. A press reaches the tracker as
  `Skater.fight_press_pending`, set by `SkaterController.note_fight_press` on
  every live input the controller applies. A fight can start in `PLAYING` and
  `FACEOFF` (the puck dropped), and a second pair can start inside `FIGHT`.
- **Not from the goal celebration.** It ends in the goal's replay, and in
  overtime in the game itself. A fight would have to hold both off, which is
  phase 5 work if you want it.
- **Nothing per skater is on the snapshot yet.** The phase byte and three
  reliable RPCs carry phase 1: `notify_fight_challenge`,
  `notify_fight_challenge_lapsed` and `notify_fight_called`. `fight_role` and
  the rest of §5's state arrive with phase 2, which is the first phase whose
  pose needs them.
- **Fighters only skate.** With no fists yet, a fight ends when the pair have
  been apart for `DISENGAGE_S` or at `FIGHT_MAX_S`. Bots coast through the
  stoppage, fighters included.
- **The challenge is shown as a bubble** over the challenger ("Let's go!"),
  seen by both teams, plus toasts. The man called out is told the key to
  answer with. The squared-up pose is phase 2.
- **Bindings**: `drop_gloves` is V on the keyboard and D-pad right on a pad (D-pad
  up is already the loft step), both rebindable.
- **The Fighting toggle** is on by default (`GameRules.FIGHTING_ENABLED`) and
  rides the lobby-settings and game-config RPCs.

## Phase 2 as built

- **`Skater.fight_role` is on the wire** (`FightRules.Role`: NONE,
  CHALLENGING, FIGHTING), in bits 4–5 of the skater's body-lock byte
  (protocol v100). `FightTracker` is its only writer; it lands every
  broadcast with the pin's role (`SkaterController._adopt_pin`). CHALLENGING
  is replicated but nothing draws it yet.
- **The guard** (`FightGuardRules`): with the gloves off, the top fist sits in
  front of the chin inside its shoulder, and the blade marker is parked under
  it, so a fist drawn from the "shaft" through it is thumb up. The shot
  machine stands down while fighting (`SkaterController._apply_state`): a
  wind-up in hand is called off and nothing new starts. The guard is pure in
  the frame, so a reconcile replay lays the same one, and the post-reconcile
  dispatch re-applies it. `SkaterPoseBridge` has a `FIGHT` owner and eases the
  hands up over `FightGuardRules.EASE_S`. The off hand comes up at render rate
  (`SkaterIKCoordinator.update_bottom_hand`) off the replicated role, so every
  machine draws it.
- **Facing squares up to the cursor while fighting**, as the stance's does
  (`FacingRules.solve`'s stance flag), rather than to the opponent: the cursor
  is input, so prediction and the host agree on it exactly.
- **The stance** is `GaitFightLayer`: a crouch floor, a base set out from
  under the hips and the chest over the knees (`fight_stance_*`,
  `fight_chest_deg` on `SkaterController`).
- **Bare fists**: `SkaterBodyMesh` has a bare variant per glove pair
  (`SkaterRigidParts.upper_body_mesh(top_right, bare)`), the glove's fist at
  `BARE_FIST_SCALE` and a wrist where the cuff was, both in the skin's zone.
  `SkaterConnectedRig` switches to it on `Skater.gloves_off()`, and the arm rig
  gives each bare fist `FightGuardRules.FIST_GRIP_AXIS`.
- **The stick is hidden** (shaft, knob and blade; `Skater._show_stick`), and
  **the stick and gloves drop** (`SkaterDroppedGear`, a `Skater` collaborator).
  The stick is copied from its live nodes, each glove from its bones with
  `SkaterRigidParts.glove_mesh` drawn by the body's material. The pieces fall
  and tumble, slide to a stop lying flat, and go when the role clears. They
  are mesh only, on every machine, never on the wire.
- **Seen with** `render-poses.sh --only=fight`: the guard from three sides, the
  drop falling and down, and a squared-up pair. **Tested by**
  `test_fight_guard.gd`.
- **Not yet**: a challenger's squared-up pose (CHALLENGING), and a pair whose
  fight ends while another goes on picks its gear up at once.

## Phase 3 as built

- **The fists are `SkaterFightHands`**, a `SkaterController` collaborator. Each
  arm's fist rides its own marker: the top hand's on `TopHand`, the bottom
  hand's on the stick's `Blade` marker, which the stick on the ice frees. So
  the wire carries both fists, and the bottom arm is drawn to the blade marker
  (`SkaterIKCoordinator.update_bottom_hand`). This replaces phase 2's parked
  blade and `apply_fight_guard`.
- **The punching fist** (`FightFistRules`): the cursor's point on the ice,
  held within the arm's reach (`SkaterFightHands.arm_reach`) and at least
  `MIN_FORWARD_M` in front of the shoulder. Its height rises from the guard's
  to the other man's chin as the arm straightens. It chases that target on an
  arrive law capped at `MAX_SPEED_M_S` (9 m/s) and `MAX_ACCEL_M_S2`. With the
  cursor close in, the fist sits up in a guard; driven out at him, it's a
  punch.
- **The holding hand** keeps the guard (`FightGuardRules.guard_hand`) until
  the grab button (shoot, held) takes a grip (`FightHoldRules.choose`). The
  grip is his sweater at the chest, or his punching arm, but **only while that
  arm is thrown** (fist past `ARM_THROWN_SHARE` of its reach). Without that
  rule, two guards an arm apart always grabbed the forearm in front of the
  hand. So catching the punch is a timing skill, and from a guard you take
  the sweater. A held arm reaches `TIED_REACH_SHARE` and moves at
  `TIED_SPEED_SHARE` (`FightHoldRules.tied`). A grip is torn away past
  `TEAR_SLACK_M`.
- **The swap** (slap button) changes which arm punches
  (`Skater.fight_punch_side`) and lets the grip go. After a swap, or a torn
  grip, the grab waits for the button to come up before it takes hold again.
  Swapping is also how a fighter whose punching arm is held frees it: the held
  arm is no longer the one punching.
- **The band** (`FightHoldRules.band_along`, `SkaterController._apply_fight_band`):
  a velocity post-step along the line between the pair, after the movement
  and the press. The pair never come closer than touching. While either holds
  the other, they're never further apart than the holder's reach plus
  `BAND_BODY_M`. The change is shared by mass. **Deviation from §3**: this is
  a mass-shared band, not a `PressRules` force contest with edges. A held man
  can be dragged by skating away, and the heavier man moves less, but bracing
  on the edges doesn't resist yet. The tug's effect on balance is phase 4.
- **Facing squares up to the man**, not the cursor, which now throws the fist
  (`SkaterController.fight_facing_dir`).
- **The partner read** follows the press's: the host reads the partner's live
  body, and a client reads him in the snapshot sampled at the input's stamp
  (`LocalController._read_fight_partner`). The partner is the nearest fighter
  on the other team.
- **The wire**: one new skater byte (grip type, 2 bits, and punching side, 1
  bit; protocol v101, replay format 21). A client keeps its own grip and side,
  as it predicts them, and a remote takes his off the wire.
- **The fists are stepped on live ticks only.** A reconcile replay lays the
  fists the live tick left (`lay_fight_hands`) rather than playing the arrive
  law twice. So a client's own fists and the host's copy of them can differ by
  the time the role took to reach the client. That matters in phase 4, where
  the host judges punches from its own copy.
- **Fighting bots** run the fight tick too, which fixed a phase-2 bug where a
  bot fighter's top fist never came up. What they do with it is phase 5.
- **Seen with** `render-poses.sh --only=fight` (the guard, a jab in flight and
  at reach, a hook, the sweater held, an arm caught, the hands swapped).
  **Tested by** `test_fight_hands.gd` and `test_fight_fist_and_hold_rules.gd`.

## Phase 4 as built

- **The judge** (`FightPunchJudge`, host-only, ticked by `GameManager` after
  the tracker) sweeps each fighter's punching fist from last tick to this one
  through the other man's head (a ball over his chin), his chest (a ball under
  his shoulders) and both his arms (capsules from shoulder to fist).
  `FightPunchRules` has the volumes and sweeps. The first volume the fist meets
  is the hit, and an arm is a **block**. A fist closing slower than
  `MIN_LAND_M_S` (2.5 m/s) is a hand on him, not a punch. A landed fist lands
  nothing more for `HIT_COOLDOWN_S`. It's judged on the host's copy of both
  bodies and both fists at the host's present, as a body check is.
- **What a punch does** (`SkaterController.absorb_punch`, host):
  - It moves him by its `Δv`: the arm's striking mass on his body's, ~0.4 m/s
    at full speed.
  - It adds **rattle**: a timer, the head's at full speed `RATTLE_HEAD_S`, the
    chest's a share of that, a block's a sliver, capped at `RATTLE_MAX_S`. The
    rattle wears off at `RATTLE_DECAY_PER_S` on the host and is adopted every
    broadcast by every machine. It's replicated in the fight byte's bits 3–7
    (protocol v102).
  - It reels him as a check of strength `REEL_HEAD_M_S` would (the stagger,
    with its recoil and wobble).
  - It **puts him down** through the check's own absorb path
    (`_absorb_hit`), with the `Δv` his balance reads grown by
    `FightPunchRules.balance_scale` (his balance shrunk by the rattle). A punch
    never drops a sound man: a full-speed one is a sixth of what his balance
    rides. Fully rattled, a clean head shot does
    (`test_fight_punch_rules.gd` holds both). So a knockdown is
    wobbled-then-dropped.
- **A rattled fist** is slower (`FightPunchRules.fist_scale`).
- **A man put down ends the fight** (`FightTracker._step_fights`).
- **Feedback** on every peer (`notify_punch_landed`, reliable): the check's
  thud played shorter and brighter at his head, a half-size impact burst, a
  remote victim's knockback lead, and a crowd swell on a hard one
  (`GameManager.punch_landed`). The crowd roars as the gloves drop
  (`fight_called`). There's no new audio file: the punch is the check's thud
  pitched up.
- **Not modelled**: the grip's tug on balance (dragging a man doesn't topple
  him), lag compensation for a remote attacker's punch, and an uppercut or
  body-shot aim (the fist's height comes from its extension alone).

## Phase 5 as built

- **A bot fights with the human's three controls** (`AIFightBrain`, in
  `Scripts/domain/ai/`, engine-free; fed each fight tick by
  `AIController._fight_tick`, which reads his head and fists off the partner's
  markers and the grips through `FightHoldRules`). It sets the cursor, the
  grab and the swap, brakes, and the fight tick does the rest, so a bot's fist
  obeys the same reach, speed and grip rules a human's does.
- **Between punches** the cursor rests `GUARD_AHEAD_M` in front of it, the
  fist up in a guard, and the grab holds his sweater.
- **A punch** drives the cursor `THROUGH_M` past his head, `AROUND_M` round
  the side his guard leaves open (away from whichever of his fists sits
  nearer the line to his head), for `THROW_S`, then back for `RECOVER_S`. The
  gap between punches rides `check_aggression` (`GAP_PASSIVE_S` at none,
  `GAP_AGGRESSIVE_S` at full), so Easy throws every 2 s and Hard every 0.6 s.
  Bots' cadences are staggered by peer id. It doesn't throw while he holds its
  punching arm.
- **Reads, a reaction late** (`carrier_reaction_delay_s`): his punching arm
  thrown, which it catches by letting the grab go for a tick so it takes
  again on the arm; and its own punching arm held, which it frees with the
  swap. Both are the `ties_up_arms` cognition gate, closed on Easy.
- **The fight controls** are toasted to a human whose fight is called (aim to
  punch, hold shoot to grab, slapshot to swap hands), with the keys of the
  device in use.
- **Tested by** `test_ai_fight_brain.gd`.
- **Not yet**: the tutorial line, a bot that skates off to
  disengage or presses the band, and a body-shot aim.

## The grudge

- **A grudge per bot per opponent** (`FightGrudges`, host-only, by peer id;
  `FightGrudgeRules` holds the numbers, all feel tunables). Every credited
  body check (`HitTracker.impact_landed`, so committed, cross-team and on a
  carrier or a man just off the puck) adds to it through
  `FightTracker.note_check`: to the hit bot's grudge against the hitter by
  the check's force (`GAIN_PER_FULL_CHECK` a full check), and
  `TEAMMATE_SHARE` of that to each of its teammates'. It drains at
  `DECAY_PER_S`, a whole accept level in three minutes, and caps at
  `MAX_LEVEL`. There is no knockdown term: a knockdown is decided in the
  victim's tick after the check is credited, so force alone carries it, and a
  check hard enough to floor a man counts about 1.4 full ones.
- **At `ACCEPT_LEVEL`** (two full checks on the bot) it answers that man's
  challenge at once; below it, the challenge lapses unanswered.
- **At `CHALLENGE_LEVEL`** (four) it calls him out (`FightTracker._bots_call_out`):
  the nearest man in front of it within challenge reach it holds that grudge
  against, past any nearer man, never while it carries the puck, and on the
  same cooldown a lapsed challenge gives a human. It does not skate to him: it
  calls him out when play brings them face to face.
- **Bots hold grudges against bots** too, so two bot teams can fight with no
  human involved. A grudge is one way round, so the hit man's grudge is the
  one that rises: a bot it calls out answers only if it holds one back.
- **A fight spends the pair's grudges** against each other; their teammates'
  stand. A new match or a rematch clears them all.
- **Tested by** `test_fight_grudges.gd` and `test_fight_tracker.gd`.

## The fight camera

Through the stoppage, `GameCamera` keeps its own top-down framing, locked,
with its centre pinned on the fight (`GameManager.fight_focus`: the player's
own fight, or the nearest) instead of on the player, and the puck out of the
fit, so it sits at its closest zoom. Its usual smoothing carries it there and
back. An orbiting close-up was tried and dropped: the cursor is unprojected
through this camera onto the ice, and skating and the fist both read it, so a
moving view moved the controls. Spectator cameras (`CameraDirector`) are
unchanged.
