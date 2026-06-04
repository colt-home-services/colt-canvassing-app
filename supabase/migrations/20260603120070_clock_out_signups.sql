-- Extend clock_out to record the canvasser's self-reported sign-up count.
-- Drop the old 3-arg signature first so PostgREST has a single, unambiguous
-- clock_out to resolve and every caller is forced onto the new signature.
DROP FUNCTION IF EXISTS public.clock_out(double precision, double precision, double precision);

CREATE OR REPLACE FUNCTION public.clock_out(
  p_lat double precision DEFAULT NULL::double precision,
  p_lon double precision DEFAULT NULL::double precision,
  p_accuracy_m double precision DEFAULT NULL::double precision,
  p_signups integer DEFAULT NULL::integer)
 RETURNS shifts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_shift public.shifts;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  update public.shifts
    set clock_out_at = now(),
        clock_out_lat = p_lat,
        clock_out_lon = p_lon,
        clock_out_accuracy_m = p_accuracy_m,
        self_reported_signups = p_signups
    where user_id = v_user and clock_out_at is null
    returning * into v_shift;

  return v_shift;
end;
$function$;
