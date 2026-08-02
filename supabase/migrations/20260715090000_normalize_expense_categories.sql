-- 支出分类统一为稳定英文编码；历史交易保留原值，在画像读取时兼容归一。
create or replace function public.normalize_expense_category(p_category text)
returns text
language sql
immutable
parallel safe
as $$
  select case lower(btrim(coalesce(p_category, '')))
    when 'food' then 'food'
    when '餐饮' then 'food'
    when '美食' then 'food'
    when '餐厅' then 'food'
    when 'shopping' then 'shopping'
    when '购物' then 'shopping'
    when '网购' then 'shopping'
    when 'transport' then 'transport'
    when 'transportation' then 'transport'
    when '出行' then 'transport'
    when '交通' then 'transport'
    when '打车' then 'transport'
    when 'entertainment' then 'entertainment'
    when '娱乐' then 'entertainment'
    when '休闲' then 'entertainment'
    when 'life' then 'life'
    when 'living' then 'life'
    when 'housing' then 'life'
    when 'rent' then 'life'
    when '生活' then 'life'
    when '日用' then 'life'
    when '缴费' then 'life'
    when 'health' then 'health'
    when 'medical' then 'health'
    when 'healthcare' then 'health'
    when '健康' then 'health'
    when '医疗' then 'health'
    when '药品' then 'health'
    when 'education' then 'education'
    when 'learning' then 'education'
    when '教育' then 'education'
    when '学习' then 'education'
    when 'other' then 'other'
    when '其他' then 'other'
    else 'other'
  end;
$$;

create or replace function public.rebuild_expense_profile(p_user_id uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with tz_now as (
    select (now() at time zone 'Asia/Shanghai')::date as today,
           date_trunc('week', now() at time zone 'Asia/Shanghai')::date as week_start
  ),
  base as (
    select
      merchant_name,
      public.normalize_expense_category(category) as category_norm,
      amount, transaction_date, transaction_time
    from public.transactions, tz_now
    where user_id = p_user_id
      and type = 'expense'
      and transaction_date >= tz_now.today - 90
  ),
  merchant_stats as (
    select jsonb_object_agg(merchant_name, jsonb_build_object(
      'week_count',  week_count,
      'month_count', month_count,
      'count_90d',   count_90d,
      'last_visit',  last_visit,
      'avg_amount',  avg_amount
    )) as j
    from (
      select
        b.merchant_name,
        count(*) filter (where b.transaction_date >= (select week_start from tz_now)) as week_count,
        count(*) filter (where b.transaction_date >= (select today from tz_now) - 29) as month_count,
        count(*)                                                        as count_90d,
        max(b.transaction_date)::text                                   as last_visit,
        round(avg(b.amount)::numeric, 2)                                as avg_amount
      from base b
      where b.merchant_name is not null and b.merchant_name <> ''
      group by b.merchant_name
      having count(*) filter (where b.transaction_date >= (select today from tz_now) - 29) >= 2
          or max(b.transaction_date) >= (select today from tz_now) - 13
      order by max(b.transaction_date) desc
      limit 40
    ) m
  ),
  category_stats as (
    select jsonb_object_agg(category_norm, jsonb_build_object(
      'week_count',    week_count,
      'month_count',   month_count,
      'week_total',    week_total,
      'median_amount', median_amount,
      'p90_amount',    p90_amount
    )) as j
    from (
      select
        b.category_norm,
        count(*) filter (where b.transaction_date >= (select week_start from tz_now)) as week_count,
        count(*) filter (where b.transaction_date >= (select today from tz_now) - 29) as month_count,
        round(coalesce(sum(b.amount) filter
          (where b.transaction_date >= (select week_start from tz_now)), 0)::numeric, 2) as week_total,
        round((percentile_cont(0.5) within group (order by b.amount))::numeric, 2) as median_amount,
        round((percentile_cont(0.9) within group (order by b.amount))::numeric, 2) as p90_amount
      from base b
      where b.transaction_date >= (select today from tz_now) - 29
      group by b.category_norm
    ) c
  ),
  week_velocity as (
    select jsonb_build_object(
      'cur_count', count(*) filter (where transaction_date >= t.week_start),
      'cur_total', round(coalesce(sum(amount) filter
        (where transaction_date >= t.week_start), 0)::numeric, 2),
      'prev_count_same_span', count(*) filter (where
        transaction_date >= t.week_start - 7
        and transaction_date <= t.today - 7),
      'prev_total_same_span', round(coalesce(sum(amount) filter (where
        transaction_date >= t.week_start - 7
        and transaction_date <= t.today - 7), 0)::numeric, 2)
    ) as j
    from base, tz_now t
  ),
  today_snap as (
    select jsonb_build_object(
      'count', count(*),
      'total', round(coalesce(sum(amount), 0)::numeric, 2),
      'late_night_count', count(*) filter (where transaction_time >= time '21:00')
    ) as j
    from base, tz_now t
    where transaction_date = t.today
  )
  select jsonb_build_object(
    'v', 1,
    'merchant_stats', coalesce((select j from merchant_stats), '{}'::jsonb),
    'category_stats', coalesce((select j from category_stats), '{}'::jsonb),
    'week_velocity',  (select j from week_velocity),
    'today',          (select j from today_snap)
  );
$$;

-- 只刷新派生画像，不更新 transactions 原始记录。
update public.user_domain_profiles
set profile = public.rebuild_expense_profile(user_id),
    computed_at = now()
where domain_key = 'expense';
