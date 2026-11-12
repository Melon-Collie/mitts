-- career_stats: the NHL rule set's penalties (docs/penalties-plan.md).
--   pim        — penalty minutes: two a minor he was assessed or a penalty shot
--                his foul gave up (PlayerStats.pim).
--   pp_goals   — his goals with his team a man up.
--   pp_assists — his assists on a goal scored with his team a man up.
--   sh_goals   — his goals with his team a man down.
-- And his special teams, on the ice: a man in the box is out there for
-- neither, so nobody is credited with killing his own penalty.
--   pp_opportunities / pp_on_ice_goals         — power plays he was on the ice
--                                                for, and his team's goals on
--                                                them with him out there.
--   pk_opportunities / pk_on_ice_goals_against — the same for the kills.
--
-- Rows from before this migration read 0: none of it was recorded for them,
-- and no match outside the NHL rule set records any.

alter table public.career_stats
    add column if not exists pim integer default 0 not null,
    add column if not exists pp_goals integer default 0 not null,
    add column if not exists pp_assists integer default 0 not null,
    add column if not exists sh_goals integer default 0 not null,
    add column if not exists pp_opportunities integer default 0 not null,
    add column if not exists pp_on_ice_goals integer default 0 not null,
    add column if not exists pk_opportunities integer default 0 not null,
    add column if not exists pk_on_ice_goals_against integer default 0 not null;

alter table public.career_stats drop constraint if exists career_stats_penalties_range;
alter table public.career_stats add constraint career_stats_penalties_range check (
    pim between 0 and 1000
    and pp_goals between 0 and 500
    and pp_assists between 0 and 1000
    and sh_goals between 0 and 500
    and pp_opportunities between 0 and 500
    and pp_on_ice_goals between 0 and 500
    and pk_opportunities between 0 and 500
    and pk_on_ice_goals_against between 0 and 500
);

-- career_totals_for() gains the lifetime sums and the two rates. Its return
-- type changes, so the function is dropped and recreated, and the view that
-- delegates to it with it.
drop view if exists public.career_totals;
drop function if exists public.career_totals_for(bigint, integer);

create function public.career_totals_for(player_steam_id bigint,
                                         p_team_size integer default null)
 returns table(
    steam_id bigint, player_name text, games_played bigint,
    goals bigint, assists bigint, points bigint, shots_on_goal bigint,
    hits bigint, shots_blocked bigint, toi_seconds bigint,
    goals_for bigint, goals_against bigint, plus_minus bigint,
    wins bigint, losses bigint,
    goals_per_60 numeric, assists_per_60 numeric, points_per_60 numeric,
    hits_taken bigint, takeaways bigint, interceptions bigint, giveaways bigint,
    faceoff_wins bigint, faceoff_losses bigint, faceoff_pct numeric,
    shot_attempts bigint, fenwick bigint, pdo numeric,
    xg_for numeric, goals_above_expected numeric, xgf_pct numeric,
    pim bigint, pp_goals bigint, pp_points bigint, sh_goals bigint,
    pp_pct numeric, pk_pct numeric)
 language sql
 stable
as $function$
  SELECT cs.steam_id,
    (array_agg(cs.player_name ORDER BY cs.played_at DESC NULLS LAST))[1],
    count(*),
    sum(cs.goals), sum(cs.assists), sum(cs.goals + cs.assists),
    sum(cs.shots_on_goal), sum(cs.hits), sum(cs.shots_blocked),
    sum(cs.toi_seconds), sum(cs.goals_for), sum(cs.goals_against),
    sum(cs.goals_for - cs.goals_against),
    sum(CASE WHEN cs.outcome = 'win'::text  THEN 1 ELSE 0 END),
    sum(CASE WHEN cs.outcome = 'loss'::text THEN 1 ELSE 0 END),
    round(sum(cs.goals)::numeric   / NULLIF(sum(cs.toi_seconds), 0)::numeric * 3600::numeric, 2),
    round(sum(cs.assists)::numeric / NULLIF(sum(cs.toi_seconds), 0)::numeric * 3600::numeric, 2),
    round(sum(cs.goals + cs.assists)::numeric / NULLIF(sum(cs.toi_seconds), 0)::numeric * 3600::numeric, 2),
    sum(cs.hits_taken), sum(cs.takeaways), sum(cs.interceptions), sum(cs.giveaways),
    sum(cs.faceoff_wins), sum(cs.faceoff_losses),
    round(sum(cs.faceoff_wins)::numeric
          / NULLIF(sum(cs.faceoff_wins) + sum(cs.faceoff_losses), 0)::numeric * 100::numeric, 1),
    -- Analytics A1: iCF = shot attempts; Fenwick = attempts − blocked.
    -- PDO = on-ice shooting% + save%, ×1000.
    sum(cs.shot_attempts),
    sum(cs.shot_attempts - cs.shot_attempts_blocked),
    round((
        sum(cs.goals_for)::numeric / NULLIF(sum(cs.team_sog_for), 0)::numeric
      + 1::numeric - sum(cs.goals_against)::numeric / NULLIF(sum(cs.team_sog_against), 0)::numeric
    ) * 1000::numeric, 0),
    -- Analytics A2: ixG; goals − ixG is finishing; xGF% is team chance-share.
    round(sum(cs.xg_for), 2),
    round(sum(cs.goals)::numeric - sum(cs.xg_for), 2),
    round(sum(cs.team_xg_for) / NULLIF(sum(cs.team_xg_for) + sum(cs.team_xg_against), 0) * 100::numeric, 1),
    sum(cs.pim), sum(cs.pp_goals), sum(cs.pp_goals + cs.pp_assists), sum(cs.sh_goals),
    -- On-ice special teams: goals over the power plays he was out for, and one
    -- less the goals against over the kills he was. Null with none on record.
    round(sum(cs.pp_on_ice_goals)::numeric
          / NULLIF(sum(cs.pp_opportunities), 0)::numeric * 100::numeric, 1),
    round((1::numeric - sum(cs.pk_on_ice_goals_against)::numeric
          / NULLIF(sum(cs.pk_opportunities), 0)::numeric) * 100::numeric, 1)
  FROM career_stats cs
  WHERE cs.steam_id = player_steam_id
    AND (p_team_size IS NULL OR cs.team_size = p_team_size)
  GROUP BY cs.steam_id;
$function$;

grant execute on function public.career_totals_for(bigint, integer) to anon;

create view public.career_totals
with (security_invoker = true) as
  SELECT t.*
    FROM (SELECT DISTINCT steam_id FROM career_stats WHERE steam_id IS NOT NULL) s,
         LATERAL public.career_totals_for(s.steam_id, NULL) t;

grant select on public.career_totals to anon;

notify pgrst, 'reload schema';
