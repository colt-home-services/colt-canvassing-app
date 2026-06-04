-- Self-reported sign-up count entered by the canvasser at clock-out.
-- Nullable: historical shifts, still-open shifts, and auto-closed (forgotten)
-- shifts legitimately have no value. CHECK guards against negatives.
-- Constant-default add = metadata-only, no table rewrite on Postgres 11+.
ALTER TABLE public.shifts
  ADD COLUMN IF NOT EXISTS self_reported_signups int;

ALTER TABLE public.shifts
  DROP CONSTRAINT IF EXISTS shifts_self_reported_signups_nonneg;

ALTER TABLE public.shifts
  ADD CONSTRAINT shifts_self_reported_signups_nonneg
  CHECK (self_reported_signups IS NULL OR self_reported_signups >= 0);
