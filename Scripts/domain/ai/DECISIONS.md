# Bot decisions — inventory

Everything a bot perceives and decides, where it lives, and the test that holds
it. A catalogue, not doctrine: the *why* is in [CLAUDE.md](CLAUDE.md) (design
rules) and [../../ai/CLAUDE.md](../../ai/CLAUDE.md) (agent wiring); each section
links the headings it depends on.

Conventions: `file.gd:func` — every basename under `Scripts/` is unique, so the
bare name is the path. Tests are under `tests/unit/{ai,rules,state}/` unless
marked *slow* (`tests/slow/ai/`). Tiers are written E/N/H.

---

## 1. The pipeline

Doctrine: [How the brain hands out work](../../ai/CLAUDE.md#how-the-brain-hands-out-work),
[The dispatch throttle](../../ai/CLAUDE.md#the-dispatch-throttle),
[How an agent is put together](../../ai/CLAUDE.md#how-an-agent-is-put-together).

| # | stage | entry | cadence / thread | reads | writes |
|---|---|---|---|---|---|
| 0 | AI snapshot | `game_manager.gd:_physics_process` → `_enrich_snapshot_for_ai`, `acceleration_tracker.gd:update`, `_apply_bot_carrier_reaction_delay` | tick rate, main | state buffer, registry, live brain's one-timer flags, ping-chaser mirror | `current_snapshot`: states, `teammate_ids_by_team`, `closest_to_puck_by_team` (chase election), `tag_up_peers`, `accel_by_peer`, `heading_omega_by_peer`, `real_puck_carrier_peer_id`, puck carrier **debounced** by `CarrierBelief.update` |
| 1 | batch kick / harvest | `ai_coordinator.gd:dispatch`, `_try_harvest`, `_drain_brain_commands`, `_publish_brain_mirrors`, `_worker_loop` | every frame; a batch only when the worker is idle | queued pings / retick / exclude | `_worker_bots`, stabilized snapshot; on harvest → `ai_controller.gd:collect_one_timer_ready` |
| 2 | team brain | `team_brain.gd:tick` → `_compute_tick` | 6 Hz (team 1 +½ period); forced by `game_manager.gd:_force_retick_team_brains` and pings; worker | snapshot, caps / position / bot-peer maps, `team_size`, `rule_set` | `state`, `slot_assignments`, `threat_assignments`, `threat_shoot_base_by_opp`, `rush_read`, `_strong_x`, `coverage_downgraded` (§2) |
| 3 | frozen view | `team_brain.gd:build_view` | every batch, worker, after all brains tick | live brain | `TeamBrainView` (via `team_strategy_view.gd`): slots, threats, strong_x, rush copy, one-timer flags, per-peer pings. **Possession `state` is not in it** — an agent sees it only through its slot |
| 4 | agent decide | `ai_controller.gd:decide` → `skater_agent.gd:tick` → `skater_agent_state_machine.gd:dispatch` | every batch; full dispatch every `dispatch_period_ticks` (H 2 / N 6 / E 9 ticks), ×2 off-puck beyond 18 m; press states every tick; worker | snapshot, view via `_strategy()` | `InputState` scratch |
| 5 | slot → role | `_state_off_puck` → `_build_role_context` → `_dispatch_role_decision` | role argmax ~30 Hz reactive / ~15 Hz shape, ×½ beyond 18 m; bypassed by `must_recompute` | `RoleContext` (snapshot, view, self caps, tier knobs, pings) | cached `RoleDecision` |
| 6 | role module | `role_behaviors/*.gd:decide` (§3) | as 5 | `RoleContext` | `RoleDecision`: `target_position`, `target_velocity`, `retreat_floor_*`, `advance_cap_m_s`, `face_travel`, `aim_world_pos`/`has_aim_override`, `lift_blade`, `is_one_timer_ready`, `commit_check`, `engaged_peer_id`, `pressures_puck`, `locked_man_pid`, `arrive_at_speed`, `held_forward_stand` |
| 6c | carrier | `carrier.gd:AIRoleCarrier.decide` from `_state_carry` | compete ~30 Hz (≈10 Hz open ice), sliced across 2 dispatches (§4) | `RoleContext` | `intended_action` + per-intent public fields |
| 7 | state handler | `_state_off_puck` / `_state_chase_puck` / `_state_carry` / `_state_*_pressed` (§5) | as 4 | decision / carrier mirrors | `move_vector` (steering), `mouse_world_pos` (cursor), buttons, `elevation_level`, `bot_*_aim_dir`, `bot_wrister_power_t` |
| 8 | post-dispatch passes | `skater_agent.gd:tick` → `apply_stick_lift_input`, `apply_stand_up`, `apply_board_play`, `apply_shot_block`, `apply_press` | every agent tick, decided or not | snapshot, own collaborator state | may overwrite `stick_check_*`, `move_vector`, `hit_held`, `brake`, `block_held`, `stance_held`, `mouse_world_pos` |
| 9 | apply | `ai_controller.gd:apply_decision` → `skater_controller.gd:_process_input` | main, frames the worker is idle | `_pending_input` | the body, exactly as a human's input |

Outside the agent: faceoff draw / skate-in (`ai_controller.gd:begin_tick`, `_center_draw_target`), tutorial puppeting (`set_scripted_mode`, `script_*`).

---

## 2. Team brain — perception and decisions

Doctrine: [DZONE is a shape, not a location](CLAUDE.md#dzone-is-a-shape-not-a-location),
[Covering a man is one behavior](CLAUDE.md#covering-a-man-is-one-behavior-and-the-role-only-chooses-who),
[Determinism](CLAUDE.md#determinism), [Two brains, two cadences](../../ai/CLAUDE.md#how-the-brain-hands-out-work).

| read / decision | function | inputs | output | test |
|---|---|---|---|---|
| possession state (7 states) | `possession_state.gd:compute` | puck zone, puck speed (`NEUTRAL_PUCK_SPEED_M_S`), **debounced** carrier, sticky last carrier team | `TeamBrain.state` | `test_possession_state.gd` |
| coverage readiness gate | `rush_read.gd:_coverage_ready` + `possession_state.gd:coverage_read`, in `team_brain.gd:_compute_tick` | bot bodies inside our blue line vs `attackers` (capped), `COVERAGE_HOLD_TICKS` leave-hysteresis; only while an opponent carries | DZONE → TRANS_DEFENSE downgrade; `coverage_downgraded` | `test_coverage_readiness.gd` |
| strong side | `team_brain.gd:_compute_tick` | puck x, `STRONG_SIDE_HYSTERESIS_M` | `_strong_x` → `strong_x()` | none for the hysteresis |
| rush mode / axis | `rush_read.gd:fill` | carrier (or loose puck) pos/vel, closing along axis, `REGROUP_CLOSING_M_S` | `mode`, `threat_axis`, `carrier_peer` | `test_rush_read.gd` |
| rush ETA | `rush_read.gd:_origin_eta` | carry ETA, or best opponent collect + carry | `rush_eta_s` | indirect only (`test_rush_read.gd` via attackers) |
| who is attacking | `rush_read.gd:_fill_attackers` | `time_to_arrive` to our net ≤ rush ETA + `LATE_MAN_WINDOW_S`; offside-positioned bodies dropped | `attackers`, `attacker_leads` | `test_rush_read.gd` |
| who is back | `rush_read.gd:_fill_recovery` | radial goal-side test; race to the house gate + `BACKCHECK_WINDOW_S`; `TRACK_ENTER/HOLD_MARGIN_S` | `inside` / `tracking` / `beaten`, `recovery_by_peer` | `test_rush_read.gd` |
| numbers | `rush_read.gd:_fill_numbers` | attackers − (inside + tracking) | `numbers` (EVEN_OR_UP / DOWN_ONE / DOWN_TWO_PLUS) | `test_rush_read.gd` |
| backpressure | `rush_read.gd:_fill_backpressure` | trackers' ETA to the carrier's hip | `backpressure_s` | `test_rush_read.gd` |
| our carrier contested | `rush_read.gd:_pressure_eta` | nearest opponent ETA | `pressure_eta_s` (**unread by design**) | `test_offensive_station.gd` |
| slot election 3v3 | `role_slots.gd:assign`, `_pick_soonest_with_hysteresis`, `_hysteresis_class`, `_assign_*` | state, momentum-aware `time_to_arrive` at own `max_speed`, prev slots (+`HYSTERESIS_PENALTY_S`), flank side (+`HYSTERESIS_PENALTY_M`), peer-id tie-break | `slot_assignments` | `test_role_slots.gd` |
| slot election 5v5 | `role_slots_5v5.gd:assign`, `_specs_for_state`, `_pick_soonest`, `_hysteresis_class` | priority-ordered `SlotSpec` (F/D/ANY group, `home_slot` −`POSITION_BIAS_S`, `lateral_race`, RUSH_D1 feasibility `deadline_s`), cross-fill pass, spare → SUPPORT (ours) / MARK | `slot_assignments` | `test_role_slots_5v5.gd` |
| excluded bots | `team_brain.gd:exclude_skater` / `_compute_tick` | tutorial puppets | removed from slots | `test_team_brain_exclude.gd` |
| man-on-threat partition | `team_brain.gd:_compute_threat_assignments` → `threat_assignment.gd:assign` (`_pick_house_defender`, `_best_matching`, `cover_anchor`) | DZONE/TRANS_DEF only; defenders = MARK + non-owning ZONE_*; men = opponents minus carrier; value `possession_value.gd:threat_of_feed` (no defenders); finish danger: his one-timer off the feed (`shot_value.gd:feed`); zone eligibility `zone_coverage.gd:in_area` (the pressure owner's area open to all) (+`AREA_RELEASE_MARGIN_M`); `NET_FRONT_DANGER_BAR`; `HYSTERESIS_MARGIN_FRAC` | `threat_assignments` | `test_threat_assignment.gd`, `test_team_brain.gd` |
| shoot-threat memo | `team_brain.gd:_refresh_threat_base_memo` | `possession_value.gd:threat_of_carrier` per opponent, full team as the defence (only if a MARK is live) | `threat_shoot_base_by_opp` | `test_team_brain.gd` |
| ping orders | `ping_directives.gd:advance`, `add`, `apply_overrides`; `team_brain.gd:apply_ping` | COVER_HIM→MARK+man, DEFEND→MARK, PRESSURE_CARRIER→PRESSURE, GET_OPEN→FINISHER (never the carrier) | slot / threat overrides; per-bot `move_target_for` (GO_THERE), `chase_peer` (GET_PUCK), `shoot_ping_for`, `pass_target_for` | `test_ping_directives.gd` |
| one-timer readiness | written by `skater_agent_state_machine.gd:push_one_timer_ready` (main, at harvest) → `team_brain.gd:set_one_timer_ready` | role's `is_one_timer_ready` (+ preserve across a feed) | read by carrier pass EV, `carrier_pass_search.gd:developing_feed_value`, chase election (campers excluded) | `test_one_timer_chain.gd` |
| cadence | `team_brain.gd:tick`, `force_retick` | `TICK_PERIOD`, `_cadence_offset_s` | when `_compute_tick` runs | `test_team_brain.gd` |
| loose-puck chaser *(host, not brain)* | `game_manager.gd:_enrich_snapshot_for_ai` → `loose_puck_chase.gd:elect` | path walk, momentum ETA, incumbent, humans / campers / out-of-play excluded, dead puck → −1, GET_PUCK override | `closest_to_puck_by_team` | `test_loose_puck_chase.gd` |
| team carrier belief *(host)* | `game_manager.gd:_apply_bot_carrier_reaction_delay` → `carrier_belief.gd:update` | `carrier_reaction_delay_s` | `puck_state.carrier_peer_id` on the AI snapshot | `test_carrier_belief.gd` |
| accel / turn rate *(host)* | `acceleration_tracker.gd:update` | velocity diffs | `accel_by_peer`, `heading_omega_by_peer` | `test_acceleration_tracker.gd` |

---

## 3. Slots → roles

Doctrine: [The defensive verbs](CLAUDE.md#the-defensive-verbs),
[A defensive stand is a moving frame](CLAUDE.md#a-defensive-stand-is-a-moving-frame-not-a-spot),
[The gap ladder](CLAUDE.md#the-gap-ladder-is-one-ladder-and-both-puck-owners-read-it),
[The three facts a station reads](CLAUDE.md#the-three-facts-a-station-reads-and-the-one-that-stays-unread),
[A pinch is priced on both halves](CLAUDE.md#a-pinch-is-priced-on-both-halves-and-its-cover-is-another-roles-read).
Facts per slot (`[label, reactive, pressurer]`) live in `role_slots.gd:_SLOT_INFO`.
Shared station bounds: `last_man_discipline.gd:offensive_station_target` (OST) /
`neutral_station_target` (NST) = `may_hold_forward_stand` + `numbers_floor` /
`station_retreat_floor` + `pull_into_play`.

| slot (size: state) | module:func | reads (ctx) | decides | fallback | tests |
|---|---|---|---|---|---|
| CARRIER (both: OZ/TO/BO) | `carrier.gd:decide` via `_state_carry` — §4 | everything | intent | stale CARRIER off-puck → `support.gd:decide` | `test_role_carrier.gd` |
| PRESSURE (3: DZ) · F1_PRESSURE (both: FC) · owning ZONE_* | `pressure.gd:decide` | `read_carrier_approach`, `rush_read`, `pursuit_standoff_m`, blade reach, opp receivers (anticipation-led), `carrier_option_bases` | gap = standoff + `rush_d.gd:ladder_gap_m`/gap-up; angled `carrier_stand`; argmax minimises `carrier_best_option` (candidates priced at the ride velocity); `commit_check` via `evaluate_body_check` with support behind; RUSH_D1's route (`depth_first`, retreat floor, advance cap); ride velocity; house floor; `engaged_peer_id` | no puck → hold; no candidate → hold, no ride | `test_role_pressure.gd` |
| MARK (3: DZ; 5: spare off-poss.; pings) | `mark.gd:decide` | `assigned_threat_peer`, memo | `cover_threat` (target + man's velocity) + `locked_man_pid` (the stick tie) | no man → argmax −max `threat_of_carrier` (candidate pushed onto `role_reads.gd:defence_possession`) around puck/net midpoint; no opps → hold | `test_role_mark.gd` |
| FINISHER (3: OZ; GET_OPEN) · NET_FRONT (5: OZ) | `finisher.gd:decide` (`_try_reactive_decision`, `_positioning_decision`) | debounced carrier, shooter loft, carrier closing speed, opp goalie | tip: step onto shot path, aim override at net, `lift_blade`; else named stations (backdoor, bumper, weak dot, high slot, tip) scored max(one-timer feed `score_pass_value`, `tip_ev`); `is_one_timer_ready` | no carrier → hold | `test_role_finisher.gd`, `test_one_timer_chain.gd` |
| SUPPORT (3: OZ/TO; 5: spare in poss.) · TRAILER (5: TO) | `support.gd:decide` | carrier, opps, mates, both goalies | argmax `score_pass_value` − `counter_rush_cost`, goal-side of carrier; OZ high post; `may_hold_forward_stand`/`numbers_floor` | no play ref → hold | `test_role_support.gd` |
| OUTLET (3: TO) · BREAKOUT_STRETCH (5: BO) | `outlet.gd:decide` | carrier closing speed, `strong_x` | argmax max(`lane_clear`, floor) × our possession of the spot (`role_reads.gd:attack_possession`, the receiver there as the pass arrives, at his velocity); velocity-corrected offside filter; rush pacing, `arrive_at_speed` | no play ref → hold | `test_role_outlet.gd` |
| BREAKOUT_STRONG (both) · BREAKOUT_WEAK (3) · BREAKOUT_D2 (5) | `breakout.gd:decide(is_strong)` | carrier, opps, `strong_x` | wall samples (strong) / goal-side reverse (weak); same lane × possession score | no play ref → hold | `test_role_breakout.gd` |
| BREAKOUT_C (5: BO) | `breakout_center.gd:decide` | carrier, opps | low swing: mid vs circle lane by `lane_clear`; `arrive_at_speed` | no play ref → hold | **none** |
| F2_MID · F3_HIGH (3: FC) | `forecheck.gd:decide` (`_decide_mid`, `_decide_high`) | carrier/puck, opp receivers | F2: minimise best breakout feed (`_max_pass_threat`); F3: `wall_rim_keepin` else OST as back layer | no play ref → hold | `test_role_forecheck.gd` |
| F2_STRONG · F2_WEAK (5: FC) | `forecheck.gd:decide_f2` | as F2 | lane argmax; weak fills a pinch via `defenseman.gd:rotate_up_to_point` | hold | `test_role_forecheck.gd` |
| CHASE (both: NEUTRAL) | `chase.gd:decide` → `defensive_verbs.gd:chase_puck` | `loose_puck_race_lost` | race (puck) or pre-contain `carrier_stand` on the puck | no puck → hold | `test_role_chase.gd` |
| FLANK_L/R (both: NEUTRAL) | `flank.gd:decide` | puck, home side | NST off a puck-side stand, layer = `zone_coverage.gd:defensive_anchor` | no puck → hold | `test_role_flank.gd` |
| RUSH_D1 (both: TD) | `rush_d.gd:_decide_d1` | `rush_read` (numbers, backpressure, threat axis), approach, `plays_rush_pass_lanes` | ladder gap + ramp cushion, `should_gap_up`, `_settable_gap`, `carrier_stand`, odd-man `_lane_fan_target` (a receiver's lane offered only when his one-timer clears `LANE_PLAY_DANGER_BAR`; candidates priced by `carrier_best_option` at the ride), `depth_first`, `set_retreat_facing` (turn and skate), house clamp, ride, retreat floor, advance cap | no puck → hold; on our net → carrier pos | `test_role_rush_d.gd`; *slow* `test_rush_gap_discipline.gd`, `test_defensive_routing.gd`, `test_nz_turnover_recovery.gd`, `test_speed_rush_defence.gd`, `test_two_on_one_defence.gd` |
| RUSH_D2 (5: TD) | `rush_d.gd:_decide_d2` | `rush_read.attacker_leads` | `cover_threat` on the mid-lane man | mid-ice post behind D1 | `test_role_rush_d.gd` |
| TRACK_PUCK (both: TD) | `track.gd:_decide_puck` | approach, `rush_read.mode` | hip (`_hip_gap`), ride; `commit_check` once goal-side; aim override on carrier | no puck → hold | `test_role_track.gd` |
| TRACK_MID (3) · TRACK_MID_STRONG/WEAK (5) | `track.gd:_decide_mid` | `recovery_by_peer`, `threat_axis`, leads | not inside → recovery post at pace; inside → `cover_threat` lane man | post | `test_role_track.gd` |
| HIGH_SLOT (5: OZ) | `high_slot.gd:decide` | carrier, opps, mates | fills a pinch (`rotate_up_to_point`); band argmax feed lane × shot lane above puck; OST | band filtered → 1 m inside line | `test_role_defenseman.gd` (rotation only) |
| POINT_STRONG/WEAK (5: OZ) | `defenseman.gd:_decide_point` | puck depth, opps, partner | `wall_rim_keepin`; lane argmax on point-shot `lane_clear`, strong sinks; weak holds middle if partner vacated; OST | base stand | `test_role_defenseman.gd`, `test_point_holds_the_line.gd`, `test_offensive_station.gd` |
| DP_STRONG/WEAK (5: FC) | `defenseman.gd:_decide_line_hold`, `_wall_pinch`, `_pinch_is_covered` | carrier, partner, rush read | keep-in; strong may pinch (`pressures_puck`); OST | line stand | `test_role_defenseman.gd` |
| DVALVE (5: TO) | `defenseman.gd:_decide_valve` | play ref | central trail, OST, `arrive_at_speed` | hold | `test_role_defenseman.gd` |
| DBACK_L/R (5: NEUTRAL) | `defenseman.gd:_decide_back` | puck x | blue-line pair shaded with puck, NST | — | `test_role_defenseman.gd` |
| ZONE_D_STRONG/D_WEAK/C/W_STRONG/W_WEAK (5: DZ) | `zone_defense.gd:decide` | `strong_x`, `assigned_threat_peer` | owner of puck area (`zone_coverage.gd:pressure_owner`) → PRESSURE; else `cover_threat` + `locked_man_pid` | `zone_coverage.gd:anchor_of` (breathes with puck) | `test_role_zone_defense.gd`, `test_zone_coverage.gd`; *slow* `test_zone_coverage_shape.gd` |
| WIDE_L/R (5: TO) | `wide_lane.gd:decide` | play ref | outside lane ahead of play, held NZ-side until the puck crosses; `arrive_at_speed` | hold | **none** |
| NONE | `skater_agent_state_machine.gd:_dispatch_role_decision` default arm | — | hold `self_pos` | — | — |

Agent-side per-slot facts outside the role: `_is_reactive_slot` (argmax cadence),
`_is_puck_pressurer_slot` (who may jab), ping GO_THERE override in `_state_off_puck`.

---

## 4. The carrier

Doctrine: [One currency across the carrier's compete](CLAUDE.md#one-currency-across-the-carriers-compete),
[Hesitation is a raised bar](CLAUDE.md#hesitation-is-a-raised-bar-never-a-timer),
[The models in detail](CLAUDE.md#the-models-in-detail) (shot value, carry safety, pass lanes, rims, positional value, controlled space),
[Where an evaluator goes](CLAUDE.md#where-an-evaluator-goes).
The carrier is `carrier.gd` (the compete: intents, phases, argmax, commitment) over `carrier_field.gd` (`AICarrierField`: what it sees, what a spot is worth, what a turnover costs) and two searches that read the field — `carrier_pass_search.gd`, `carrier_carry_search.gd`. Bare function names below are in `carrier.gd`; `test_carrier_collaborator_seams.gd` holds the seam.

**Currency** — the odds of scoring: `action_scoring.gd:score_shoot_value` (the `shot_value.gd` seam) in the zone; outside it, past what the carry searches, `carrier_field.gd:horizon_value` → `possession_value.gd:at` (our possession: the best zone entry's worth × the skate's decay × `action_scoring.gd:arrival_race`). Every option pays `carrier_field.gd:turnover_cost` (the opponent's possession at the loss point, `possession_value.gd:at`) and, 5v5 only, `carrier_field.gd:counter_exposure_cost` (`counter_rush_cost` × `carrier_field.gd:EXPOSURE_APPETITE_*`). Future value × `action_scoring.gd:delay_discount`.

| action | evaluator | sees | vetoes / gates | test |
|---|---|---|---|---|
| SHOOT (wrister) | `_pick_fire_phase` hold sweep: `shot_holds.gd:solve_shot`/`price_keep` × `score_shoot_value`; aim and loft `shot_odds.gd:pick_shot_now`; keeper as read now (`shot_odds.gd:stance_of`) | release projected over windup + pull, goalie as replicated (the field prices his answer), release-time defenders, load share, keep odds | puck ≤ `SHOT_MIN_FORWARD_OF_LINE_M` past goal line; outside zone with keeper home (`THREAT_GOALIE_HOME_M`); `SHOT_MIN_VALUE` after settle handicap; staggered or settling a catch; ping SHOOT ×`PING_SHOOT_EV_MULT` | `test_role_carrier.gd`, `test_shot_holds.gd`, `test_shot_value.gd` |
| SHOOT for a tip | `action_scoring.gd:tip_ev` (max with direct shot) | in-zone mates as tippers, faster hold | as SHOOT | `test_ai_action_scoring.gd`, `test_role_finisher.gd` |
| PASS flat | `carrier_pass_search.gd:search` (at each pace of `puck_lane.gd:PASS_PACE_FRACS`; the commit fires the winner's) → `carrier_pass_search.gd:_pass_variant_ev` → `carrier_pass_search.gd:_pass_ev`; `pass_lead.gd:lead`; `puck_lane.gd:lane_clear` (with the defenders' blades, `puck_lane.gd:_blade_block`), `release_contest_clean`, `pass_miss_prob`, `receiver_heading_uncertainty_m`; `carry_space.gd:reach_clearance` (reception) | receiver value at lead (his shot speed/loft, keeper over flight, no windup if one-timer-ready), drive-in credit `carrier_field.gd:receiver_drive_in_value`, receiver facing rotation `carrier_pass_search.gd:_facing_rotation_time`, 4 loss modes priced at their spots, the reception at `feed_reception.gd:arrival_closing_speed`, caught or bobbled by `feed_reception.gd:receiver_bobble_prob` — a catch settles (`receiver_settle_s`: delays his action and holds the puck in the reception read's reach), a bobble is a loose puck he wins back only by `action_scoring.gd:arrival_race` at his `bobble_regather_s` | out-of-play receiver; a softer pace whose flight outruns `PASS_LEAD_MAX_S`; carrier in zone → receiver/lead in zone (`OZ_RECEIVE_LINE_BUFFER_M`); lead past own goal line; `zone_entry_blocked`; `net_obstacle.gd:pass_lane_blocked_by_net`, `pass_crosses_own_slot`; lane 0; `PASS_MIN_VALUE`; ping PASS ×`PING_PASS_EV_MULT` | `test_role_carrier.gd`, `test_carrier_never_back_passes.gd`, `test_pass_lead.gd`, `test_pass_settle_price.gd` |
| PASS saucer | `carrier_pass_search.gd:_pass_variant_ev` (saucer), `puck_lane.gd:lane_clear_saucer`, `saucer_max_launch_speed` | sticks under the flight | flat lane ≥ `SAUCER_SKIP_WHEN_LANE_CLEAR`; no landing runway; not better than flat; +`SAUCER_EXTRA_MISS_PROB` | `test_ai_action_scoring.gd`, `test_role_carrier.gd` |
| PASS rim | `rim_pass.gd:build`, `carrier_pass_search.gd:_rim_launch_for` (rank), then `carrier_pass_search.gd:_pass_ev` for the single best | boards path walk, receiver meet/catchability, opponent + keeper race, softest launch within `RIM_SOFT_SHARE` | flat lane clear; zone rules as flat; released as INTENT_DUMP | `test_rim_pass.gd`, `test_role_carrier.gd` |
| one-timer feed | a PASS whose receiver `is_one_timer_ready` (keeper gets flight only) | readiness flag (§2) | as PASS | `test_one_timer_chain.gd` |
| CARRY | `carrier_carry_search.gd:search` → destinations (`carrier_destinations.gd:fill`, each priced by `carrier_carry_search.gd:_score_destination` → `_score_move_candidate_base`/`_score_wheel_candidate`, chosen by `carrier_destinations.gd:choose`'s hysteresis) → near moves (`carry_rollout.gd:roll_all` toward the destination or `arrival.gd:cage_waypoint`; `carrier_carry_search.gd:_score_move` one-ply → `_upgrade_candidate_two_ply` (`carrier_field.gd:pass_option_from`, and for the `CARRY_PLY2_WIDTH` best moves `carrier_carry_search.gd:_carry_on_value`, every move rolled again from the end)) | candidates: standing still (paying the step's decay outside the zone) and the seven rolled moves; each move = max(`carrier_carry_search.gd:_end_worth` at its end — the arrival value or the destination carried on —, the pass option there, the best second move) × decay × `carrier_carry_search.gd:_rolled_safety` − strip cost | one-way OZ valve (`OZ_RETREAT_LINE_BUFFER_M`); `zone_entry_blocked`; no ice behind the goal line from in front; no crease; `carrier_carry_search.gd:_candidate_ice_legal` for destinations; exact ceiling prunes; `CARRY_BEAM_WIDTH`, `CARRY_PLY2_WIDTH` | `test_role_carrier.gd`, `test_carrier_destinations.gd`, `test_carry_rollout.gd`, `test_bot_duels.gd` |
| stand still | inside `carrier_carry_search.gd:search` | shoot-now score (or our possession outside the zone) × safety − cost | wins only strictly | `test_role_carrier.gd` |
| drive-in floor | `carrier_field.gd:receiver_drive_in_value` (self) floors carry | — | — | `test_role_carrier.gd` |
| HOLD for a developing feed | `carrier_pass_search.gd:developing_feed_value`, `carrier_pass_search.gd:_developing_outlet_feed` × current safety × `delay_discount(_hold_elapsed_s)` | FINISHER or NET_FRONT spot projected `OUTLET_DEVELOP_WINDOW_S` (`score_pass_value`); OUTLET / BREAKOUT_STRONG / BREAKOUT_D2 skating ≥ `OUTLET_DEVELOP_MIN_SPEED_M_S` | `holds_for_developing_feeds`; one-timer-ready finisher skipped | `test_role_carrier.gd` |
| protect (blade) | `_pick_fire_phase`: `carry_space.gd:best_handle_protect_point` → `protect_gain`/`protect_offset`; `_fill_protect_opponents` | non-beaten defenders (`PROTECT_SCREEN_BEHIND_M`) | `protects_the_puck` (`forward_puck_clearance` always computed) | `test_role_carrier.gd`, `test_reach_safety.gd` |
| evade seam | `carry_space.gd:best_evade_point` (current safety) | momentum-projected reach | — | `test_reach_safety.gd` |

**Argmax / commitment** — `decide` (throttle `PICK_ACTION_PERIOD_TICKS`, open-ice LOD `_arm_pick_cooldown`, slicing `_pick_fire_phase` → next dispatch `_pick_commit_phase`; full eval on `reset`/`clear_intent`) → `_pick_commit_phase`:
1. each fire option qualifies against its **own** bar using `_settle_handicap(value, _settle_penalty(ctx))`; best qualified = `fire_score` (−INF if none);
2. hysteresis ×(1+`ACTION_HYSTERESIS_MARGIN_FRAC`) on the incumbent fire intent only (CARRY never);
3. fire if `fire ≥ carry` and `fire ≥ hold` (ties fire), or retention hopeless — never while staggered, nor while settling a hard catch (`ctx.self_settle_s`, the controller's settle lock, which would only queue the press — `docs/stick-settling-plan.md`; unrelated to the settle *doubt* in step 1);
4. else CARRY (advance `_hold_elapsed_s` only while hold > carry and retention is not hopeless).

Agent side (`skater_agent_state_machine.gd`): `_state_carry` latches the intent (`_state_from_carrier_intent`), freezes shot/dump params, pre-aims (`_aim_target_for_intent`, `_lock_pass_hold`), presses when `_load_ready` or on `_intent_max_wait_ticks` (every release is a charged wrister); then `carrier.clear_intent()`.

---

## 5. Agent behaviour outside the role decision

Doctrine: [Reception doctrine](../../ai/CLAUDE.md#reception-doctrine), [Chase doctrine](../../ai/CLAUDE.md#chase-doctrine),
[Who may play the puck](../../ai/CLAUDE.md#who-may-play-the-puck), [The blade cursor](../../ai/CLAUDE.md#the-blade-cursor-leaves-the-agent-untouched),
board / shot-block / tie extras in [The defensive verbs](CLAUDE.md#the-defensive-verbs).
Functions in `skater_agent_state_machine.gd` unless named.

| behaviour | function | trigger | reads | test |
|---|---|---|---|---|
| OFF_PUCK | `_state_off_puck` | default | role decision, pings | `test_skater_agent_state_machine.gd` |
| tag-up override | `_state_off_puck` → `_tag_up_anchor` | `snapshot.is_out_of_play(self)` | blue line | `test_world_snapshot_out_of_play.gd` |
| off-puck blade priority | `_state_off_puck` | yank > jab > tie > one-timer aim > aim override > ready stance (`_ready_stance_aim`, `_compute_desired_aim_dir`, `_deflect_safe_aim_dir`) | decision, puck | `test_skater_agent_state_machine.gd` |
| one-timer readiness preserve | `_state_off_puck`, `_set_one_timer_ready` | ready role through a pass flight (`ONE_TIMER_PRESERVE_MAX_TICKS`) | **real** carrier | `test_one_timer_chain.gd` |
| → CHASE_PUCK | `_should_chase_loose_puck`, `skater_agent_reception.gd:incoming_pass`, `_post_puck_lost_state` | real carrier none, `_loose_elapsed_s ≥` reaction delay; GET_PUCK; reach band (`loose_puck_chase.gd:puck_comes_to_reach`, `_teammate_first_to_puck`); election; not `loose_puck_chase.gd:loose_puck_race_lost` | election, path | `test_skater_agent_state_machine.gd`, `test_loose_puck_chase.gd`; *slow* `test_loose_puck_engagement.gd` |
| chase steering | `_state_chase_puck`, `_lead_intercept`, `_shade_intercept_goal_side` | chasing | contested 50/50 overshoot, blade-first route, rink clamp | `test_ai_chase_angling.gd`, `test_skater_agent_state_machine.gd` |
| reception | `_try_shot_reception` → `skater_agent_reception.gd:read_shot` (A: one-time, B: net-ward catch; square-up `_squared_to_shoot`), `_pass_receive_aim_and_steer` → `skater_agent_reception.gd:read_pass`, `_chase_reception_aim_target`, `skater_agent_reception.gd:blade_gate`, `skater_agent_reception.gd:wall_kill_aim`; give-brake `skater_agent_reception.gd:RECEIVE_GIVE_CEILING_M_S` | fast loose puck toward me | `trajectory.gd` path, the better feed (`score_pass_value`, one-timed or caught) ≥ `skater_agent_reception.gd:SHOT_RECEPTION_SCORE_GATE`, redirect angle / forehand / square-up | `test_skater_agent_reception.gd`, `test_skater_agent_state_machine.gd`, `test_one_timer_chain.gd`; *slow* `test_pass_reception_catch.gd` |
| strip pull-back | `_update_engagement_cooldown` | puck just knocked loose near me | `ENGAGEMENT_*` | `test_skater_agent_state_machine.gd` |
| CARRY cursor | `_step_carry_cursor`, `_carry_mouse_aim`, `_carry_aim_track_fire`, `_stickhandle_offset`, `_has_man_to_beat`, `_carry_reach_behind_net`, `_arc_step_mouse_target`, `_protect_turn_direction` | carrying, no intent | carrier mirrors (`protect_*`, `forward_puck_clearance`, `shoot_now_hold`) | `test_skater_agent_state_machine.gd` |
| SHOOT_PRESSED | `_state_shoot_pressed` | intent ready | charge `BOT_WRISTER_CHARGE_TICKS`; bails: puck lost, stagger, front opponent `BOT_WRISTER_BAIL_RADIUS_M` | `test_skater_agent_state_machine.gd` |
| PASS_PRESSED | `_state_pass_pressed` | intent ready | charged pass; rim FLAT; saucer LOW; mid-charge bails | `test_skater_agent_state_machine.gd` |
| ONE_TIMER_PRESSED | `_state_one_timer_pressed`, `skater_agent_one_timer.gd:line_anchor`, `skater_agent_one_timer.gd:time_to_set`, `skater_agent_one_timer.gd:shuffle_stick`, `skater_agent_one_timer.gd:swing_for`, `skater_agent_one_timer.gd:puck_at_zone`, `skater_agent_one_timer.gd:feed_time_s` | ready + in zone + live feed line / puck in zone (`_puck_in_one_timer_zone`) | set wait (pivot, glide and shuffle against the feed's flight), catch when the feed beats both the set and the window, dead-feed bail, `ONE_TIMER_PRESS_MAX_TICKS` | `test_skater_agent_one_timer.gd`, `test_one_timer_chain.gd`, `test_bot_one_timer_loop.gd` |
| execution error | `_set_state` → `_sample_aim_error_rad`, `_sample_release_hold_ticks`; `_apply_committed_aim_error` | each press entry (the only RNG) | tier errors | `test_skater_agent_state_machine.gd`, `test_shot_sim.gd` |
| goalie-motion aim | `_shot_aim_point` → `shot_aim.gd:compute_open_net_aim` | one-timer / pre-aim fallback | goalie vx if `reads_goalie_motion` | `test_skater_agent_state_machine.gd` |
| steering | `skater_agent_steering.gd:steer` → `steering.gd:compute_move_vector` (repels, `_moving_frame_pursuit`, `_net_detour`, `_carrier_threat_repel`), `is_rideable_anchor`, `should_brake`, `should_arrival_brake`, `pivot_cuts_in_stance`, `stance_carves_to` | every decided move | anchor, anchor velocity, engaged peer, retreat floor | `test_ai_steering.gd`, `test_approach_speed_cap.gd`; *slow* `test_defensive_routing.gd` |
| offside brake | `apply_offside_guard` (last write in `skater_agent.gd:tick`) → `steering.gd:offside_brake`; `_teammate_must_tag_up` | every tick incl. skipped, after the deke and board play | puck vs line, team tag-up | `test_ai_steering.gd` |
| jab / lift | `skater_agent_stick_play.gd:jab_aim`, `jab_target`; `stick_lift_read.gd:prefers_lift` | pressurer slot (`_is_puck_pressurer_slot`) or `pressures_puck`, puck in reach | `lifts_sticks` | `test_bot_stick_lift.gd`, `test_stick_lift_read.gd` |
| stick tie / yank | `skater_agent_stick_play.gd:tie_aim`, `step_tie_follow`, `tie_yank_aim`; `stick_tie_read.gd` | `decision.locked_man_pid`, feed coming to him / me tied | `ties_sticks`, `TIE_LAG_BUDGET_S` | `test_bot_stick_lift.gd`, `test_stick_tie_read.gd` |
| stick-check button | `skater_agent_stick_play.gd:apply_button` | every tick | lift / tie holds | `test_bot_stick_lift.gd` |
| reach for a pin | `skater_agent_board_play.gd:_reach_for_pin` (stick button instead of the check) | dispatch holding `hit_held`, unbraced man on the wall within `PIN_REACH_S` of contact, the hit within his balance (`BodyBalanceRules.overshoot`), `_pin_worth_holding` | `check_aggression` | `test_bot_board_play.gd` |
| hold a pin / pinned slide | `skater_agent_board_play.gd:apply`, `_pin_worth_holding`, `_last_back`, `_team_arrival_s`, `_pinner_mirror` (matches the man's lagged slide speed, closes the offset), `_pinned_slide` | pin role ≠ NONE | `check_aggression`, `PIN_LAG_BUDGET_S` | `test_bot_board_play.gd`; *slow* `test_board_play.gd` |
| press a screen | `skater_agent_press.gd:_press_the_screen` → `press_read.gd:displacement_m` (= the host's `PressRules` pair on the man's replicated facing, posture, brake, stagger and intent), `screen_read.gd:clears_screen` (`hides_release` = the goalie's `screen_peek_offset` body test); holds `hit_held`, the stick into him | the covered man (`locked_man_pid`) in our end within `STEP_IN_M`, hiding the release from our goalie, moved off the sightline in `READ_S` | `check_aggression` | `test_bot_press.gd`, `test_press_rules.gd`, `test_screen_read.gd` |
| screener digs in | `skater_agent_press.gd:_dig_in` (holds the brake and the stance) | in their end hiding the release from their goalie, slow, an opponent within `STEP_IN_M` | `protects_the_puck` | `test_bot_press.gd` |
| carrier drives through a man | `skater_agent_press.gd:_drive_through` → `press_read.gd:pair_accel` with Ctrl against without (the host's `PressRules` pair, his own skate and the man's replicated facing, posture, brake, stagger and intent); holds `hit_held`, the carrier's brace | CARRY, the nearest opponent touching within `STEP_IN_M` and inside `DRIVE_THROUGH_COS` of our skate | `protects_the_puck` | `test_bot_press.gd` |
| carrier vs square checker | `skater_agent_board_play.gd:_answer_pin_threat` → `pin_threat_read.gd:answer` | carrying at the wall, a checker with his stick out (`StickCheckRules.is_stick_busy`) ≤ `PIN_THREAT_RANGE_M` | `protects_the_puck` | `test_pin_threat_read.gd`, `test_bot_board_play.gd` |
| shot block / 2-on-1 dive | `skater_agent_shot_block.gd:apply`, `_shot_coming`, `_dive_point`; `shot_block_read.gd` | opponent windup in our end on my line / numbers ≠ EVEN | `blocks_shots`; never while CARRY | `test_bot_shot_block.gd`, `test_shot_block_read.gd` |
| body check commit | `defensive_verbs.gd:evaluate_body_check` → `body_check.gd:evaluate`; SM holds `hit_held` | PRESSURE (support behind only) / TRACK_PUCK | `check_aggression`, own weight/transfer | `test_body_check.gd`, `test_role_pressure.gd` |
| stand up a carrier | `skater_agent_stand_up.gd:apply` → `stand_up_read.gd:meets` (holds `hit_held`) | every tick after dispatch: an opponent carrier skating into us inside `MEET_S` of contact, and the hit rocks him | `check_aggression` (0 never) | `test_stand_up_read.gd` |
| dispatch throttle | `dispatch` (skip counter, live re-aim on skipped ticks, far-play ×2), `_stagger_cadence_phases` | non-press states | `dispatch_period_ticks` | `test_skater_agent_state_machine.gd`; `benchmarks/` |
| role-argmax throttle | `_state_off_puck` (`must_recompute`, `_is_reactive_slot`) | OFF_PUCK | `ROLE_DECISION_PERIOD_TICKS`, `FAR_PLAY_LOD_RADIUS_M`, `FINISHER_FLIGHT_NEAR_M` | `test_skater_agent_state_machine.gd` |

---

## 6. Difficulty — `bot_skill_profile.gd`

Doctrine: [Difficulty rides three independent axes](CLAUDE.md#difficulty-rides-three-independent-axes),
[The rule that keeps cognition gates honest](CLAUDE.md#the-rule-that-keeps-cognition-gates-honest).
Plumbing: `skater_agent_state_machine.gd:apply_profile` → SM field → (roles) `_build_role_context` → `RoleContext`. Test: `test_bot_skill_profile.gd`. Goalie tiers: `GoalieSkillProfile`, mirrored by `AIGoalieModel.set_goalie_profile`.

| field | axis | E / N / H | read at |
|---|---|---|---|
| `carrier_reaction_delay_s` | precision | 0.34 / 0.22 / 0.05 | `game_manager.gd:_apply_bot_carrier_reaction_delay` (team shape); `_should_chase_loose_puck` (own chase clock) |
| `dispatch_period_ticks` | precision | 9 / 6 / 2 | `dispatch`, `_stagger_cadence_phases`, `_state_off_puck`, `_state_carry`; `carrier.gd:decide`; `skater_agent_stick_play.gd:jab_aim` |
| `shot_aim_error_rad` | precision | 0.055 / 0.04 / 0.01 | `_set_state` (sample); execution only |
| `pass_aim_error_rad` | precision | 0.0225 / 0.015 / 0.01 | `_set_state`; `carrier_pass_search.gd:_pass_variant_ev`, `carrier_pass_search.gd:_rim_launch_for`, `carrier_field.gd:pass_option_from` (`pass_miss_prob`) |
| `shot_timing_error_s` | precision | 0.24 / 0.16 / 0.10 | `_sample_release_hold_ticks` |
| `settle_penalty_frac` / `_tau_s` | precision | 0.85, 0.55 / 0.60, 0.30 / 0.0, 0.25 | `carrier.gd:_settle_penalty` → `_pick_commit_phase` bars |
| `pursuit_standoff_m` | pace (space) | 3.0 / 0.75 / 0.0 | `pressure.gd:decide` |
| `pass_speed_scale` | pace | 0.75 / 0.85 / 1.0 | `carrier_pass_search.gd:search`, `_pick_commit_phase`, `carrier_field.gd:pass_option_from`, `carrier_pass_search.gd:developing_feed_value`, `carrier_pass_search.gd:_developing_outlet_feed` |
| `check_aggression` | pace (threat) | 0.0 / 0.65 / 1.0 | `defensive_verbs.gd:evaluate_body_check`; `skater_agent_board_play.gd:apply` |
| `defensive_anticipation_scale` | pace (space) | 0.2 / 0.6 / 1.0 | `role_reads.gd:collect_opp_team_excluding_carrier`, `collect_opponents` |
| `reads_goalie_motion` | cognition | F / T / T | `_shot_aim_point`; `carrier_field.gd:goalie_unsettled_at`, `carrier_carry_search.gd:_score_move_candidate_base` |
| `holds_for_developing_feeds` | cognition | F / T / T | `carrier_pass_search.gd:developing_feed_value` |
| `reads_receiver_commitment` | cognition | F / T / T | `carrier_pass_search.gd:search` (ω = 0 when off) |
| `angles_the_chase` | cognition | F / T / T | `_state_chase_puck` |
| `plays_rush_pass_lanes` | cognition | F / T / T | `rush_d.gd:_decide_d1` |
| `protects_the_puck` | cognition | F / T / T | `carrier.gd:_pick_fire_phase`; `_carry_mouse_aim`; `apply_board_play` (pin answer) |
| `lifts_sticks` | cognition | F / T / T | `skater_agent_stick_play.gd:jab_aim` |
| `ties_sticks` | cognition | F / T / T | `skater_agent_stick_play.gd:tie_aim`, `tie_yank_aim` |
| `blocks_shots` | cognition | F / T / T | `apply_shot_block` |

Not tier knobs: aim slew (`apply_capabilities` → `_apply_aim_slew`, real blade speed); every `AISkaterCaps` build number.

---

## 7. Feel tunables (not evaluation)

Hand-picked by design ([Evaluators model perception, never feel](CLAUDE.md#evaluators-model-perception-never-feel)). Constant names, by file.

- **Election targets** — `role_slots_5v5.gd`: `_POINT_INSET_M` … `_TRACK_MID_SPLIT_M`, plus inline literals in `_specs_for_state` / `_breakout_post_specs` (TRAILER `6.0`, ZONE_D_WEAK `1.0`, ZONE_C `1.5`, BREAKOUT_STRONG `half_w − 2.0`, BREAKOUT_D2 `1.0`).
- **Zone anchors** — `zone_coverage.gd`: `*_REST_*`, `W_*`, `BREATHE_*`, `D_HOME_U_M`, `F_HOME_DEPTH_INTO_NZ_M`, `SHOT_LANE_STEP_M`.
- **Role staging** — `finisher.gd` (`WEAK_SIDE_BIAS_M`, `RUSH_*`, `TIP_STATION_DIST_M`); `support.gd` (`SEARCH_RADIUS_M`, `HIGH_POST_INSET_M`, `GOAL_SIDE_TOLERANCE_M`); `outlet.gd` (`BLUE_LINE_BUFFER_M`, `WEAK_SIDE_INSET_M`, `RUSH_*`, `PACE_TOLERANCE_M`, `BLOCKED_LANE_FLOOR`); `breakout.gd` (`WALL_*`, `STRONG_*`, `MID_SEAM_FRACTION`, `BLOCKED_LANE_FLOOR`); `breakout_center.gd`; `wide_lane.gd`; `high_slot.gd` (`BAND_*`); `flank.gd`; `forecheck.gd` (`F3_WALL_INSET_M`, `F2_*`); `defenseman.gd` (`POINT_*`, `DP_*`, `DVALVE_*`, `DBACK_*`, `RIM_KEEPIN_WALL_INSET_M`, `PINCH_MAX_DEPTH_M`); `track.gd` (`MID_LANE_SPLIT_M`, `CIRCLE_TOP_INSET_M`, `HIP_GOAL_SIDE_M`); `rush_d.gd` (`GAP_*_STICKS`, `D2_*`, `RUSH_LANE_FAN_FRACTIONS`, `LANE_PLAY_DANGER_BAR`); `defensive_verbs.gd` (`ANGLE_INSIDE_M`), `last_man_discipline.gd` (`BEHIND_HOLD_EXTRA_M`, `PLAY_CONNECTION_FLIGHT_S`), `role_reads.gd` (`DEFENSIVE_ANTICIPATION_*`).
- **Stability margins** — `role_slots.gd:HYSTERESIS_PENALTY_S/_M`; `role_slots_5v5.gd:POSITION_BIAS_S`; `team_brain.gd:STRONG_SIDE_HYSTERESIS_M`; `possession_state.gd:COVERAGE_HOLD_TICKS`; `rush_read.gd:TRACK_*_MARGIN_S`; `threat_assignment.gd:HYSTERESIS_MARGIN_FRAC`; `zone_coverage.gd:AREA_RELEASE_MARGIN_M`; `loose_puck_chase.gd:HYSTERESIS_S`; `station_search.gd:TARGET_SWITCH_MARGIN`; `action_scoring.gd:ACTION_HYSTERESIS_MARGIN_FRAC`; SM `FACE_*_HYSTERESIS_M`, `CARRY_MAN_TO_BEAT_HYSTERESIS_M`.
- **Cadence / search budget** — `team_brain.gd:TICK_PERIOD`; SM `DISPATCH_PERIOD_TICKS`, `ROLE_DECISION_PERIOD_TICKS`, `FAR_PLAY_LOD_RADIUS_M`, `FINISHER_FLIGHT_NEAR_M`; `carrier.gd:PICK_ACTION_PERIOD_TICKS`, `OPEN_ICE_LOD_*`, `CARRY_BEAM_WIDTH`, `EXPOSURE_PROB_FLOOR`; `station_search.gd:SEARCH_STEP_M`, `POLAR_ANGLES`, `STATION_ARGMAX_LOD_M`, `ANTI_CROWD_RADIUS_M`.
- **Carrier tactics** — `carrier.gd`: `PING_*_EV_MULT`, `PASS_OPTION_DISCOUNT`, `RIM_SOFT_SHARE`, `EXPOSURE_APPETITE_*`, `RECEIVER_DRIVE_*`, `OUTLET_DEVELOP_*`, the rolled moves (`carry_rollout.gd`: `HORIZON_S`, `SOFT_TURN_RAD`, `HARD_TURN_RAD`, `STEP_TICKS`), the destination menu's geometry (`carrier_destinations.gd`: `WIDE_*`, `REGROUP_*`, `EXIT_*`, `WALKOUT_*`, `WHEEL_*`), `PASS_LEAD_MAX_S`, `RIM_AIM_STANDOFF_M`.
- **Execution windows** — SM: `ONE_TIMER_*`, `BOT_WRISTER_*`, `INTENT_MAX_WAIT_TICKS`, `ENGAGEMENT_*`, `STICKHANDLE_*`, `CARRY_PROTECT_*`, `CARRY_BEHIND_NET_*`, `PROTECT_TURN_*`, `OWN_NET_BLADE_DISCIPLINE_M`, `READY_STANCE_AIM_FORWARD_M`, `FACE_THREAT_*`; `skater_agent_stick_play.gd` `POKE_JAB_*`, `STICK_LIFT_HOLD_TICKS`; `skater_agent_board_play.gd` `PIN_*`; `skater_agent_steering.gd:SHOT_LANE_LEAD_TIME_S`; `skater_agent_reception.gd` `RECEIVE_*`, `ONE_TIME_*`, `SHOT_RECEPTION_SCORE_GATE`, `WALL_KILL_BAND_M`, `BODY_WALL_MARGIN_M`; `skater_agent_one_timer.gd` `ONE_TIMER_*`, `BOT_ONE_TIMER_ZONE_OFFSET_*`; `bot_mechanics.gd`.
- **Steering field** — `steering.gd`: `*_REPEL_*`, `NET_DETOUR_*`, `ANCHOR_DEADBAND`, `BRAKE_PIVOT_*`, `STANCE_*`, `ARRIVAL_BRAKE_*`, `OFFSIDE_BRAKE_*`.
- **Faceoff draw** — `ai_controller.gd`: `bot_draw_*`.

---

## 8. Adding a bot feature — checklist

Size first: `skater_agent_state_machine.gd` and `carrier.gd` are already past `test_no_god_class_growth.gd`'s 800-line limit, so prefer extracting a collaborator to growing them; a new file must stay under it, and the receiver's side of a feed is its own leaf (`feed_reception.gd`) so `puck_lane.gd` stays under it.

**New carrier action**
1. Model it in a leaf or one evaluator (`action_scoring.gd` / `carry_space.gd`), never both directions (`test_scoring_split_stays_acyclic.gd`); calibration test in `test_ai_action_scoring.gd`.
2. Price in the xG seam with `AICarrierField.turnover_cost` (+ `counter_exposure_cost` in 5v5) — [one currency](CLAUDE.md#one-currency-across-the-carriers-compete).
3. A search over candidates is its own collaborator beside the others (pattern `carrier_pass_search.gd`): `class_name AICarrier<X>Search`, the field at construction, results in named fields, its own scratch; reads the field, never writes its lists, never names `AIRoleCarrier` (`test_carrier_collaborator_seams.gd`). Shared perception or valuation it needs goes on `AICarrierField`, filled in `fill` / `fill_receivers`.
4. `carrier.gd`: `INTENT_*` const; hold the search as `var _x := AICarrier<X>Search.new(_field)`; score in `_pick_fire_phase` into a `_phase_*` field (survives slicing); qualify against its own bar and add hysteresis in `_pick_commit_phase`; public result fields zeroed in `reset()` and `clear_intent()`.
5. SM: `_state_from_carrier_intent` (+ `test_state_from_carrier_intent_maps_every_intent`); mirror/freeze in `_state_carry`; `_aim_target_for_intent`; a new press state also needs the `is_press_state` list in `dispatch` and sampling in `_set_state`.
6. Tests: `test_role_carrier.gd` (outcomes that are tuning go in its snapshot), `test_skater_agent_state_machine.gd`.

**New role (behaviour for a slot)**
1. `role_behaviors/<role>.gd` with `static func decide(ctx: RoleContext) -> RoleDecision`, composed from the shared blocks: the verbs in `defensive_verbs.gd` (`cover_threat`, `read_carrier_approach` + `carrier_stand`, `chase_puck`, `carrier_best_option`), stations through `last_man_discipline.gd` (`offensive_station_target` / `neutral_station_target`), the candidate argmax through `station_search.gd` (`generate_candidates_around`, `incumbent_bonus`), context through `role_reads.gd`; publish `target_velocity` only for a real stand.
2. New input → `RoleContext` var + stamp it in `_build_role_context` (every build, both brain/no-brain branches). New output → `RoleDecision` var + consumer in `_state_off_puck`.
3. No `Scripts/ai/` class names in domain (`test_bot_domain_does_not_reach_up.gd`); no allocation per call beyond the existing `RoleDecision`.
4. Test: `tests/unit/rules/test_role_<role>.gd`.

**New slot**
1. `role_slots.gd:Slot` value + `_SLOT_INFO` row (`test_every_slot_has_its_facts`).
2. Election: 3v3 arm in `role_slots.gd:assign`; 5v5 `SlotSpec` in `role_slots_5v5.gd:_specs_for_state` (priority position, group, `home_slot`, `lateral_race` / `deadline_s`).
3. Continuity: both `_hysteresis_class` functions.
4. `_dispatch_role_decision` arm — **nothing fails if missing** (falls to hold).
5. If it covers a man / is a zone area: `role_slots_5v5.gd:is_zone_slot`, `team_brain.gd:_compute_threat_assignments`, `zone_coverage.gd:in_area`/`anchor_of`/`pressure_owner`, SM `_is_reactive_slot` and `_is_puck_pressurer_slot`.
6. If the carrier should wait for it: `carrier_pass_search.gd:developing_feed_value`. If a ping forces it: `ping_directives.gd:apply_overrides`.
7. Tests: `test_role_slots.gd` / `test_role_slots_5v5.gd`.

**New agent behaviour**
1. Self-contained job → `Scripts/ai/skater_agent_<x>.gd` (`setup(identity)`, knobs per call, owns only its fields), held as `var _x := SkaterAgentX.new()` (the regex in `test_agent_collaborator_seams.gd`); never names the SM; SM never writes its fields.
2. Per-tick override → `apply_<x>` on the SM, called from `skater_agent.gd:tick` after `dispatch`; may read only throttle-cached state.
3. New state → the four steps in [How an agent is put together](../../ai/CLAUDE.md#how-an-agent-is-put-together) + entry resets in `_set_state`; tick counters advance by `_dispatch_period_ticks`; a blade target that must track goes in the skipped-tick branch of `dispatch` / `_off_puck_live_aim`.
4. Pure read → `Scripts/domain/ai/<x>_read.gd` + test (pattern: `shot_block_read.gd`).
5. New `InputState` field → reset in `skater_agent.gd:zero_input`.

**New team-level read**
Pure, refilled-in-place domain class (pattern `rush_read.gd`) → fill in `team_brain.gd:_compute_tick` → `team_strategy_view.gd` method + `TeamBrainView` field + `build_view` freeze (`test_team_brain_view.gd`) → `RoleContext`. Host-raised writes go through an `ai_coordinator.gd` queue (`_drain_brain_commands`); main-thread readers through `_publish_brain_mirrors`.

**New difficulty knob**
1. `bot_skill_profile.gd`: field + `_init` param + `hard()` / `normal()` / `easy()`; pick an axis; a cognition gate may only remove an input or an option.
2. SM field + `apply_profile`; for roles also `RoleContext` + `_build_role_context`; collaborators take it per call; team-wide only via `GameManager`.
3. Tick-denominated windows scale with `_dispatch_period_ticks`.
4. `test_bot_skill_profile.gd`: softening ladder, Normal == Hard on gates, Easy closed.
