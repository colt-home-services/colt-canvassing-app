-- Re-create v_shifts_detail with self_reported_signups exposed so the app can
-- read it (full current definition + s.self_reported_signups).
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
    s.self_reported_signups
   FROM shifts s
     LEFT JOIN auth.users u ON u.id = s.user_id;
