# Goalie possession — plan

Status: **approved** — Option B, clean takeaway on a strip, all tiers handle
the puck with decision quality scaling. Built in the phases below.

## The ask

The goalie plays the puck the way a skater does: he gets it on his blade, holds
it, and releases it with a real shot or pass. Opponents can take it off him.
This replaces three pieces of special-case behaviour:

| Today | Becomes |
|---|---|
| Unpressured glove catch → puck set down at his feet → crease sweep | Catch → puck to his blade → he plays it |
| Loose puck in the crease → velocity written onto the puck from up to 1.7 m away (the "force field" sweep) | His blade has to reach the puck to gain it → he plays it |
| Rim behind the net → trap, "stop it, leave it, get back" | Trap → he plays it |

Decided: **he shoots/clears and passes**, **opponents can strip him**, and the
three sources above are in. **Covers are out of scope** — the pressured catch
and the smother keep their freeze / hold-and-release path, including the
cover-release sweep.

This reverses the documented doctrine in `Scripts/controllers/CLAUDE.md`
("He never carries and never passes") and `docs/gameplay-design.md`. Both get
rewritten as part of the work.

## The central choice: what "carrier" means for a goalie

`Puck.carrier` is typed `Skater`, and every system downstream of it names the
carrier by a registry peer id. That covers the wire (`carrier_idx` is an index
into the snapshot's skater list), the client carry pins, all three
lag-compensated claim resolvers (which forward-predict the carrier through a
`SkaterController`), stats (`PlayerRecord`), and roughly forty AI readers of
`carrier_peer_id`. A goalie has no peer id, no record, no `SkaterNetworkState`
and no forward prediction. Several of those paths fail *silently* on an unknown
id — the codec writes "no carrier", and the client stays in loose-puck mode
while the host pins.

**Option A — make the goalie a real `Puck.carrier`.** Abstract the carrier,
reserve goalie ids, extend the wire and the codec, teach every claim resolver
and AI reader about goalie carriers. This is the most uniform result, and it
touches nearly every invariant in `Scripts/networking/CLAUDE.md`.

**Option B (chosen) — goalie-held puck.** `GoalieController` owns
possession. The puck stays carrier-less to the netcode (`carrier_peer_id ==
-1`) and is pinned to his blade with the existing `motion_pinned` mechanism —
the one the glove hold already uses — but *not* `pickup_locked`, so it is live
to opposing blades. Everything the player sees is skater-consistent: he carries
it on his stick, releases through `ShotMechanics`, and loses it to a stick.
What is *not* uniform is the plumbing underneath, and that is where the risk is
lowest.

The rest of this plan assumes B.

## Design (Option B)

### 1. Possession state (host)

- New `GoalieStateMachine.State.HANDLING`, appended (the enum is append-only on
  the wire; `state_enum` already carries the half-butterfly states).
- A new collaborator, `GoaliePuckHandling`, laid out like `GoaliePuckPlay`:
  tuning pushed at config time, its own state, one `advance()` per tick, and an
  explicit requests block the controller reads back. The controller performs
  every puck write.
- Each tick he holds it: `motion_pinned = true`. The puck goes to his blade's
  carry point. Its `linear_velocity` is set to the blade's velocity, so client
  prediction and opponent reads see a moving puck rather than a teleporting one.
- Possession ends when:
  - he releases it;
  - any skater becomes `puck.carrier` (the strip, §4);
  - a whistle or phase change happens;
  - the hold limit expires (§3).

### 2. Gaining it

- **Catch.** At the end of the unpressured hold, the puck goes from the glove
  to the blade, and he enters HANDLING instead of `_drop_caught_puck`.
  Pressured catches are unchanged.
- **Crease.** The force-field sweep is removed for loose pucks. He reaches with
  the existing blade-yaw solve (`GoalieStickRules.yaw_to_target`, already used
  by the standing and paddle sweeps). He gains the puck only when the blade's
  contact point gets within a pickup radius of a slow puck that is on the ice.
  That uses the same pickup-radius rule the skaters use, so "he got his stick
  on it" means the same thing for everyone. A puck his blade cannot reach stays
  loose. The cover read (every lane covered and an opponent on the puck) is
  unchanged.
- **Rim.** `PLAYING_PUCK`'s STOP phase becomes the gain. HANDLING then runs
  from behind the net. The trip's conservative go/abort races stay exactly as
  they are, because getting there safely is still the hard part.

### 3. Deciding and releasing

These are pure, reused evaluators. No new scoring model is invented here.

- **Pass:** for each teammate, use `AIActionScoring.lane_clear`, `AIPassLead.lead`,
  `pass_launch_speed`, `pass_miss_prob`, `pass_lane_blocked_by_net` and
  `pass_crosses_own_slot`, valued against `turnover_cost`.
- **Clear:** use `AIActionScoring.dump_clear_candidates`, which already
  enumerates legal clears (no icing, the puck doesn't stop in our zone).
- **Rim:** use `AIRimPass` behind the net.
- **Release:** `ShotMechanics.release_wrister` runs from his blade position,
  with the quick-pass path for passes and the charged path for clears. Its
  `direction * power` goes onto the puck through `apply_release_velocity`. This
  is the same velocity a skater produces for the same target, which is the
  consistency the ask is about.
- **Timing:** a short read beat after gaining the puck, then release the best
  option. Pressure shortens the beat: an opponent's arrival time at the puck,
  from the forechecker model `GoaliePuckPlay` already uses. A hard hold limit
  forces the best available option, never a hold-forever.
- **Difficulty:** decision quality scales per `GoalieSkillProfile` the way bot
  pass aim error does. Weaker goalies misjudge lanes and turn it over more,
  which is how real goalies differ.

### 4. Getting stripped

Because the puck is carrier-less and live, an opposing skater who gets a blade
to it **takes it**. This runs through the existing pickup paths: the host loop
for bots, and the lag-compensated `PickupClaimResolver` for human clients. No
new claim type, no new RPC. The moment `puck.carrier != null`, the goalie's
possession ends.

A dedicated poke or stick-lift against him is not built: it would need a
goalie-aware branch in two claim resolvers, a goalie blade and top hand on the
wire, and goalie forward prediction. The outcome a poke would produce — a
forechecker whose stick gets there wins the puck — falls out of machinery that
already works. The takeaway is clean, not a knock-loose.

### 5. Clients (the netcode part)

**No client change.** The pin this section first proposed would have broken
the property it was meant to protect. To the netcode the goalie-held puck is a
loose puck, so clients already predict it to host-present plus their input lead
— the same instant `LagCompRewind.puck_view_time` rewinds it to for a pickup
claim. Render == rewind already holds for a human's strip. Pinning it to the
goalie's rendered blade at `H − d` would move the render off that instant and
force a matching special case in the claim resolver.

What is left is cosmetic: the goalie draws at `H − d` and the puck at
host-present, so while he turns with it the puck leads his blade by the turn
over that window. He is planted while he holds it, so it shows only during the
turn up ice off a rim stop.

- **Wire.** `HANDLING` is a new `state_enum` value: protocol v66.

### 6. Skater AI

- To the bots a goalie-held puck reads as loose, so **both** teams would chase
  it. Built: the chase election withholds it from his own team
  (`GameManager._goalie_has_puck`), so his teammates hold their positional
  roles while the opponents' elected chaser forechecks it.
  - Not built: a possession read that has his teammates actively get open for
    the outlet — the team brain still plays the LOOSE shape. A follow-up.
- Pass reception is already velocity-based (`_incoming_pass_to_me`), so a bot
  receives a goalie pass without knowing who made it.
- **Stats:** goalies have no `PlayerRecord`, so a goalie pass earns no assist.
  That is a known gap, and a separate issue.

## Phases

1. **Host mechanics** — built. The HANDLING state, all three gains, the
   pass/clear decision and release, strip by pickup, the hold limit.
   `test_goalie_puck_handling.gd`.
2. **Clients** — no change needed (§5); protocol v66.
3. **Bot awareness** — the chase election half is built; the "get open for the
   outlet" possession read is a follow-up (§6).
4. **Docs** — the puck-play doctrine (`Scripts/controllers/CLAUDE.md`) and the
   gameplay-design paragraph are rewritten.
