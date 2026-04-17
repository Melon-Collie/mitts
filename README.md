# Hockey Game

An arcade hockey game built in Godot 4.6.2 (Jolt Physics). Online multiplayer — each player runs their own client, with their own camera.

> **Early development.** Expect rough edges.

---

## Download & Play

1. Go to the [latest release](../../releases/tag/latest) and download the zip for your platform
   - **Windows:** `Windows Desktop.zip` → extract and run `hockey.exe`
   - **Linux:** `LinuxX11.zip` → extract, `chmod +x hockey.x86_64`, then run it
2. Pick **Play Offline**, **Host Game**, or **Join** from the main menu

For online play the host needs UDP port **7777** forwarded on their router.

The main menu shows an **"Update available"** notice when your build is behind the latest release. It doesn't patch automatically — grab the new zip from the release page when you see it.

---

## Controls

| Input | Action |
|-------|--------|
| **WASD** | Skate |
| **Mouse** | Blade position |
| **Left click (tap)** | Quick shot / pass |
| **Left click (hold + sweep)** | Wrister — sweep blade to charge, release to shoot |
| **Right click (hold)** | Slapshot — charge up, release to shoot |
| **Shift (hold)** | Freeze facing — body angle locks in place; skate freely while keeping your blade position |
| **Space** | Brake (no direction) / Pulse dash (hold direction) |
| **Ctrl (hold, no puck)** | Shot-block stance — crouch, widen block area, slow movement, face puck |
| **Ctrl (during wind-up)** | Cancel shot — abort a wrister or slapshot wind-up without firing |
| **Scroll up / down** | Toggle elevated shot |
| **Tab** | Toggle scoreboard |

---

## How It Plays

Your blade follows your mouse at all times. Move it toward the puck to pick it up — the puck attaches automatically when your blade gets close enough. Once you have it, shoot or pass by sweeping your mouse and releasing.

Facing follows your movement naturally, like a real skater. Hold **Shift** to freeze your body angle in place — skate in any direction while keeping your blade exactly where it is, useful for backward skating or precise stickhandling.

Pucks coming in fast deflect off your blade instead of sticking. Move your stick backward with the puck to absorb a pass and catch it; hold your stick still against a fast puck to deflect it. Opposing blades can poke-check the puck loose — stick battles are momentum-based. Skate hard into a puck carrier to body check them — a big enough hit knocks the puck loose. Get in the way of a shot and it deflects off your body. Opponents can't poke their stick through you — position your body to shield the puck.

---

## What's In

- Skating with momentum, friction, and backward skating
- Mouse-driven blade control with a custom top-hand IK solver — fixed stick length, asymmetric range-of-motion (tight on forehand, extended backhand for one-handed reaches)
- Reactive bottom-hand IK — second hand grips the shaft naturally and releases to a one-handed pose only when the blade swings past the upper body's rotation limit
- Wrister and slapshot with charge-based power
- Quick shots and one-touch finishes
- Relative-velocity catch vs deflect — move blade with the puck to receive, into the puck to redirect
- Poke checking — opposing blades strip the puck loose, direction driven by blade velocities
- Body checking — weight-based momentum transfer; hard hits strip the puck from the carrier
- Puck carry speed penalty — carrier max speed reduced to 88%, encouraging passing
- Passive shot blocking — puck deflects off skater bodies with dampened momentum
- Active shot-block stance (Ctrl) — drops to a crouch, widens block area, snaps to face puck, slows movement; puck carries more energy away than passive
- Shot cancel (Ctrl during wind-up) — abort a wrister or slapshot wind-up at any point without firing; puck stays with the carrier
- Stick clamping against player bodies and goalie pads — no poking through opponents
- Physical deflection off blade contact normal with elevation tipping
- Elevated shots
- Online multiplayer with client-side prediction
- Regulation rink markings — center line, blue lines, goal lines, faceoff circles, goalie creases
- Accurate Art Ross hockey nets with Bézier curve frame and translucent ruled-surface netting
- Behavioral goalie AI (state machine, Buckley depth system, butterfly, RVH) — server-authoritative with client interpolation, tracking lag for beatable positioning
- Goal detection, score tracking, and faceoff sequences — goals pause play, players teleport to faceoff dots, puck goes live on pickup
- Period-based game loop — 3 periods × 4 minutes; clock pauses during dead-puck phases; each period opens with a faceoff; game locks after the final period until reset
- NHL-style scorebug — teams + scores (away top, home bottom) | shots on goal | period + clock, in a three-column dark panel (top-left); phase banner (GOAL! / FACEOFF / etc.) appears centered below it
- Per-player stat tracking — goals, assists, points, shots on goal, hits; Tab-toggle scoreboard overlay with rows colored by team; auto-opens on game over; synced host → clients via reliable RPC
- Elevation indicator — bottom-center HUD badge when elevated shot mode is active
- Main menu — host, join (with IP input), and offline from the title screen
- Update-available notice — main menu compares the baked-in build version (auto-generated from commit count at export time) against the latest GitHub Release and prompts the player to re-download when they're stale
- Team colors — Penguins gold + black (home) vs Leafs blue + white (away); all teammates match
- Local player ring — gray semi-transparent ring on the ice under your skater only
- Stadium lighting — 6 overhead SpotLights in a 2×3 grid; warm white, soft falloff, shadows on center pair
- Anti-aliased ice markings — procedural rink texture at 40px/m with sub-pixel smooth circles and lines; mipmapped for clean rendering at all zoom levels
- MSAA 4x — hardware anti-aliasing for smooth geometry edges
- Host reset button — top-right HUD button (host only) that zeroes the score and restarts from faceoff
- Offsides ghost — skaters past the blue line without the puck become transparent ghosts that can't interact with the puck or other players until they retreat or the puck enters the zone
- Hybrid icing — shooting from your own half past the opponent's goal line triggers a race: if the defending team's closest player is nearer the goal line, your entire team is ghosted for 3 seconds; if you beat them back to the puck, icing is waved off
- Puck trail — pale-blue ribbon streak behind the puck when moving fast
- Puck wall impact — small ice burst when the puck sharply reverses direction off the boards
- Ice spray — burst of ice particles from both skates on hard braking or sharp direction changes
- Skate trails — faint flat marks left on the ice surface while skating, fading over 2.5s
- Speed lines — faint particle streaks behind skaters at high speed
- Body check impact — particle burst at the victim's position on a hard hit
- Shot charge glow — blue OmniLight at the blade that brightens as wrister or slapshot charges
- Goal celebration — gold particle burst and flash of light inside the net on every goal

---

## Planned

- Reactive goalie saves (glove, shoulder, stick poke)
- More platforms

## Later

- Characters with unique abilities (deferred until game feel is right)

---

## Development

### Running Tests

The project uses [GUT (Godot Unit Test)](https://github.com/bitwes/Gut) v9.6.0, committed under `addons/gut/`. Tests live in `tests/unit/` and cover the domain layer (rule classes + state machine).

**In the editor:** open the **GUT** panel at the bottom of the screen and click **Run All**.

**From the command line:**

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

Exit code is 0 on pass, non-zero on fail — suitable for CI.

### CI

Every push and PR triggers `.github/workflows/test.yml`, which caches Godot 4.6.2, imports the project, and runs the GUT suite. `deploy.yml` gates the export job on tests passing, so a broken test blocks releases to main.

### Releases

`deploy.yml` computes `VERSION=0.1.<git commit count>` on each run, rewrites the placeholder `"dev"` in `Scripts/game/build_info.gd` to that string before export, and publishes to the `latest` GitHub Release with the version as the release name. The download URL stays stable (`releases/tag/latest`) so the README link never rots. Exported clients compare their baked-in version against the release name to decide whether to show the update notice.

### Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full layer model. Summary: pure-GDScript domain layer (`Scripts/domain/`) holds rules and the state machine, the application layer (`GameManager`, controllers, `ActorSpawner`) orchestrates, infrastructure (actors, networking, UI) handles engine integration. Controllers receive their collaborators via `setup()` injection; upward communication is by signals.
