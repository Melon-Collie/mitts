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
| Touches | small blade touchdowns | a lifted skate landing |

## Phases

1. **Pushes on the gait** (built). The coordinator emits
   `Skater.skate_pushed(left, strength)` on each push's onset; strength is
   `SkaterLocomotion.push_strength` (intensity × push scale × the stroking
   states' share). `SkaterSoundController` plays a take at that skate on a
   player of its own per foot, its level following strength.
2. **The stop and the skid** as a sustained scrape over the stop's weight and
   deceleration, with an onset bite.
3. **Glide and carve beds**, two loops whose levels follow speed and edge load.
4. **Polish**: touchdowns, the start's chop, the mix of the local skater's own
   skating against everyone else's, a voice budget for six skaters.

## Recordings

Every cue is a file mastered by `tools/normalize_sfx.py` and listed in
`SoundManager` (`_SOUND_PATHS`, `_TAKE_COUNTS` for several takes, `_MIX_DB`,
`_UNDER_REFERENCE_DB`), so swapping a recording in is replacing the files and,
if the take count or the mastering shortfall changes, those two numbers. The
placeholders are cut from the old stride recording.

| Cue | Placeholder | Wanted |
|---|---|---|
| `skate_push_01..06.wav` | the stride, re-pitched ±10% and tilted ±3 dB, 400 ms from 3 ms before the bite | 6–10 pushes, mono, ~300–500 ms, cut 3 ms before the bite |
| glide bed (phase 3) | — | a seamless 2–4 s loop of a coasting glide |
| carve (phase 3) | — | a seamless 2–4 s loop of a held edge |
| `skate_brake.wav` (the stop's bite) | the original | a short bite as the blades dig in, mono |
| `skate_scrape.wav` (the stop's sustain) | grains of `skate_brake.wav`'s steady scrape, overlap-added round a 2 s circle so the loop has no seam | a seamless 2–4 s loop of a held stop's spray, mono, loop on in its `.import` (`edit/loop_mode=2`) |

## Phase 1 as built

- Each push is heard once. A leg's push weight is exactly 0 while it is not
  pushing (`max(-s, 0)` per stroking state), so a push is under way from the
  first pass above 0.001, whatever the frame rate, and is heard on the first
  pass of it the stroke is past 0.05 strength. That is its onset, except at a
  start, whose first push begins at zero strength and is heard ~75 ms in once
  the stroke has some.
- A start's first pushes are quiet (strength ~0.06 against ~1 at cruise): the
  stroke's intensity eases up from zero, so the dig-in sounds as small as it
  is drawn. A start's crunch is phase 4's.
- Both gait paths publish the same channels (`push_l`, `push_r`,
  `push_strength` on the coordinator; `NativeSkaterGait.get_push`), and
  `test_native_gait_parity.gd` compares them.
- `test_gait_push_events.gd`: each leg pushes once per stride cycle, the legs
  alternate, and a coasting skater makes no push.
- Level: full at strength 1 (a flat-out stride), −14 dB at the floor; the cue
  sits at −6 in the mix, with the quieter body and stick sounds.
- The fixed-clock loop is gone, so a glide is silent until phase 3.

## Phase 2 as built

- The gait publishes the stop's and the skid's weights (`stop_weight`,
  `skid_weight` on the coordinator; `NativeSkaterGait.get_scrape`; held by
  `test_native_gait_parity.gd`), read through `SkaterController.skate_scrape`
  as `GoalieSoundController` reads `GoalieController.stance`.
- The scrape's amplitude is the share of the legs shedding speed — the stop
  whole, the skid at half — times speed against 8 m/s; under −30 dB it stops.
  The bite plays once as the stop's weight passes half at 1.5 m/s or more, and
  re-arms when the stop lets go.
- Measured (`test_skate_scrape_sound.gd`): a stop from speed bites once and
  scrapes up to −1.7 dB for ~0.9 s, silent once stopped; the skid scrapes to
  −7.5 dB without a bite; a stride does not scrape.
- The stop's sound follows the gait's stop rather than the brake button: it
  comes in with the legs turning across, and the shot block's plant (which sets
  `is_braking` for its spray) no longer plays the brake.

