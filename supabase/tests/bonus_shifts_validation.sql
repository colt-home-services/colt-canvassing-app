-- Bonus-shift validation queries. Run in the Supabase SQL Editor.

-- ---------------------------------------------------------------------------
-- BACKFILL (one-off). Iterate the ACTUAL distinct qualifying dates.
-- Do NOT use generate_series(date, date, interval) here: with date bounds it
-- resolves via timestamptz and can skip calendar days, leaving days unprocessed.
-- ---------------------------------------------------------------------------
-- SELECT public.generate_bonus_shifts(d)
-- FROM (
--   SELECT DISTINCT work_date_ny AS d
--   FROM v_payroll_daily
--   WHERE valid_buckets >= 8
-- ) x;

-- ---------------------------------------------------------------------------
-- PARITY: the job must flag the SAME (user, day) set as the legacy green-row
-- criterion (valid_buckets >= 8). Expect ZERO rows.
-- (Durations differ by design: legacy was flat 15 min; new adds the 60-min tier.)
-- ---------------------------------------------------------------------------
SELECT 'missing' AS problem, p.user_id, p.work_date_ny
FROM v_payroll_daily p
LEFT JOIN shifts s
  ON s.is_bonus
 AND s.user_id = p.user_id
 AND (s.clock_in_at AT TIME ZONE 'America/New_York')::date = p.work_date_ny
WHERE p.valid_buckets >= 8 AND s.id IS NULL
UNION ALL
SELECT 'extra', s.user_id, (s.clock_in_at AT TIME ZONE 'America/New_York')::date
FROM shifts s
LEFT JOIN v_payroll_daily p
  ON p.user_id = s.user_id
 AND p.work_date_ny = (s.clock_in_at AT TIME ZONE 'America/New_York')::date
 AND p.valid_buckets >= 8
WHERE s.is_bonus AND p.user_id IS NULL;

-- ---------------------------------------------------------------------------
-- TIER CORRECTNESS: every bonus row's duration matches its bucket tier.
-- Expect ZERO rows.
-- ---------------------------------------------------------------------------
SELECT s.user_id,
       (s.clock_in_at AT TIME ZONE 'America/New_York')::date AS ny_date,
       (EXTRACT(epoch FROM s.clock_out_at - s.clock_in_at) / 60)::int AS bonus_min,
       p.valid_buckets
FROM shifts s
JOIN v_payroll_daily p
  ON p.user_id = s.user_id
 AND p.work_date_ny = (s.clock_in_at AT TIME ZONE 'America/New_York')::date
WHERE s.is_bonus
  AND (EXTRACT(epoch FROM s.clock_out_at - s.clock_in_at) / 60)::int
      <> public.bonus_minutes(p.valid_buckets::int);
