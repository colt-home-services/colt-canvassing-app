-- Pure mapping from valid knock buckets to bonus-shift minutes.
-- < 8 buckets (<2h)  -> 0
-- 8..23 (2h..6h)     -> 15
-- >= 24 (>=6h)       -> 60 (cap)
CREATE OR REPLACE FUNCTION public.bonus_minutes(p_buckets integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_buckets >= 24 THEN 60
    WHEN p_buckets >= 8  THEN 15
    ELSE 0
  END;
$$;
