CREATE TABLE IF NOT EXISTS public.canvasser_daily_metric_overrides (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  work_date_ny date NOT NULL,
  total_knocks integer,
  signed_ups integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id),
  CONSTRAINT canvasser_daily_metric_overrides_total_knocks_nonneg
    CHECK (total_knocks IS NULL OR total_knocks >= 0),
  CONSTRAINT canvasser_daily_metric_overrides_signed_ups_nonneg
    CHECK (signed_ups IS NULL OR signed_ups >= 0),
  CONSTRAINT canvasser_daily_metric_overrides_has_value
    CHECK (total_knocks IS NOT NULL OR signed_ups IS NOT NULL),
  PRIMARY KEY (user_id, work_date_ny)
);

CREATE OR REPLACE FUNCTION public.touch_canvasser_daily_metric_override()
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
  ON public.canvasser_daily_metric_overrides;
CREATE TRIGGER trg_touch_canvasser_daily_metric_override
  BEFORE INSERT OR UPDATE ON public.canvasser_daily_metric_overrides
  FOR EACH ROW EXECUTE FUNCTION public.touch_canvasser_daily_metric_override();

ALTER TABLE public.canvasser_daily_metric_overrides ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "daily metric overrides readable by owner or managers"
  ON public.canvasser_daily_metric_overrides;
CREATE POLICY "daily metric overrides readable by owner or managers"
  ON public.canvasser_daily_metric_overrides
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

CREATE OR REPLACE FUNCTION public.manager_set_daily_metric_override(
  p_user_id uuid,
  p_work_date_ny date,
  p_total_knocks integer DEFAULT NULL::integer,
  p_signed_ups integer DEFAULT NULL::integer)
RETURNS public.canvasser_daily_metric_overrides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_is_manager boolean;
  v_existing public.canvasser_daily_metric_overrides;
  v_override public.canvasser_daily_metric_overrides;
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
  FROM public.canvasser_daily_metric_overrides
  WHERE user_id = p_user_id
    AND work_date_ny = p_work_date_ny;

  INSERT INTO public.canvasser_daily_metric_overrides (
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
    total_knocks = COALESCE(p_total_knocks, canvasser_daily_metric_overrides.total_knocks),
    signed_ups = COALESCE(p_signed_ups, canvasser_daily_metric_overrides.signed_ups)
  RETURNING * INTO v_override;

  RETURN v_override;
END;
$function$;

GRANT SELECT ON public.canvasser_daily_metric_overrides TO authenticated;
GRANT EXECUTE ON FUNCTION public.manager_set_daily_metric_override(uuid, date, integer, integer)
  TO authenticated;
