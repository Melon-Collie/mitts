-- One-time data reset: the recorded shots and career stats come from builds the
-- game has since outgrown, so they start over. Schema untouched. The hosted
-- project runs it once (supabase_migrations records it); CI's replay truncates
-- tables that are already empty.

truncate table public.shot_events, public.career_stats restart identity;
