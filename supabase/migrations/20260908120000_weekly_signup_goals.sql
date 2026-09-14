CREATE TABLE IF NOT EXISTS public.weekly_signup_goals (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week_start_ny date NOT NULL,
  goal_signups integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  CONSTRAINT weekly_signup_goals_goal_nonneg CHECK (goal_signups >= 0),
  CONSTRAINT weekly_signup_goals_week_is_monday
    CHECK (EXTRACT(isodow FROM week_start_ny) = 1),
  PRIMARY KEY (user_id, week_start_ny)
);

CREATE OR REPLACE FUNCTION public.touch_weekly_signup_goal()
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
  ON public.weekly_signup_goals;
CREATE TRIGGER trg_touch_weekly_signup_goal
  BEFORE INSERT OR UPDATE ON public.weekly_signup_goals
  FOR EACH ROW EXECUTE FUNCTION public.touch_weekly_signup_goal();

ALTER TABLE public.weekly_signup_goals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "weekly goals readable by owner or managers"
  ON public.weekly_signup_goals;
CREATE POLICY "weekly goals readable by owner or managers"
  ON public.weekly_signup_goals
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

DROP POLICY IF EXISTS "weekly goals insertable by managers"
  ON public.weekly_signup_goals;
CREATE POLICY "weekly goals insertable by managers"
  ON public.weekly_signup_goals
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  );

DROP POLICY IF EXISTS "weekly goals updatable by managers"
  ON public.weekly_signup_goals;
CREATE POLICY "weekly goals updatable by managers"
  ON public.weekly_signup_goals
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

GRANT SELECT, INSERT, UPDATE ON public.weekly_signup_goals TO authenticated;
