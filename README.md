# Mitts

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
- Puck carry speed penalty — carrier max speed reduced to 85%, encouraging passing
- Passive shot blocking — puck deflects off skater bodies with dampened momentum
- Active shot-block stance (Ctrl) — drops to a crouch, widens block area, snaps to face puck, slows movement
- Shot cancel (Ctrl during wind-up) — abort a wrister or slapshot wind-up at any point without firing
- Physical deflection off blade contact normal with elevation tipping
- Elevated shots
- Online multiplayer with client-side prediction and lag compensation
- Regulation rink markings — center line, blue lines, goal lines, faceoff circles, goalie creases
- Art Ross hockey nets with translucent ruled-surface netting
- Behavioral goalie AI (butterfly, RVH) — tracking lag makes positioning beatable
- Goal detection, score tracking, and faceoff sequences
- Period-based game loop — 3 periods × 4 minutes; clock pauses during dead-puck phases
- NHL-style scorebug — teams + scores | shots on goal | period + clock; phase banner (GOAL! / FACEOFF / etc.)
- Per-player stat tracking — goals, assists, points, shots on goal, hits; Tab-toggle scoreboard; auto-opens on game over
- Main menu — host, join (with IP input), and offline
- Update-available notice — main menu compares the baked-in build version against the latest GitHub Release
- Team colors — Penguins gold + black (home) vs Leafs blue + white (away)
- Local player ring — gray semi-transparent ring on the ice under your skater only
- Stadium lighting and anti-aliased ice markings
- Puck trail, ice spray, skate trails, speed lines, body check impact burst, shot charge glow, goal celebration
- Game menu (ESC) — Resume, Change Position, Rematch, Return to Lobby, Disconnect
- Pre-game lobby — slot picking, configurable rules (periods, duration, OT); "Return to Lobby" brings the session back here with team assignments preserved
- Offsides ghost — skaters past the blue line without the puck become transparent and can't interact until they retreat or the puck enters the zone
- Hybrid icing — shooting from your own half past the opponent's goal line ghosts your team for 3 seconds unless beaten back

---

## Planned

- Reactive goalie saves (glove, shoulder, stick poke)
- More platforms

## Later

- Characters with unique abilities (deferred until game feel is right)
