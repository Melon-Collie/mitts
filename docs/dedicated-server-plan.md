# Dedicated servers — design plan

Status: **design agreed in chat, 2026-11-13. Phase 1a is built (§8); the rest
is not.** The rows under *Proposed, not confirmed* were put forward in that chat
and not answered; settle them before the phase that needs them.

Mitts is server-authoritative already: one machine simulates, every other
machine predicts, reconciles and sends lag-compensated claims. Today that
machine is a player's. This plan adds servers the developer runs, so that a
match can be played with nobody at zero ping and nobody able to end it by
leaving, and so that a tester playing alone against bots produces netcode data.
Player hosting stays.

**Hosted** in this document means simulated on a Mitts server. **Player-hosted**
means simulated on a player's machine, as every online match is today.

## Decisions already made

| Question | Answer |
|---|---|
| Who runs the servers | **The developer.** No community server binary. |
| Player hosting | **Stays, first class.** It is a choice, not only a fallback. Free play, the tutorial and drills run on the in-process host regardless. |
| The party | **The base social unit.** Members, each with a position, skating together in free play on the leader's machine. The leader queues it into standard games. It has no rules, bots or team split to set. |
| The custom lobby | **A mode the party enters.** Today's lobby screen: seats across both sides, rules, bots. Leaving returns to the party. Two groups of friends who want to play each other merge into one party and pick sides. |
| Standard games | **Fixed rules, the party on one side.** Two queues: **vs AI**, whose one setting is bot difficulty, and **vs humans**, which has none. |
| Team size | **3v3 and 5v5 from day one**, in both queues. |
| Where a custom match runs | **The leader chooses**: a Mitts server or their own machine. |
| No server free | **Fall back to player-hosted.** |
| Where a vs-AI match runs | **Hosted, while the game is in testing.** The test pool is under ten people and a hosted solo game is a full client session. Where each kind of match runs is a setting the backend holds, so it can move to the leader's machine later without a client update. |
| A server's life | **One process a match.** It boots from a match config, plays the match, posts its results and exits. It never runs a lobby. |
| What is built first | **Hosted vs AI for one tester**, before parties and before the vs-humans queue. |

### Proposed, not confirmed

| Question | Proposal |
|---|---|
| Standard rules | Today's lobby defaults (`ARCADE`, three periods). |
| vs humans when no server is free | The queue waits; it does not fall back. A fallback puts one party's leader at zero ping against strangers. |
| Bots in a vs-humans match | At least one human party a side; empty seats filled evenly by bots at one fixed difficulty. Ten humans at once is rare in a closed beta. How long the queue holds out for humans before filling is unset. |
| Mode choice in a queue | One ticket says 3v3, 5v5 or either, so two modes do not halve a small pool. |
| Seats in a queued 5v5 | In 5v5 the seat is the position. Party members hold distinct positions; the matchmaker seats strangers by the preferred position the join handshake carries, and teammates trade with the existing mid-match slot swap. |
| A friend joining a hosted custom match late | The leader's client vouches for them to the server. |
| Transport to a server | ENet, direct (§3). |

## 1. What "host" means today

`is_host` is read about 200 times in 22 files and carries three meanings. Only
the first is true of a server.

1. **This machine simulates.** Nearly every read in `game_manager.gd` (82) and
   `network_manager.gd` (63) is this gate and nothing more. A server sets
   `is_host = true` and they are all correct as written.
2. **This machine's player is peer 1.** About a dozen sites:
   `GameManager.on_host_started` spawns a local skater for peer 1,
   `NetworkManager.start_offline` and `apply_local_identity` seed peer 1's
   identity from `PlayerPrefs`, the two loops in
   `_push_lobby_assignments_to_clients` skip peer 1, and `LobbyManager` leaves
   peer 1 out of the ready check.
3. **This player runs the lobby.** All of it is in UI scripts (`LobbyManager`
   25 reads, the pause menu, the settings and slot panels, the rematch votes).
   A server runs no UI, and a client of a server already has `is_host` false, so
   its host-only controls are hidden with no change.

So the work is the second meaning, plus whatever the host does for its own
screen that the match depends on (§7).

`on_host_started` already has the shape a server needs: when peer 1's seat is a
spectator it spawns the world, the other players and the bots, and gives the
host no skater. A server is that branch without the camera.

## 2. The server

**It boots from a match config, not a lobby.** `on_host_started` reads the
roster and rules from `NetworkManager.pending_lobby_slots`,
`pending_bot_slots`, `pending_bot_identities` and `pending_game_config`, which
the lobby screen fills today. A server fills them from the config it was started
with. `LobbyManager` holds the lobby's authority inside a UI script, and none of
that has to move.

**The config names players by SteamID**, since nobody is connected when it is
written: which SteamID sits in which seat, which seats are bots, the rules, the
bot and goalie difficulty, the game id. The host's reconnect reservations
already hold a seat by SteamID and restore a joiner into it
(`GameManager._restore_reserved_player`). Seating from the config is expected to
be that path with the reservations made before anyone has joined; it has not
been tried.

**What the host reads from its own player's preferences** has to come from the
config or a server default instead: `bot_difficulty` and `goalie_difficulty`
(config), `share_gameplay_stats` and `replay_recording_enabled` (server
defaults).

**It reports its own telemetry.** `NetworkSessionReporter` posts one row a peer,
keyed on that peer's `steam_id`, as `host` or `client`, and the `match_health`
view joins them because netcode failures are asymmetric. A server has no Steam
identity. It posts a `server` row: the per-peer input starvation, backlog
drains and overdue pops only the simulating machine measures, and its own tick
health. Without it a hosted match has half its record.

**It can post the match's stats itself**, with a key that never ships in a
client. That is what would make career rows trustworthy; it is not needed for
Phase 1.

## 3. Transport and identity

Online play is Steam P2P: a joiner joins a Steam lobby and connects to its
owner's SteamID (`NetworkManager._on_steam_lobby_joined`). A server box runs no
Steam client.

- **ENet, direct to the server's address** (proposed). The relay exists to get
  through home NAT, and a server has a public address. `SteamMultiplayerPeer`
  is a drop-in `MultiplayerPeer`, so the RPC layer does not care which it is
  given.
- **GodotSteam Server and Steam sockets.** Keeps the relay and hides the
  server's address. It is a separate build from the client's GodotSteam, and a
  Godot forum thread reports `create_host` failing silently with it on 4.6, with
  no resolution. It needs a spike before it is chosen.

`request_join` takes the joiner's SteamID as an argument the client sends. Among
friends that is fine. On a public server, where a career row and a seat key on
it, the server must check a Steam auth ticket instead. A closed beta of known
testers can run without it.

**Hosted data measures a different link.** Prediction, reconcile and lag-comp
telemetry carries over to any transport. Link quality does not: a direct path to
a datacenter never shows the Steam relay clumping the interpolation delay was
sized against (`Scripts/networking/CLAUDE.md`). Player-hosted sessions stay the
source for that.

## 4. The client side

**The Steam lobby stops meaning a game session.** Today
`NetworkManager.attach_online` makes the lobby and the host peer together, and
joining the lobby means connecting to its owner. A party is a Steam lobby that
lasts across matches while the connection under it changes: to the leader's
machine for free play, to a server for a match, back again. If the leader
leaves, Steam passes the lobby to another member and free play restarts there.

**The custom lobby is a match-config builder.** At Start it either starts the
match as it does today or sends its config to the allocator and hands everyone
to the server that comes back. A hosted custom match also needs a leader the
server will take a kick, an end-match and the rematch decision from, named by
SteamID in the config.

## 5. Running them

Sized for a closed beta, and deliberately small.

**The server is a container image**: the headless Linux export, the game pack
and the native kernels. It is built in CI beside the release it matches, since
a server and a client of different builds refuse each other at the join
handshake. A match is one container, started for it and gone when it exits.

**Edgegap first.** One API call starts a container near the players and returns
an address and a UDP port; it is billed by the vCPU-minute and costs nothing
idle, which for a pool under ten is less than any box left running. Its free
trial (one deployment at a time, about 1.5 vCPU, an uptime cap of an hour or
more) covers Phase 1. Puck, a physics hockey game from a studio of this size,
runs its official servers this way beside player hosting. Edgegap's API token
cannot ship in a client, so a Supabase function holds it: the client asks the
function for a match, and the function asks Edgegap.

**A rented box is the fallback**, in central North America (Dallas): the input
lead covers a one-way trip of up to 100 ms (`MAX_ONE_WAY_S`), and from the
middle of the continent both coasts sit well inside it. It is the move if
Edgegap's shared hardware puts noise in the tick, if a month's play passes
what a box costs (about 350 vCPU-hours against a $24 box), or if Edgegap goes
the way Hathora did in May 2026. The same image runs there, with a small
allocator in place of Edgegap's API. Player hosting stays under both, so a host
that is full or gone degrades a match to player-hosted and never to nothing.

**The matchmaker is on Supabase** when the vs-humans queue is built: a queue
table and a function that pairs parties and asks for a server.

**What one match needs** (a 5v5 of ten bots, the worst case, measured in §8):
about 0.9 of a core for the main thread at a tick a frame, 0.65 once a server
skips the mesh nobody sees, plus about 0.2 for the bots' worker thread; about
600 MB of memory; and 16 KB/s of upload a human client
(`docs/performance-findings.md`), so 1.3 Mbps for ten humans. The tick is one
thread, so a core taken by a neighbour is dilated physics for every client in
the match.

## 6. Phases

Each phase is playable on its own and the next is built on it.

1. **Hosted vs AI for one tester.** Each step is one pull request, and the game
   plays as it does today after every one of them.
   a. A server launch mode: the host path with no local player, no seat and no
      camera (§7 is the list). Held by the probe. **Built, §8.**
   b. Boot from a match config, seat joiners by SteamID, post the results and
      exit; exit early when the last human has left.
   c. ENet: the server listens on a UDP port and a client connects to an
      address. Proved with both on one machine, which needs no hosting.
   d. The server's telemetry row.
   e. The container image, built and pushed by CI.
   f. The Supabase function that asks Edgegap for a match, and the button in
      the client that asks the function and falls back to player-hosted.
2. **Identity.** Steam auth tickets; the server posts career rows.
3. **Parties.** The lasting Steam lobby, group free play, the connection swap.
4. **The vs-humans queue.** The matchmaker, queue tickets, seating.
5. **Hosted custom matches.** The lobby's hand-off, the leader role, late
   joiners.

`ARCHITECTURE.md` → Decisions records "Authoritative host, no dedicated server".
It is rewritten when Phase 1 lands.

## 7. The host with nobody on it — as measured

`.claude/hooks/probe-headless-host.sh` opens an offline lobby, seats the host as
a spectator, fills every skater seat with a bot and plays the match headless to
`GAME_OVER` (`tools/headless_host_probe_runner.gd`). Taken 2026-11-13 on a
4-core cloud container, editor (debug) binary, **native kernels not built**, so
every hot kernel ran on its GDScript original:

| match | outcome | tick rate in live play | cores used |
|---|---|---|---|
| 3v3, one 10 s period and overtime | game over, 1–0 | 90.0 Hz | not taken |
| 5v5, three 40 s periods and overtime, frame rate uncapped | game over, 0–1 | 83–89 Hz | 1.18 |
| 5v5, three 25 s periods, capped at 30 fps | game over, 0–1 | 87.9–89.2 Hz | 1.05 |

The uncapped 5v5 shared the machine with an analyzer scan for part of its run,
so its tick rates are not clean; the capped run had the machine to itself.

**The match flow needs no skater on the host.** The pre-game intro, faceoffs,
periods and their breaks, a goal's celebration and replay, overtime and the
final horn all ran, with no script error in any run. The bots' worker thread ran
headless too.

**Ten bots on GDScript kernels fill a core.** The capped run reached 24 of its
30 frames a second, and live play slipped 1 to 2 % under the tick rate, which
every client would feel as dilated physics. With the kernels built,
`docs/performance-findings.md` has the ten-skater tick at 4.9 ms on the same
kind of machine, under half a core at 90 Hz. So a server build carries the
native kernels, and a box is sized from a release build with them, not from this
table. All ten skaters as bots is the worst case a match can ask for.

What a server still has to change. These come from reading the host path; the
probe passes over all of them, because its host keeps a viewport and a seat:

1. **Two phases end when a cinematic does.** `GOAL_SCORED` ends on
   `GoalReplayDriver.replay_stopped` and a period break on the intermission
   reel stopping (`PhaseCoordinator._on_goal_replay_stopped`,
   `GameManager._on_intermission_reel_stopped`). Both drivers ran headless,
   cameras and all. A server either keeps them or times those phases itself.
2. **A skip vote counts the host as a voter.** `_total_skip_voters()` is
   `1 + connected peers`, so on a server no replay or break could be skipped.
3. **The probe's host holds a spectator seat** (`_spectator_peers[1]`), one of
   `MAX_SPECTATORS`. A server holds none.
4. **The host builds its camera, its HUD and the arena.** A server needs none
   of it. What it costs was not measured.
5. **The host's own preferences set the bots** (§2).

## 8. Phase 1a as built

`NetworkManager.start_server()` is a host that seats nobody
(`is_dedicated_server`). It opens no lobby: the caller fills
`pending_game_config` and the bot slots and loads `Hockey.tscn`, which is what
the probe's `--server` does and what Phase 1b's boot will do from a config.

Of §7's five, what it took:

1. **The cinematics stay.** The goal replay and the intermission reel run on a
   server as they do on a host, so those phases end on the same clock a
   client's own cinematic runs on. They mount their cameras with none to hand
   back to, which found a stale read in `GoalReplayDriver` (its cameras followed
   the puck through a field `stop()` had just cleared). Fixed there.
2. **A server casts no skip vote.**
3. **A server holds no seat**, player or spectator.
4. **Measured, and left alone.** The scene still builds its HUD and the arena.
   Freeing them before the match plays (`--free=`) moved nothing: see below.
5. **Not done.** Bot and goalie difficulty still come from the machine's
   preferences; Phase 1b's config carries them.

Probed 2026-11-22 as a server, same machine and caveats as §7: a 5v5 of three
30 s periods and a 3v3 that went to overtime and scored both reached
`GAME_OVER` with no script error, no camera at the opening faceoff and no
local skater. The 5v5 held 88.7 to 90.0 Hz in live play.

### What the HUD and the arena cost a server

The same 5v5 server match (one 40 s period, capped at 30 fps), with nodes freed
before it played, two runs each, 2026-11-22, same machine and caveats as §7:

| freed | process step, ms a frame | tick, ms | peak memory |
|---|---|---|---|
| nothing | 18.00 | 4.98 | 595 MB |
| `Hud` | 17.51 | 4.87 | 590 MB |
| `RinkArena/ArenaStands`, `Jumbotron` | 18.26 | 4.88 | 597 MB |
| all three and `CrowdAudio` | 17.43 | 4.89 | 591 MB |

Runs of one configuration differ by up to 0.4 ms, so the arena costs nothing
that shows and the HUD at most half a millisecond a frame. Memory does not move,
though freeing a node after the scene has loaded cannot show what never loading
it would save. Neither is worth a server-only scene.

**What the table does show is where a server's frame goes: the skaters' own
per-frame step.** 18 ms a frame for ten bots on the GDScript kernels;
`docs/performance-findings.md` has it at 3.6 ms with the native ones. That is
the cosmetic rig (gait, IK, skin) of bodies nobody is looking at.

**And a server cannot buy it back with a low frame rate.** Godot runs every tick
a frame owes back to back and sends at the frame's end, so at 30 fps three ticks
and their snapshots leave in one clump, which a client's interpolation delay
then has to cover. A server runs about a tick a frame (a cap at the tick rate),
where the process step is paid 90 times a second.

### How much of that step is separable

Most of it already is, by design (`Scripts/actors/CLAUDE.md`, *Cosmetic vs.
gameplay*). A skater's frame has three parts:

- **The mesh pass** (stick, arms, spine, skin, head, off hand) reads the
  gameplay markers and writes only mesh, and a skater off camera skips it.
  `test_off_camera_culling.gd` holds that skipping it moves nothing gameplay
  reads.
- **The on-ice chrome** (ring, name, chevrons) and the effects.
- **The gait.** It runs for a skater nobody sees, because it is not only mesh:
  a held pose's share of the crouch lowers the gameplay frames
  (`SkaterSkatingCoordinator.apply` → `Skater.set_skating_crouch_drop`).

A server pays for all three because `SkaterCameraCull.sees` answers true with no
camera, which is right for a test or a tool and wrong for a machine nobody is
watching. With a camera that sees no skater mounted (`--look-away`), same match
as the table above, two runs: the process step fell from 18.0 to 12.5 ms a
frame, the tick did not move, and the match played out. Freezing the chrome and
the effects on top of that moved nothing.

### On the native kernels

Built in the same container (12 of 12 kernels active) and rerun, 2026-11-22: the
5v5 server match capped at 90 fps, two runs each. Editor (debug) binary still.

| | process step, ms a frame | tick, ms | main thread busy | frame rate held |
|---|---|---|---|---|
| as a server is today | 5.7 | 4.6 | 89% | 85 of 90 |
| every skater off camera | 2.2 | 4.9 | 64% | 89.5 of 90 |

The tick held 90 Hz in all four. The native kernels are the process step's, not
the tick's: the tick costs what it did on GDScript.

The mesh pass is 3.5 ms a frame, a third of a core at a tick a frame, and a
server as it stands cannot hold that frame rate on this machine. Counting as
nobody watching is a few lines over a path that is already tested, and it is
the larger half of the saving.

Of the 2.2 ms left, a 3v3 run the same way (1.5 ms for six skaters) puts about
0.16 ms on each skater and 0.6 ms on the frame. So the gait is at most 1.6 ms a
frame for ten, 0.14 of a core, and that is a ceiling: it is everything a skater
still does each frame, not the gait alone. Skipping it means first moving the
held pose's crouch onto the tick, which is reconcile code.
