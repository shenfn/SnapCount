-- Drop and recreate daily_domain_summary without SECURITY DEFINER
drop view if exists public.daily_domain_summary;

create view public.daily_domain_summary
with (security_invoker = true)
as
with expense_agg as (
  select
    transaction_date as d,
    user_id,
    sum(amount) as expense_total,
    count(*) as expense_count
  from public.transactions
  where status = 'done' and type = 'expense'
    and user_id = auth.uid()
  group by transaction_date, user_id
),
income_agg as (
  select
    income_date as d,
    user_id,
    sum(amount) as income_total,
    count(*) as income_count
  from public.income_records
  where user_id = auth.uid()
  group by income_date, user_id
),
domain_agg as (
  select
    (occurred_at at time zone 'Asia/Shanghai')::date as d,
    user_id,
    sum(case when domain_key = 'sleep' then
      coalesce(nullif(payload_jsonb->>'sleep_minutes','')::numeric,
               nullif(payload_jsonb->>'sleep_hours','')::numeric * 60, 0)
    else null end) as sleep_minutes,
    avg(case when domain_key = 'sleep' and (payload_jsonb->>'quality_score') is not null
      then nullif(payload_jsonb->>'quality_score','')::numeric
    else null end) as sleep_score_avg,
    count(*) filter (where domain_key = 'sleep') as sleep_count,
    sum(case when domain_key = 'sport' then
      coalesce(nullif(payload_jsonb->>'duration_minutes','')::numeric, 0)
    else null end) as sport_minutes,
    count(*) filter (where domain_key = 'sport') as sport_count,
    sum(case when domain_key = 'reading' then
      coalesce(nullif(payload_jsonb->>'reading_minutes','')::numeric, 0)
    else null end) as reading_minutes,
    count(*) filter (where domain_key = 'reading') as reading_count,
    sum(case when domain_key = 'food' then
      coalesce(nullif(payload_jsonb->>'total_calorie_kcal','')::numeric, 0)
    else null end) as food_calories,
    count(*) filter (where domain_key = 'food') as food_meals
  from public.data_records
  where occurred_at is not null
    and user_id = auth.uid()
  group by (occurred_at at time zone 'Asia/Shanghai')::date, user_id
),
all_keys as (
  select d, user_id from expense_agg
  union
  select d, user_id from income_agg
  union
  select d, user_id from domain_agg
)
select
  k.d as date,
  k.user_id,
  coalesce(e.expense_total, 0) as expense_total,
  coalesce(e.expense_count, 0) as expense_count,
  coalesce(i.income_total, 0) as income_total,
  coalesce(i.income_count, 0) as income_count,
  coalesce(da.sleep_minutes, 0) as sleep_minutes,
  da.sleep_score_avg,
  coalesce(da.sleep_count, 0) as sleep_count,
  coalesce(da.sport_minutes, 0) as sport_minutes,
  coalesce(da.sport_count, 0) as sport_count,
  coalesce(da.reading_minutes, 0) as reading_minutes,
  coalesce(da.reading_count, 0) as reading_count,
  coalesce(da.food_calories, 0) as food_calories,
  coalesce(da.food_meals, 0) as food_meals,
  case
    when (coalesce(e.expense_count,0) + coalesce(i.income_count,0) +
          coalesce(da.sleep_count,0) + coalesce(da.sport_count,0) +
          coalesce(da.reading_count,0) + coalesce(da.food_meals,0)) > 0
    then true else false
  end as has_any_data
from all_keys k
left join expense_agg e on e.d = k.d and e.user_id = k.user_id
left join income_agg i on i.d = k.d and i.user_id = k.user_id
left join domain_agg da on da.d = k.d and da.user_id = k.user_id
order by k.d desc;
