-- Flag distinguishing generated bonus shifts from real store shifts.
-- Instant, metadata-only on Postgres 11+ (constant default = no table rewrite).
ALTER TABLE public.shifts
  ADD COLUMN IF NOT EXISTS is_bonus boolean NOT NULL DEFAULT false;

-- At most one bonus shift per canvasser per NY calendar day.
-- This is the conflict target that makes generate_bonus_shifts idempotent.
-- CONCURRENTLY = no write-lock on shifts while building (safe with live shifts).
-- NOTE: CREATE INDEX CONCURRENTLY cannot run inside a transaction block —
-- run it as its own statement, separate from the ALTER above.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS shifts_one_bonus_per_day
  ON public.shifts (user_id, ((clock_in_at AT TIME ZONE 'America/New_York')::date))
  WHERE is_bonus;
