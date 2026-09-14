CREATE OR REPLACE FUNCTION public.manager_list_canvassers()
RETURNS TABLE(user_id uuid, user_email text)
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
    SELECT 1
    FROM public.profiles p
    WHERE p.user_id = v_actor
      AND p.role = 'manager'
  ) INTO v_is_manager;

  IF NOT v_is_manager THEN
    RAISE EXCEPTION 'manager role required';
  END IF;

  RETURN QUERY
  SELECT p.user_id, u.email::text AS user_email
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.user_id
  WHERE p.role = 'canvasser'
    AND u.email IS NOT NULL
  ORDER BY u.email;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.manager_list_canvassers() TO authenticated;
