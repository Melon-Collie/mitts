# Architecture

Technical decisions and reference tables for Mitts. Layer model, code conventions, and development workflow are in `CLAUDE.md`.

---

## Design Philosophy

Depth over breadth — few inputs with rich emergent behavior rather than many explicit mechanics.

The Rocket League freeplay ceiling is a guiding star: the stickhandling-to-shot pipeline should reward practice and feel satisfying to master.

**Key inspirations:** Omega Strikers / Rocket League (structure), Breakpoint (twin-stick melee blade feel), Mario Superstar Baseball (stylized characters, exaggerated tuning, pre-match draft). Slapshot: Rebound is a cautionary reference — pure physics shooting feels unintuitive; the blade proximity pickup system is explicitly designed to solve that accessibility gap.

---

## Reference

### Network Rates

| Channel | Rate | Transport |
|---------|------|-----------|
| Input (client → host) | 60 Hz | Unreliable, last 12 frames per packet |
| World state (host → clients) | 40 Hz | Unreliable, ~192 bytes quantized |
| Events (pickup, spawn, goal, goalie transitions) | On event | Reliable |
| Stats sync | On change | Reliable |

Interpolation delay: 75ms baseline, adapts per-packet via `lerp(0.15)`, capped at +5ms / −1ms per packet.

Wire format: Skater 35B · Puck 13B · Goalie 8B. ~62% reduction vs unquantized.

### Collision Layers

| Constant | Value | Purpose |
|----------|-------|---------|
| `LAYER_WALLS` | 1 | Boards, ice surface, goalie body parts |
| `LAYER_BLADE_AREAS` | 2 | Skater blade `Area3D`s |
| `LAYER_PUCK` | 8 | Puck `RigidBody3D` |
| `LAYER_SKATER_BODIES` | 16 | Skater `CharacterBody3D` bodies |

Composed masks: `MASK_PUCK = 1` (walls + goalie only, not skater bodies), `MASK_SKATER = 17` (walls + other skater bodies).

The puck's pickup zone `Area3D` sits on `LAYER_WALLS | LAYER_BLADE_AREAS` (3) with `collision_mask = LAYER_BLADE_AREAS` (2) so it detects blade `Area3D`s via `area_entered`.

### Game Phases

| Phase | Duration | Movement |
|-------|----------|----------|
| `PLAYING` | Until goal or clock expires | Full |
| `GOAL_SCORED` | 2s | Locked |
| `FACEOFF_PREP` | 0.5s | Locked |
| `FACEOFF` | Until pickup or 10s timeout | Full |
| `END_OF_PERIOD` | 3s | Locked |
| `GAME_OVER` | Indefinite | Locked |

Period clock ticks only during `PLAYING`. On expiry: if periods remain → `END_OF_PERIOD` → `FACEOFF_PREP` (period increments, clock resets); if last period → `GAME_OVER`.

---

## Decisions

**Authoritative host, no dedicated server.** One player hosts; the host runs all physics. Eliminates server costs and NAT complexity at the expense of host-advantage. Acceptable for a small-scale arcade game.

**No pickup prediction.** Two players can contest the same puck — the server arbitrates who wins. Predicting pickup locally and rolling it back on a contested play feels worse than the single round-trip delay. Pickup is detected server-side via lag-compensated rewind; only the grant confirmation travels to the client.

**Ghost mode over stoppages for offsides and icing.** Stoppages interrupt flow; ghost mode keeps the puck live and lets offending players correct their position. Downside: slightly less legible than a whistle. Acceptable for an arcade game that prioritizes momentum.

**`_carrier_peer_id` managed by reliable RPCs, never world state.** Unreliable packets can arrive out of order relative to pickup/release RPCs, causing the puck to flicker between carried and loose. Reliable RPCs guarantee ordering; world state is ignored for carrier identity.

**Immediate reconcile snap, no gradual position correction.** Gradual blending toward the server state introduces a window where the client is in a known-wrong position. Immediate snap + input replay is always convergent within one reconcile cycle. A visual-only offset blend can be layered on top without affecting physics correctness — tracked as a future improvement (see `docs/specs/NETCODE_AUDIT_2026.md` #3).

**Trajectory prediction exits on physics contact, not only carrier RPCs.** When the predicted puck hits a post or the goalie, host and client diverge immediately — the host's Jolt sees the collision but the client doesn't know to stop predicting. Ending prediction on local post/goalie contact lets the client fall back to interpolation before the divergence compounds.

**Goalie state transitions and shot reactions via reliable RPCs.** Interpolation gives smooth position but can't guarantee reaction timing — a butterfly during a rapid shot sequence may arrive in the wrong bracket order. Reliable RPCs deliver exact state changes; clients play a local reaction timer from the RPC payload for immediate visual feedback.

---

## Build Status

| Stage | Description | Status |
|-------|-------------|--------|
| 1 | Skating feel | Done |
| 2 | Stick / puck interaction | Done |
| 3 | Basic goalie | Done |
| 4 | Networking (prediction, interpolation, reconciliation) | Done |
| 5 | Goalie AI rework + networking | Done |
| 6 | Full game flow (goals, faceoffs, score) | Done |
| 7 | Testable domain layer (rules extraction, state machine, GUT tests, CI) | Done |
| 8 | Period-based game loop (clock, period transitions, game over) | Done |
| 9 | Visual polish (puck trail, ice spray, skate trails, goal burst, wall impact, body check, shot charge glow, speed lines) | Done |
| 10 | Playtester distribution (auto-versioned GitHub Releases + in-game update notifier) | Done |
| 11 | In-game team/position swap | Done |
| 12 | Pre-game lobby (slot picking + rule config) + in-game "Return to Lobby" | Done |
| 13 | Characters + abilities | Deferred — revisit when game feel is right |
| 14 | Networking refactor Phase 1 (bug fixes + reconcile smoothing) | Done |
| 15 | Networking refactor Phase 2 (telemetry pull model, puck buffer fix) | Done |
| 16 | Networking refactor Phase 3 (NetworkSim autoload, presets 0–5) | Done |
| 17 | Networking refactor Phase 4 (NTP-style clock sync, input host_timestamp) | Done |
| 18 | Networking refactor Phase 5 (StateBufferManager ring buffers, goalie keyed by team_id) | Done |
| 19 | Networking refactor Phase 6 (swept sphere interaction detection, puck pickup/poke/deflect to domain layer) | Done |
| 20 | Networking refactor Phase 7 (input redundancy, lag-compensated pickup/shot/hit, state-machine save/restore in reconcile, remove gradual correction) | Done |
| 21 | Netcode fixes (segment-segment detection, blade_contact_world lag-comp, reconcile mouse-seed + server shot authority, quantized world state, body check impulse replay) | Done |
| 22 | Netcode audit (40 Hz world state, 75ms interpolation, board collision in replay, goalie reliable RPCs, trajectory prediction exits on contact, pickup timestamp fix, adaptive delay, Hermite puck interpolation, goalie quantization 10→8B) | Done |
| 23 | Goalie reactive saves (glove, body, stick poke) | Planned |

---

## Open Questions

- Slapshot pre/post release buffer window for one-timer timing feel
- Middle-zone puck reception: blade readiness check
- Aim assist
- Procedural skating animations
- CharacterStats resource design (universal vs per-character exports)
- Camera goal anchor flip speed on turnovers
- Rink size tuning (possible 2/3 scale)
- Reconcile position blend (NETCODE_AUDIT_2026.md #3) — visual smoothing without physics compromise
- Session-relative timestamps for long-session f32 precision (netcode-improvements-plan.md #4)
