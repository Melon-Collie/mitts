# Player Attributes

Scope: `Scripts/domain/state/player_attributes.gd` and its application path
(`SkaterController.apply_attributes`, `SkaterAppearanceCoordinator.apply`).
The original design record is `docs/attributes-v4-plan.md`. Where it and this
file disagree, this file is current.

## The model

A build is **body + gear**, six ints:

- **Height**: inches, every inch from 5'7" to 6'8". Tables are authored at five
  anchor heights (`ANCHOR_INCHES`) and interpolated.
- **Weight**: pounds, bounded per height by a BMI band (23.0–29.0) and an
  absolute 162 lb floor. The ratio governs 5'11" and up, and the floor governs
  5'7"–5'10", where a ratio stops meaning anything. Implausible bodies can't be
  represented. `frame_t()` (0 lean, 0.5 neutral, 1 heavy) is the
  height-independent "how heavy for my frame" quantity the frame tables index
  by. It is piecewise about the neutral, because the band is asymmetric.
- **Four gear slots**: skate profile, blade curve, stick flex, stick length.
  Each is 0/1/2, with 1 = balanced.

**Every axis is lateral.** There is no power budget and no legality check.
Validation only coerces (`coerce_height`, `coerce_weight`, the gear clamp), so a
forged build lands on the nearest legal body. The neutral build is
**6'1" / 201 lb / all-balanced** (`PlayerAttributes.neutral()`), the NHL-average
frame. There every multiplier is 1.0 and a skater plays the controller's
defaults.

## The constitution

A lever may scale **outputs** or **geometry**, never **fidelity**. "Your hands
are you": no build tracks the cursor more precisely than another. Stickhandling
differences come from lever geometry. The blade caps derive from the build's
sweep lever (stick + arm ROM, normalized to the neutral build's lever):

- **Tip speed ∝ lever.** The same angular gesture sweeps a longer blade faster
  in m/s. `test_blade_lever_calibration` pins traverse time across a build's own
  reach as roughly flat (≤8%).
- **The inertia cap ∝ 1/lever^k** (`blade_inertia_exponent`). The long lever
  sweeps but can't cut back; the short lever is the scalpel.

Physical play works the same way. Mass is the whole system: check delivery and
brace emerge from the collision resolver's reduced-mass math, and no attribute
term scales them.

## What each dial routes to

| dial | scales | accessor(s) |
|---|---|---|
| Height | first-step burst (favors small builds: a shorter leg cycles faster) | `accel_mult` |
| | agility baseline (favors small builds) | `agility_mult` |
| | charged-shot ceiling (favors big builds), and slapper wind-up WITH it (the long lever loads slower) | `shot_power_mult` (wrister), `slapper_power_mult`, `shot_charge_mult` |
| | skeleton, arm length and ROM, hand heights (mesh-native 5'10" = 1.0) | `height_mult` |
| | stick cut to the body (~0.65× the height deviation) | `stick_len_mult` |
| | helmet (a mild table of its own; heads are near-constant) | `head_bulk_mult` |
| Weight | mass, linear in pounds (0.79–1.28) | `mass_mult` |
| | first-step burst (favors lean builds) | `accel_mult` |
| | agility bite (F = mv²/r: heavy turns wide and stops long) | `agility_mult` |
| Both | girth = sqrt(mass/height): every lateral body part and the hitbox radius | `girth_mult` |
| | glide: air drag over mass with area ∝ sqrt(mass·height) is 1 / girth, so a heavy-for-his-height body coasts | `glide_drag_mult` |

**Size never buys top speed.** If it did, every build would be the tallest one.
Top speed is the skate profile's alone: `speed_mult` is the profile's lean,
and `top_speed_mult` counts it twice, once raw and once through its position in
the 20–25 mph burst band. Every body skates the same ~22.4 mph on balanced
skates. `carry_speed_mult` rises with the same band position and is the whole
cost of carrying at speed. Drag never sets top speed either: the thrust against
drag equilibrium (~15.6 m/s) sits well past the cap, so glide shapes only the
coast and the approach to it.

So size trades things with no single right answer. Small and lean wins the
first step, the corner and the quicker wind-up. Big and heavy wins reach, shot
power, every contact and the coast.

## The gear slots

| slot | options | what it leans |
|---|---|---|
| Skate profile | agility / balanced / power | power: +top speed and glide, −agility (lateral grip included); agility: the reverse plus first step. Stacked with the body, agility runs ~0.84–1.15. |
| Blade curve | M88 / M92 / M28 | the loft **angle ladder** (each level a set launch angle, steeper on the M28; design of record `docs/elevation-rework-plan.md`), backhand (1.08 / 1.00 / 0.90, never past parity), slapper power (±3%), reception ceiling (±7%, never `pickup_max_speed`). `Skater.apply_blade_pattern` renders the pick. |
| Stick flex | whippy / medium / stiff | stiff is the **slapshot stick**: slapper ceiling (±6%) **and** slapper wind-up, both in the same direction (a lateral slot trades, it never stacks). Whippy is the **wrist-shot stick**: `wrister_unloaded_share` 0.70 / 0.60 / 0.50, the share of a wrister the shaft carries with no torso load. The wrister ceiling is flex-free, so they break even on a fully loaded wrister. The shaft's visible bow scales with the pick (`stick_bend_mult`, cosmetic). `flex_number()` shows the stick's real retail stiffness, fitted to weight; it is display-only. |
| Stick length | short / standard / long | ±4% on the height's cut. Feeds reach, poke and claim range, the blade-cap lever and the stick mesh. |

## Bots read the same body

Bots never see the tables. `SkaterController.build_ai_caps` snapshots the
scaled fields the physics drives with (top speed, thrust, reach, blade speed,
lateral grip, backhand coefficient, wrister ceiling, reception lean, mass,
radius) into `AISkaterCaps`, so the AI never disagrees with the body.

## Where builds come from

- **Players** pick one build on the player screen (`player_settings_popup.gd`:
  height and weight sliders; height moves preserve `frame_t`) and its locker
  (`locker_popup.gd`: the gear rows). There are no presets.
- **Prefs** (`player_prefs.gd`) store the six ints under `attr_scale_version`
  5. An older save loads the neutral build.
- **Bots** carry curated cards in `data/bot_identities.json`, read through
  `PlayerAttributes.from_dict`, which takes only the native keys.
- **Online**, the build locks at join: six ints through `request_join` /
  `spawn_remote_skater`, coerced by the host. In free play a pick re-applies
  immediately.

## Rules for changing it

- All tuning is private consts in `player_attributes.gd`, read through named
  accessors. **Never index a `_*` table outside that file.** The file header
  says how to add an "X scales Y" rule.
- Coupled levers derive from their partner so they can't drift: edge glide
  from height agility, slapper wind-up from shot power.
- `apply_attributes` and `SkaterAppearanceCoordinator.apply` are idempotent.
  They capture bases on the first call and recompute live = base × multiplier
  every call, so repeated applies never compound. A new scaled field needs its
  base captured in `_capture_attribute_bases`.
- The neutral build must stay at 1.0 everywhere (`test_neutral_is_all_ones`).
  That is what lets the controller's defaults *be* the neutral build.
