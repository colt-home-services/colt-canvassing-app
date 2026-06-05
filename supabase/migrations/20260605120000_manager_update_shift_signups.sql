-- Extend manager_update_shift to also override the self-reported sign-up count.
-- Adds p_signups and stamps signups_edited_at only when the count actually
-- changes, so the shifts table can show an independent "sign-ups edited"
-- indicator. edited_at (time edits) and signups_edited_at (sign-up edits) are
-- each now gated on an IS DISTINCT FROM check against the existing row, so a
-- save that touches only one of them lights only that indicator.
--
-- Drop the old 4-arg signature first so adding the 5th param doesn't leave a
-- stale overload for PostgREST to resolve ambiguously.
DROP FUNCTION IF EXISTS public.manager_update_shift(uuid, timestamptz, timestamptz, text);

CREATE OR REPLACE FUNCTION public.manager_update_shift(
  p_shift_id uuid,
  p_clock_in_at timestamptz,
  p_clock_out_at timestamptz,
  p_notes text DEFAULT NULL::text,
  p_signups integer DEFAULT NULL::integer)
 RETURNS shifts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_is_manager boolean;
  v_existing public.shifts;
  v_shift public.shifts;
  v_times_changed boolean;
  v_signups_changed boolean;
begin
  if v_actor is null then
    raise exception 'not authenticated';
  end if;

  select exists (
    select 1 from public.profiles p
    where p.user_id = v_actor and p.role = 'manager'
  ) into v_is_manager;

  if not v_is_manager then
    raise exception 'manager role required';
  end if;

  if p_clock_in_at is null then
    raise exception 'clock_in_at required';
  end if;

  if p_clock_out_at is not null and p_clock_out_at <= p_clock_in_at then
    raise exception 'clock_out_at must be after clock_in_at';
  end if;

  select * into v_existing from public.shifts where id = p_shift_id;
  if not found then
    raise exception 'shift not found';
  end if;

  v_times_changed :=
    v_existing.clock_in_at is distinct from p_clock_in_at
    or v_existing.clock_out_at is distinct from p_clock_out_at;

  -- coalesce: an omitted p_signups must not wipe an existing count.
  v_signups_changed :=
    p_signups is not null
    and v_existing.self_reported_signups is distinct from p_signups;

  update public.shifts
    set clock_in_at = p_clock_in_at,
        clock_out_at = p_clock_out_at,
        notes = coalesce(p_notes, notes),
        self_reported_signups = coalesce(p_signups, self_reported_signups),
        edited_by = v_actor,
        edited_at = case when v_times_changed then now() else edited_at end,
        signups_edited_at =
          case when v_signups_changed then now() else signups_edited_at end,
        auto_closed = case when v_times_changed then false else auto_closed end
    where id = p_shift_id
    returning * into v_shift;

  return v_shift;
end;
$function$;
