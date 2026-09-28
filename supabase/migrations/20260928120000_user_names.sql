ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name text;

CREATE OR REPLACE FUNCTION public.save_my_name(
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
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF nullif(trim(p_first_name), '') IS NULL
     OR nullif(trim(p_last_name), '') IS NULL THEN
    RAISE EXCEPTION 'first and last name are required';
  END IF;

  UPDATE public.profiles
  SET first_name = trim(p_first_name), last_name = trim(p_last_name)
  WHERE user_id = v_actor;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile not found';
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.save_my_name(text, text) TO authenticated;

DROP FUNCTION public.manager_list_canvassers();

CREATE OR REPLACE FUNCTION public.manager_list_canvassers()
RETURNS TABLE(user_id uuid, user_email text, first_name text, last_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_is_manager boolean;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.user_id = v_actor AND p.role = 'manager'
  ) INTO v_is_manager;

  IF NOT v_is_manager THEN
    RAISE EXCEPTION 'manager role required';
  END IF;

  RETURN QUERY
  SELECT p.user_id, u.email::text, p.first_name, p.last_name
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.user_id
  WHERE p.role = 'canvasser' AND u.email IS NOT NULL
  ORDER BY p.last_name NULLS LAST, p.first_name NULLS LAST, u.email;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.manager_list_canvassers() TO authenticated;
