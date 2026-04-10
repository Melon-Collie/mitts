# Hockey Game

An arcade hockey game built in Godot 4.6.2 (Jolt Physics). Online multiplayer — each player runs their own client, with their own camera.

> **Early development.** Windows only. Expect rough edges.

---

## Download & Play

1. Go to the [latest release](../../releases/tag/latest) and download the zip
2. Extract and run the `.exe`

**Launch modes (run from a terminal):**

| Command | Mode |
|---------|------|
| `HockeyGame.exe` | Offline — single player, no network |
| `HockeyGame.exe --host` | Host — opens port 7777 UDP for online play |
| `HockeyGame.exe --connect <ip>` | Client — connects to the host's public IP |

The host needs UDP port **7777** forwarded on their router.

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

Pucks coming in fast deflect off your blade instead of sticking. Move your stick backward with the puck to absorb a pass and catch it; hold your stick still against a fast puck to deflect it. Opposing blades can poke-check the puck loose — stick battles are momentum-based. Skate hard into a puck carrier to body check them — a big enough hit knocks the puck loose.

---

## What's In

- Skating with momentum, friction, and backward skating
- Mouse-driven blade control with reach and arc limits
- Wrister and slapshot with charge-based power
- Quick shots and one-touch finishes
- Relative-velocity catch vs deflect — move blade with the puck to receive, into the puck to redirect
- Poke checking — opposing blades strip the puck loose, direction driven by blade velocities
- Body checking — weight-based momentum transfer; hard hits strip the puck from the carrier
- Physical deflection off blade contact normal with elevation tipping
- Elevated shots
- Online multiplayer with client-side prediction
- Regulation rink markings — center line, blue lines, goal lines, faceoff circles, goalie creases
- Accurate Art Ross hockey nets with Bézier curve frame and translucent ruled-surface netting
- Behavioral goalie AI (state machine, Buckley depth system, butterfly, RVH) — server-authoritative with client interpolation, tracking lag for beatable positioning
- Goal detection, score tracking, and faceoff sequences — goals pause play, players teleport to faceoff dots, puck goes live on pickup

---

## Planned

- Score/phase HUD
- Reactive goalie saves (glove, shoulder, stick poke)
- Characters with unique abilities
- More platforms
