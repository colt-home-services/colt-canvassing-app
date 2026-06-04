-- Verification queries for self-reported sign-ups. Run manually in the Supabase
-- SQL editor (no local DB harness). Each should return zero "bad" rows.

-- 1. The non-negative CHECK constraint exists.
select 'missing_check_constraint' as problem
where not exists (
  select 1 from pg_constraint
  where conname = 'shifts_self_reported_signups_nonneg'
);

-- 2. No stored value violates the constraint (defensive; CHECK enforces it).
select id, self_reported_signups
from public.shifts
where self_reported_signups is not null and self_reported_signups < 0;

-- 3. The view exposes the column.
select 'view_missing_column' as problem
where not exists (
  select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'v_shifts_detail'
    and column_name = 'self_reported_signups'
);

-- 4. clock_out has the 4-arg signature including p_signups.
select 'clock_out_missing_p_signups' as problem
where pg_get_function_identity_arguments('public.clock_out'::regproc)
  not like '%p_signups integer%';
