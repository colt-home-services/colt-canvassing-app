-- Track manager edits to a shift's self-reported sign-up count separately from
-- time edits (edited_at). Keeping a distinct timestamp lets the shifts table
-- show an independent "sign-ups edited" indicator with its own edit time,
-- without coupling it to the clock-in/out edit flag.
-- Constant-default (NULL) add = metadata-only, no table rewrite on PG 11+.
ALTER TABLE public.shifts
  ADD COLUMN IF NOT EXISTS signups_edited_at timestamptz;

-- Re-create v_shifts_detail with signups_edited_at exposed so the manager
-- shifts table can read it (full current definition + s.signups_edited_at).
CREATE OR REPLACE VIEW public.v_shifts_detail AS
SELECT s.id,
    s.user_id,
    u.email AS user_email,
    s.clock_in_at,
    s.clock_out_at,
    EXTRACT(epoch FROM COALESCE(s.clock_out_at, now()) - s.clock_in_at)::bigint AS duration_seconds,
    s.clock_in_lat,
    s.clock_in_lon,
    s.clock_in_accuracy_m,
    s.clock_out_lat,
    s.clock_out_lon,
    s.clock_out_accuracy_m,
    s.edited_by,
    s.edited_at,
    s.notes,
    s.auto_closed,
    s.disallowed_at,
    s.disallowed_by,
    (s.clock_in_at AT TIME ZONE 'America/New_York'::text)::date AS work_date_ny,
    s.is_bonus,
    s.self_reported_signups,
    s.signups_edited_at
   FROM shifts s
     LEFT JOIN auth.users u ON u.id = s.user_id;
