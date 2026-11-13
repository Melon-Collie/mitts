# Dedicated servers — design plan

Status: **design agreed in chat, 2026-11-13. Nothing is built but the probe in
§7.** The rows under *Proposed, not confirmed* were put forward in that chat and
not answered; settle them before the phase that needs them.

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

Sized for a closed beta, and deliberately small:

- **One rented Linux box** with the headless build and an allocator: a small
  process that starts one server process a match on its own port and says so
  when it has no room.
- **The matchmaker on Supabase**, which the game already uses: a queue table
  and a function that pairs parties and asks the allocator for a server.
- **One region.** The input lead covers a one-way trip of up to 100 ms
  (`MAX_ONE_WAY_S`).

A managed fleet is worth its cost once concurrent matches outgrow one box.
Vendors and prices have not been compared.

## 6. Phases

Each phase is playable on its own and the next is built on it.

1. **Hosted vs AI for one tester.**
   a. The host path runs with no local player and no camera (§7 is the list).
   b. A headless launch that boots from a match config and exits after posting.
   c. ENet between that server and a client on one machine, then across the
      network.
   d. The server's telemetry row.
   e. The allocator on one box, and a button in the client that asks it for a
      vs-AI match.
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
