# Fighting — design plan

Status: **approved; phase 1 (lifecycle) built**, awaiting a local playtest.
Phases 2–5 are not started. Where phase 1 differs from the text below, the
"Phase 1 as built" section says how.

Two skaters can fight. Both must agree to it, the referee blows the play
dead, and the fight is played with the same hands the stick is: the cursor
places a fist exactly as it places the blade, and a button holds the other
man's sweater. There is no penalty; the fight ends, play restarts with a
faceoff, and both stay on.

## Decisions already made (from chat, 2026-11-11)

| Question | Answer |
|---|---|
| Consent | **Challenge + accept.** One player presses Fight squared up to an opponent nearby; the opponent has a short window to press it back. An unanswered challenge just lapses, with nothing lost. |
| When, and the whistle | **Any time.** In live play the whistle goes the instant both have agreed; in dead time (a faceoff set-up) the fight runs before the next faceoff. A faceoff follows every fight. The goal celebration is the one exception (see *Phase 1 as built*). |
| Afterwards | **No penalty.** Both stay on. |
| Controls | **The cursor drives the fist, and a button grabs.** The fist uses the stick's IK, reach and speed limits; punch power is the fist's speed at contact. Holding a button grabs with the other hand and keeps the grip. A key swaps the hands. |
| Bots | **Never challenge, and accept every challenge at once**, for now, so a fight can be tested against them. How a bot decides to fight comes later. |
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
  (`GameRules.nearest_faceoff_dot`). From `GOAL_CELEBRATION` or
  `FACEOFF_PREP` it stores the dot that phase was heading for. Every path
  enters a **new phase `GamePhase.Phase.FIGHT`**, appended as ordinal 7 so
  `.mreplay` files stay valid.
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

- **Bots**: accept at once and never challenge (the decisions table); how a
  bot fights once fists exist is phase 5.
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
  every input the controller applies, including the locked faceoff paths. A
  fight can start in `PLAYING`, `FACEOFF` and `FACEOFF_PREP`, and a second
  pair can start inside `FIGHT`.
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
