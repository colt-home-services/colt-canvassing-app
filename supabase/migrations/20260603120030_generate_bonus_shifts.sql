-- Converge bonus shifts for one NY work date to match current knock data.
-- Idempotent: upsert earners (>=8 buckets), delete non-earners.
-- Only ever touches rows where is_bonus = true.
CREATE OR REPLACE FUNCTION public.generate_bonus_shifts(p_date date) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $genbonus$
BEGIN
  -- Upsert one bonus shift per earning canvasser for p_date.
  -- clock_in_at = 08:00 America/New_York on p_date (stored as UTC instant).
  -- clock_out_at = clock_in_at + tier minutes. Duration is the only meaningful field.
  INSERT INTO public.shifts (user_id, clock_in_at, clock_out_at, is_bonus, auto_closed)
  SELECT
    p.user_id,
    (p_date::text || ' 08:00')::timestamp AT TIME ZONE 'America/New_York',
    ((p_date::text || ' 08:00')::timestamp AT TIME ZONE 'America/New_York')
      + make_interval(mins => public.bonus_minutes(p.valid_buckets::int)),
    true,
    false
  FROM public.v_payroll_daily p
  WHERE p.work_date_ny = p_date
    AND public.bonus_minutes(p.valid_buckets::int) > 0
  ON CONFLICT (user_id, ((clock_in_at AT TIME ZONE 'America/New_York')::date)) WHERE is_bonus
  DO UPDATE SET clock_out_at = EXCLUDED.clock_out_at;

  -- Remove bonus shifts for p_date whose canvasser no longer qualifies.
  DELETE FROM public.shifts s
  WHERE s.is_bonus
    AND (s.clock_in_at AT TIME ZONE 'America/New_York')::date = p_date
    AND NOT EXISTS (
      SELECT 1 FROM public.v_payroll_daily p
      WHERE p.user_id = s.user_id
        AND p.work_date_ny = p_date
        AND public.bonus_minutes(p.valid_buckets::int) > 0
    );
END;
$genbonus$;
