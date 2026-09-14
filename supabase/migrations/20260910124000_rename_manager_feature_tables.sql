DO $$
BEGIN
  IF to_regclass('public.manager_weekly_signup_goals') IS NULL
     AND to_regclass('public.weekly_signup_goals') IS NOT NULL THEN
    ALTER TABLE public.weekly_signup_goals
      RENAME TO manager_weekly_signup_goals;
  END IF;

  IF to_regclass('public.manager_daily_metric_overrides') IS NULL
     AND to_regclass('public.canvasser_daily_metric_overrides') IS NOT NULL THEN
    ALTER TABLE public.canvasser_daily_metric_overrides
      RENAME TO manager_daily_metric_overrides;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.touch_manager_weekly_signup_goal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by = COALESCE(NEW.created_by, auth.uid());
  END IF;
  NEW.updated_at = now();
  NEW.updated_by = auth.uid();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_touch_weekly_signup_goal
  ON public.manager_weekly_signup_goals;
DROP TRIGGER IF EXISTS trg_touch_manager_weekly_signup_goal
  ON public.manager_weekly_signup_goals;
CREATE TRIGGER trg_touch_manager_weekly_signup_goal
  BEFORE INSERT OR UPDATE ON public.manager_weekly_signup_goals
  FOR EACH ROW EXECUTE FUNCTION public.touch_manager_weekly_signup_goal();

DROP POLICY IF EXISTS "weekly goals readable by owner or managers"
  ON public.manager_weekly_signup_goals;
DROP POLICY IF EXISTS "weekly goals insertable by managers"
  ON public.manager_weekly_signup_goals;
DROP POLICY IF EXISTS "weekly goals updatable by managers"
  ON public.manager_weekly_signup_goals;
DROP POLICY IF EXISTS "manager weekly goals readable by owner or managers"
  ON public.manager_weekly_signup_goals;
CREATE POLICY "manager weekly goals readable by owner or managers"
  ON public.manager_weekly_signup_goals
  FOR SELECT
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  );

DROP POLICY IF EXISTS "manager weekly goals insertable by managers"
  ON public.manager_weekly_signup_goals;
CREATE POLICY "manager weekly goals insertable by managers"
  ON public.manager_weekly_signup_goals
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  );

DROP POLICY IF EXISTS "manager weekly goals updatable by managers"
  ON public.manager_weekly_signup_goals;
CREATE POLICY "manager weekly goals updatable by managers"
  ON public.manager_weekly_signup_goals
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  );

CREATE OR REPLACE FUNCTION public.touch_manager_daily_metric_override()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at = now();
  NEW.updated_by = auth.uid();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_touch_canvasser_daily_metric_override
  ON public.manager_daily_metric_overrides;
DROP TRIGGER IF EXISTS trg_touch_manager_daily_metric_override
  ON public.manager_daily_metric_overrides;
CREATE TRIGGER trg_touch_manager_daily_metric_override
  BEFORE INSERT OR UPDATE ON public.manager_daily_metric_overrides
  FOR EACH ROW EXECUTE FUNCTION public.touch_manager_daily_metric_override();

DROP POLICY IF EXISTS "daily metric overrides readable by owner or managers"
  ON public.manager_daily_metric_overrides;
DROP POLICY IF EXISTS "manager daily metric overrides readable by owner or managers"
  ON public.manager_daily_metric_overrides;
CREATE POLICY "manager daily metric overrides readable by owner or managers"
  ON public.manager_daily_metric_overrides
  FOR SELECT
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  );

DROP FUNCTION IF EXISTS public.manager_set_daily_metric_override(
  uuid,
  date,
  integer,
  integer);
CREATE OR REPLACE FUNCTION public.manager_set_daily_metric_override(
  p_user_id uuid,
  p_work_date_ny date,
  p_total_knocks integer DEFAULT NULL::integer,
  p_signed_ups integer DEFAULT NULL::integer)
RETURNS public.manager_daily_metric_overrides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_is_manager boolean;
  v_existing public.manager_daily_metric_overrides;
  v_override public.manager_daily_metric_overrides;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.user_id = v_actor
      AND p.role = 'manager'
  ) INTO v_is_manager;

  IF NOT v_is_manager THEN
    RAISE EXCEPTION 'manager role required';
  END IF;

  IF p_user_id IS NULL OR p_work_date_ny IS NULL THEN
    RAISE EXCEPTION 'user_id and work_date_ny are required';
  END IF;

  IF p_total_knocks IS NULL AND p_signed_ups IS NULL THEN
    RAISE EXCEPTION 'an override value is required';
  END IF;

  IF p_total_knocks IS NOT NULL AND p_total_knocks < 0 THEN
    RAISE EXCEPTION 'total_knocks must be non-negative';
  END IF;

  IF p_signed_ups IS NOT NULL AND p_signed_ups < 0 THEN
    RAISE EXCEPTION 'signed_ups must be non-negative';
  END IF;

  SELECT * INTO v_existing
  FROM public.manager_daily_metric_overrides
  WHERE user_id = p_user_id
    AND work_date_ny = p_work_date_ny;

  INSERT INTO public.manager_daily_metric_overrides (
    user_id,
    work_date_ny,
    total_knocks,
    signed_ups
  )
  VALUES (
    p_user_id,
    p_work_date_ny,
    COALESCE(p_total_knocks, v_existing.total_knocks),
    COALESCE(p_signed_ups, v_existing.signed_ups)
  )
  ON CONFLICT (user_id, work_date_ny)
  DO UPDATE SET
    total_knocks = COALESCE(
      p_total_knocks,
      manager_daily_metric_overrides.total_knocks
    ),
    signed_ups = COALESCE(
      p_signed_ups,
      manager_daily_metric_overrides.signed_ups
    )
  RETURNING * INTO v_override;

  RETURN v_override;
END;
$function$;

GRANT SELECT, INSERT, UPDATE ON public.manager_weekly_signup_goals
  TO authenticated;
GRANT SELECT ON public.manager_daily_metric_overrides TO authenticated;
GRANT EXECUTE ON FUNCTION public.manager_set_daily_metric_override(
  uuid,
  date,
  integer,
  integer)
TO authenticated;

DROP FUNCTION IF EXISTS public.touch_weekly_signup_goal();
DROP FUNCTION IF EXISTS public.touch_canvasser_daily_metric_override();
