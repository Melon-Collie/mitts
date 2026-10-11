# Skating sound plan

The skating should sound like what the legs are doing. The gait already knows
what that is: which state the skater is in, when each skate pushes, how hard
the edges are loaded, and when a stop is digging in. It derives all of it from
replicated state, on every peer, at render rate, and never in reconcile replay
(`Scripts/controllers/CLAUDE.md`). So the sounds key off the gait and need
nothing new on the wire.

## What was there

- `skate_loop.ogg` was one stride (a bite at 62 ms, a ~300 ms scrape, then
  0.6 s of room tone) looped on its own clock: a push about once a second
  whatever the legs did, through glides and carves alike, its volume and
  pitch following speed.
- `skate_brake.wav`, a 0.28 s scrape, fired once when braking began however
  long the stop lasted. The skid and the carve had no sound.

## The layers

| Layer | What it is | What drives it |
|---|---|---|
| Push | a bite and a short scrape per push, at the skate that pushed | each leg's push starting (`SkaterLocomotion.l_push` / `r_push` rising from 0) |
| Glide bed | the steel's hiss while coasting | speed |
| Carve | a louder, brighter sustained edge | the edges' load in a turn (the carve, the tight turn, a crossover's under-push) |
| Stop | a bite, then a spray that lasts the deceleration | `mix.stop` × the speed being shed; the skid softer |
| Touches | small blade touchdowns | a lifted skate landing (`SkaterLocomotion.l_dy` / `r_dy` back to 0) |
| Start | a short, hard dig per push | a push from near a standstill against the acceleration it makes |

## Phases

1. **Pushes on the gait** (built). The coordinator emits
   `Skater.skate_pushed(left, strength, dig)` on each push's onset; strength is
   `SkaterLocomotion.push_strength` (intensity × push scale × the stroking
   states' share). `SkaterSoundController` plays a take at that skate on a
   player of its own per foot, its level following strength.
2. **The stop and the skid** (built) as a sustained scrape over the stop's
   weight and deceleration, with an onset bite.
3. **Glide and carve beds** (built), two loops whose levels follow speed and
   edge load.
4. **Polish** (built): touchdowns, the start's chop, the mix of the local
   skater's own skating against everyone else's, a voice budget for the lobby.

## Recordings

Every cue is a file mastered by `tools/normalize_sfx.py` and listed in
`SoundManager` (`_SOUND_PATHS`, `_TAKE_COUNTS` for several takes, `_MIX_DB`,
`_UNDER_REFERENCE_DB`), so swapping a recording in is replacing the files and,
if the take count or the mastering shortfall changes, those two numbers. The
placeholders are cut from the old stride recording.

| Cue | Placeholder | Wanted |
|---|---|---|
| `skate_push_01..06.wav` | the stride, re-pitched ±10% and tilted ±3 dB, 400 ms from 3 ms before the bite | 6–10 pushes, mono, ~300–500 ms, cut 3 ms before the bite |
| `skate_glide.wav` | band-limited noise (2.5–9 kHz), 4 s, its spectrum filtered round the circle so the loop has no seam | a seamless 2–4 s loop of a coasting glide, mono, loop on in its `.import` |
| `skate_carve.wav` | grains of the stride's scrape tail, overlap-added round a 3 s circle | a seamless 2–4 s loop of a held edge, mono, loop on in its `.import` |
| `skate_dig_01..04.wav` | push takes 1–5, re-pitched down 6–12%, saturated, 200 ms decaying over 60 ms | 4–6 hard digs from a standstill, mono, ~150–250 ms, cut 3 ms before the bite |
| `skate_touch_01..04.wav` | push takes, re-pitched up 12–24%, thinned, 80 ms decaying over 14 ms | 4–6 blades set down on the ice, mono, ~50–100 ms |
| `skate_brake.wav` (the stop's bite) | the original | a short bite as the blades dig in, mono |
| `skate_scrape.wav` (the stop's sustain) | grains of `skate_brake.wav`'s steady scrape, overlap-added round a 2 s circle so the loop has no seam | a seamless 2–4 s loop of a held stop's spray, mono, loop on in its `.import` (`edit/loop_mode=2`) |

## Phase 1 as built

- Each push is heard once. A leg's push weight is exactly 0 while it is not
  pushing (`max(-s, 0)` per stroking state), so a push is under way from the
  first pass above 0.001, whatever the frame rate, and is heard on the first
  pass of it the stroke (or, since phase 4, a start's dig) is past 0.05.
- Both gait paths publish the same channels (`push_l`, `push_r`,
  `push_strength` on the coordinator; `NativeSkaterGait.get_push`), and
  `test_native_gait_parity.gd` compares them.
- `test_gait_step_events.gd`: each leg pushes once per stride cycle, the legs
  alternate, and a coasting skater makes no push.
- Level: full at strength 1 (a flat-out stride), −14 dB at the floor; the cue
  sits at −6 in the mix, with the quieter body and stick sounds.
- The fixed-clock loop is gone; phase 3's glide bed took over its hiss.

## Phase 2 as built

- The gait publishes the stop's and the skid's weights (`stop_weight`,
  `skid_weight` on the coordinator; `NativeSkaterGait.get_sound`; held by
  `test_native_gait_parity.gd`), read through `SkaterController.skate_sound`
  as `GoalieSoundController` reads `GoalieController.stance`.
- The scrape's amplitude is the share of the legs shedding speed — the stop
  whole, the skid at half — times speed against 8 m/s; under −30 dB it stops.
  The bite plays once as the stop's weight passes half at 1.5 m/s or more, and
  re-arms when the stop lets go.
- Measured (`test_skate_loops.gd`): a stop from speed bites once and
  scrapes up to −1.7 dB for ~0.9 s, silent once stopped; the skid scrapes to
  −7.5 dB without a bite; a stride does not scrape.
- The stop's sound follows the gait's stop rather than the brake button: it
  comes in with the legs turning across, and the shot block's plant (which sets
  `is_braking` for its spray) no longer plays the brake.

## Phase 3 as built

- The gait publishes the edges' load in a turn (`turn_load` on the
  coordinator, `SkaterLocomotion.turning` unsigned: the share of the edge's
  grip the travel's curve uses; the third channel of
  `NativeSkaterGait.get_sound`), read with the stop's weights through
  `SkaterController.skate_sound`.
- The glide hisses at speed against 10 m/s, given up by the stop's weight, so
  a stop is all scrape. It plays under every push: the pushes ride on it.
- The carve is the turn load times speed against 8 m/s, its pitch rising up to
  8% as the edge loads. A crossover loads the edge too, so it carves under its
  pushes.
- The scrape, the glide and the carve share one held-loop path: under −30 dB a
  loop stops, and a level or pitch is written only when it moves.
- Mix: the carve at −8, the glide at −10, under the pushes and the scrape and
  over the menu click.
- Measured (`test_skate_loops.gd`): a stride glides at −0.1 dB and neither
  scrapes nor carves; a coasting curve held from speed carves at −0.4 dB
  through all of it, pitched up 7.8%; a stopped skater neither scrapes nor
  glides.

## Phase 4 as built

- **Landings.** The gait publishes each skate's lift (`lift_l`, `lift_r` on the
  coordinator; `NativeSkaterGait.get_lift`). A lift is exactly 0 on the ice, so
  a skate has landed once it is back under 0.5 mm, and is heard if it rose past
  3 mm (`Skater.skate_touched(left, lift)`, the highest lift since the last
  landing). Its level follows that height, full at 30 mm (a crossover's
  over-step), down to −18 dB. Measured (`test_gait_step_events.gd`): each skate
  lands once a cycle striding (lifts to 22 mm) and in crossovers (30 mm), and
  never coasting.
- **The start.** A push also carries the start's dig
  (`SkaterLocomotion.dig_strength`: how near a standstill, times the forward
  acceleration against `stride_effort_ref_accel`, times the share of stride and
  backward the classifier is skating toward). A push is heard once either is
  past 0.05, and plays a dig take while the dig outweighs the stroke. A start's
  first push is heard at its onset at 0.96 dig. Its stroke strength there is
  0.00, which is why phase 1 heard it late and quiet.
- **The gait draws a start as one push.** From rest to 5.4 m/s the right leg
  pushes once, for ~0.75 s (`dig_in_cadence_rate` 4.5 rad/s), so a start is
  heard as one dig and then the stride. Chopping it into quick steps is a gait
  change, and the dig sound follows it without change.
- **Steps share a player per skate.** A push, a dig and a landing are the same
  blade, so each new step takes over that skate's player. A landing comes three
  quarters of a cycle after its push, so a push's tail is rarely cut.
- **Your own skating in front.** Another skater's steps, glide and carve play
  6 dB under the local skater's (`Skater.is_local_skater`). Stops play full
  for everyone, since a stop is an event. A spectator has no local skater, so
  everything sits at the lower level.
- **The voice budget.** Only held loops are budgeted: one-shots end on their
  own, but the scrape, glide and carve run as long as the gait holds them, up
  to 30 in 5v5. Each controller writes how loud each of its loops arrives at
  the listener (the cue's level plus the camera's inverse-distance falloff)
  into a lobby-wide table each frame, and plays a loop only while it is among
  the 8 loudest. A playing loop ranks 3 dB louder, so two near-equal loops do
  not trade places every frame. A controller takes a slot in the table on
  entering the tree and gives it back on leaving.
- Mix: the dig at −4 (with the stop's bite), the landing at −11 (under the
  push, over the menu click).

