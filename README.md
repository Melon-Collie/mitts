# Hockey Game

An arcade hockey game built in Godot 4. Online multiplayer — each player runs their own client, with their own camera.

> **Early development.** Windows only. Expect rough edges.

---

## Download & Play

1. Go to the [latest release](../../releases/tag/latest) and download the zip
2. Extract and run the `.exe`
3. To host a game, launch with `--host` as a command line argument (right-click the exe → create shortcut → add `--host` to the target, or run from a terminal: `HockeyGame.exe --host`)
4. Other players launch normally — they'll connect to the host

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

Pucks coming in fast deflect off your blade instead of sticking — you can one-touch redirect incoming passes.

---

## What's In

- Skating with momentum, friction, and backward skating
- Mouse-driven blade control with reach and arc limits
- Wrister and slapshot with charge-based power
- Quick shots and one-touch finishes
- Automatic pickup and blade deflection
- Elevated shots
- Online multiplayer with client-side prediction
- Behavioral goalie AI (state machine, Buckley depth system, butterfly, RVH) — server-authoritative with client interpolation

---

## Planned

- Characters with unique abilities
- Proper game flow (goals, faceoffs, score)
- More platforms
