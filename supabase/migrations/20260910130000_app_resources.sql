CREATE TABLE IF NOT EXISTS public.app_resources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  url text NOT NULL,
  description text,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  CONSTRAINT app_resources_title_not_blank CHECK (length(trim(title)) > 0),
  CONSTRAINT app_resources_url_not_blank CHECK (length(trim(url)) > 0),
  CONSTRAINT app_resources_url_http CHECK (url ~* '^https?://')
);

CREATE OR REPLACE FUNCTION public.touch_app_resource()
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

DROP TRIGGER IF EXISTS trg_touch_app_resource ON public.app_resources;
CREATE TRIGGER trg_touch_app_resource
  BEFORE INSERT OR UPDATE ON public.app_resources
  FOR EACH ROW EXECUTE FUNCTION public.touch_app_resource();

ALTER TABLE public.app_resources ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "resources readable by everyone signed in"
  ON public.app_resources;
CREATE POLICY "resources readable by everyone signed in"
  ON public.app_resources
  FOR SELECT
  USING (
    is_active
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  );

DROP POLICY IF EXISTS "resources insertable by managers"
  ON public.app_resources;
CREATE POLICY "resources insertable by managers"
  ON public.app_resources
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  );

DROP POLICY IF EXISTS "resources updatable by managers"
  ON public.app_resources;
CREATE POLICY "resources updatable by managers"
  ON public.app_resources
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

DROP POLICY IF EXISTS "resources deletable by managers"
  ON public.app_resources;
CREATE POLICY "resources deletable by managers"
  ON public.app_resources
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.user_id = auth.uid()
        AND p.role = 'manager'
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_resources TO authenticated;
