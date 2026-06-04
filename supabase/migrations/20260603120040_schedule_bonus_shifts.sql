-- Nightly job: re-converge the last 14 NY days so a missed run is caught the
-- next night and late knock edits self-correct. Re-running is a no-op.
-- Requires the pg_cron extension (enabled separately).

-- Unschedule first so this file is safe to re-apply.
DO $do$
BEGIN
  PERFORM cron.unschedule('nightly-bonus-shifts');
EXCEPTION WHEN OTHERS THEN
  NULL; -- job did not exist yet
END $do$;

-- NOTE: iterate integer day-offsets, NOT generate_series over date bounds.
-- generate_series(date, date, interval) resolves via timestamptz and can skip
-- calendar days depending on session timezone, leaving days unprocessed.
SELECT cron.schedule(
  'nightly-bonus-shifts',
  '0 6 * * *',  -- 06:00 UTC daily (~1-2 AM Eastern)
  $job$
  SELECT public.generate_bonus_shifts((now() AT TIME ZONE 'America/New_York')::date - g)
  FROM generate_series(0, 13) AS g;
  $job$
);
