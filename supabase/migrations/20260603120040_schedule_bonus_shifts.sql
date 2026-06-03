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

SELECT cron.schedule(
  'nightly-bonus-shifts',
  '0 6 * * *',  -- 06:00 UTC daily
  $job$
  SELECT public.generate_bonus_shifts(d::date)
  FROM generate_series(
    (now() AT TIME ZONE 'America/New_York')::date - 13,
    (now() AT TIME ZONE 'America/New_York')::date,
    interval '1 day'
  ) AS d;
  $job$
);
