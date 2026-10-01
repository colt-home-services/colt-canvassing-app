ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS manager_first_name text,
  ADD COLUMN IF NOT EXISTS manager_last_name text;

DROP FUNCTION IF EXISTS public.manager_list_canvassers();

CREATE FUNCTION public.manager_list_canvassers()
RETURNS TABLE(user_id uuid, user_email text, first_name text, last_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.user_id = v_actor AND p.role = 'manager'
  ) THEN
    RAISE EXCEPTION 'manager role required';
  END IF;

  RETURN QUERY
  SELECT p.user_id, u.email::text,
         COALESCE(NULLIF(trim(p.manager_first_name), ''), p.first_name),
         COALESCE(NULLIF(trim(p.manager_last_name), ''), p.last_name)
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.user_id
  WHERE p.role = 'canvasser' AND u.email IS NOT NULL
  ORDER BY COALESCE(p.manager_last_name, p.last_name),
           COALESCE(p.manager_first_name, p.first_name), u.email;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.manager_list_canvassers() TO authenticated;

CREATE OR REPLACE FUNCTION public.manager_set_canvasser_name(
  p_user_id uuid,
  p_first_name text,
  p_last_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_first text := nullif(trim(p_first_name), '');
  v_last text := nullif(trim(p_last_name), '');
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.user_id = v_actor AND p.role = 'manager'
  ) THEN
    RAISE EXCEPTION 'manager role required';
  END IF;
  IF v_first IS NULL OR v_last IS NULL THEN
    RAISE EXCEPTION 'first and last name are required';
  END IF;

  UPDATE public.profiles
  SET manager_first_name = v_first, manager_last_name = v_last
  WHERE user_id = p_user_id AND role = 'canvasser';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'canvasser profile not found';
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.manager_set_canvasser_name(uuid, text, text) TO authenticated;
