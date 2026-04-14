# Hockey Game

An arcade hockey game built in Godot 4.6.2 (Jolt Physics). Online multiplayer — each player runs their own client, with their own camera.

> **Early development.** Windows only. Expect rough edges.

---

## Download & Play

1. Go to the [latest release](../../releases/tag/latest) and download the zip
2. Extract and run the `.exe`
3. Pick **Play Offline**, **Host Game**, or **Join** from the main menu

For online play the host needs UDP port **7777** forwarded on their router.

---

## Controls

| Input | Action |
|-------|--------|
| **WASD** | Skate |
| **Mouse** | Blade position |
| **Left click (tap)** | Quick shot / pass |
| **Left click (hold + sweep)** | Wrister — sweep blade to charge, release to shoot |
| **Right click (hold)** | Slapshot — charge up, release to shoot |
| **Shift (hold)** | Backward skating — facing locks to mouse |
| **Space** | Brake |
| **Scroll up / down** | Toggle elevated shot |

---

## How It Plays

Your blade follows your mouse at all times. Move it toward the puck to pick it up — the puck attaches automatically when your blade gets close enough. Once you have it, shoot or pass by sweeping your mouse and releasing.

Facing follows your movement naturally, like a real skater. Hold **Shift** to lock your facing to the mouse and skate backward while keeping your eyes on the play.

Pucks coming in fast deflect off your blade instead of sticking. Move your stick backward with the puck to absorb a pass and catch it; hold your stick still against a fast puck to deflect it. Opposing blades can poke-check the puck loose — stick battles are momentum-based. Skate hard into a puck carrier to body check them — a big enough hit knocks the puck loose. Get in the way of a shot and it deflects off your body. Opponents can't poke their stick through you — position your body to shield the puck.

---

## What's In

- Skating with momentum, friction, and backward skating
- Mouse-driven blade control with reach and arc limits
- Wrister and slapshot with charge-based power
- Quick shots and one-touch finishes
- Relative-velocity catch vs deflect — move blade with the puck to receive, into the puck to redirect
- Poke checking — opposing blades strip the puck loose, direction driven by blade velocities
- Body checking — weight-based momentum transfer; hard hits strip the puck from the carrier
- Puck carry speed penalty — carrier max speed reduced to 88%, encouraging passing
- Passive shot blocking — puck deflects off skater bodies with dampened momentum
- Stick clamping against player bodies and goalie pads — no poking through opponents
- Physical deflection off blade contact normal with elevation tipping
- Elevated shots
- Online multiplayer with client-side prediction
- Regulation rink markings — center line, blue lines, goal lines, faceoff circles, goalie creases
- Accurate Art Ross hockey nets with Bézier curve frame and translucent ruled-surface netting
- Behavioral goalie AI (state machine, Buckley depth system, butterfly, RVH) — server-authoritative with client interpolation, tracking lag for beatable positioning
- Goal detection, score tracking, and faceoff sequences — goals pause play, players teleport to faceoff dots, puck goes live on pickup
- Scorebug HUD — score and phase label (GOAL! / FACEOFF) in top-left corner
- Elevation indicator — bottom-center HUD badge when elevated shot mode is active
- Main menu — host, join (with IP input), and offline from the title screen
- Player colors — team-hued skater colors; reds for team 0, blues for team 1, each player a distinct shade
- Host reset button — top-right HUD button (host only) that zeroes the score and restarts from faceoff
- Offsides ghost — skaters past the blue line without the puck become transparent ghosts that can't interact with the puck or other players until they retreat or the puck enters the zone
- Icing ghost — shooting from your own half past the opponent's goal line ghosts your entire team for 3 seconds or until the other team picks up the puck

---

## Planned

- Reactive goalie saves (glove, shoulder, stick poke)
- Characters with unique abilities
- More platforms

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

### Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full layer model. Summary: pure-GDScript domain layer (`Scripts/domain/`) holds rules and the state machine, the application layer (`GameManager`, controllers, `ActorSpawner`) orchestrates, infrastructure (actors, networking, UI) handles engine integration. Controllers receive their collaborators via `setup()` injection; upward communication is by signals.
