-- shot_events.next_control: who had the puck next after a shot that did not score.
--
-- WHY: docs/possession-value-plan.md prices a shot against the possession it
-- spends, and the price depends on how often the shooting team gets the puck
-- back. No harness can measure that — none models a save, a freeze, or the
-- rebound race followed by the next possession — so it is measured from play.
-- Issue #577 (the rebound put-back value) needs the same data.
--
-- 'ours' / 'theirs': the team of the next ESTABLISHED possession (the game's
-- PossessionTracker, not a mere touch). 'whistle': play stopped first.
-- NULL: a goal (nothing to retain), a row written before this column, or a shot
-- still unresolved when the game's log was posted.
--
-- Idempotent DDL, additive only.

alter table public.shot_events
    add column if not exists next_control text;

alter table public.shot_events drop constraint if exists shot_events_next_control_valid;
alter table public.shot_events add constraint shot_events_next_control_valid check (
    next_control is null or next_control in ('ours', 'theirs', 'whistle')
);
