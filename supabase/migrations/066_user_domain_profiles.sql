-- 066: user_domain_profiles — 每域预计算画像(投影,可随时重算)
-- 架构:事实层 L1。增量/夜间/回填共用同一 rebuild 函数,消灭双逻辑漂移。
-- 详见 docs/profile-schema-v1.md

create table if not exists public.user_domain_profiles (
  user_id         uuid not null references auth.users(id) on delete cascade,
  domain_key      text not null check (domain_key in
    ('expense','sleep','sport','food','reading','wallet')),
  profile_version int  not null default 1,
  profile         jsonb not null default '{}'::jsonb,
  source_count    int  not null default 0,
  computed_at     timestamptz not null default now(),
  primary key (user_id, domain_key)
);

alter table public.user_domain_profiles enable row level security;

-- 仅本人可读(前端未来可用画像做展示);写入只走 service_role 的 rebuild 函数
drop policy if exists user_domain_profiles_read on public.user_domain_profiles;
create policy user_domain_profiles_read on public.user_domain_profiles
  for select using (auth.uid() = user_id);

-- ============================================================
-- expense 画像 v1
-- 口径:自然周=周一起算(Asia/Shanghai);近30天=滚动窗口
-- ============================================================
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
      -- category 归一化:线上存在 '餐饮' 等中文脏值
      case
        when category in ('food','餐饮','美食') then 'food'
        when category is null or category = '' then 'other'
        else category
      end as category_norm,
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
      -- 准入:近30天≥2次 或 近14天出现过
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
        count(*) filter (where b.transaction_date >= (select week_start from tz_now))                as week_count,
        count(*) filter (where b.transaction_date >= (select today from tz_now) - 29)                as month_count,
        round(coalesce(sum(b.amount) filter
          (where b.transaction_date >= (select week_start from tz_now)), 0)::numeric, 2)             as week_total,
        round((percentile_cont(0.5) within group (order by b.amount))::numeric,2) as median_amount,
        round((percentile_cont(0.9) within group (order by b.amount))::numeric,2) as p90_amount
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
      -- 上周同期:上周一 .. 上周同星期几(同跨度对比才公平)
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

-- ============================================================
-- sleep 画像 v1
-- 口径:按"夜"去重(同夜多条取 occurred_at 最新);夜=occurred_at 的上海日期
-- ============================================================
create or replace function public.rebuild_sleep_profile(p_user_id uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with nights as (
    select distinct on ((occurred_at at time zone 'Asia/Shanghai')::date)
      (occurred_at at time zone 'Asia/Shanghai')::date as night,
      nullif(payload_jsonb->>'sleep_hours','')::numeric  as hours,
      nullif(payload_jsonb->>'quality_score','')::numeric as score,
      nullif(payload_jsonb->>'sleep_start_at','')        as sleep_start_raw
    from public.data_records
    where user_id = p_user_id
      and domain_key = 'sleep'
      and occurred_at >= now() - interval '30 days'
    order by (occurred_at at time zone 'Asia/Shanghai')::date, occurred_at desc
  ),
  valid as (select * from nights where hours is not null),
  baseline as (
    select jsonb_build_object(
      'n', count(*),
      'median_hours', round((percentile_cont(0.5) within group (order by hours))::numeric, 2),
      'p25',          round((percentile_cont(0.25) within group (order by hours))::numeric, 2),
      'p75',          round((percentile_cont(0.75) within group (order by hours))::numeric, 2),
      'mean_score',   round(avg(score)::numeric, 0),
      'window_days',  30
    ) as j
    from valid
  ),
  -- 作息型:入睡时刻跨午夜 → +12h 平移后取平均再还原,避免 23:30 与 00:30 平均成 12:00
  chrono as (
    select jsonb_build_object(
      'typical_sleep_start', to_char(
        (avg(shifted) - interval '12 hours')::time, 'HH24:MI'),
      'type', case
        when (avg(shifted) - interval '12 hours')::time >= time '00:00'
         and (avg(shifted) - interval '12 hours')::time <  time '06:00' then 'night_owl'
        when (avg(shifted) - interval '12 hours')::time <= time '22:30'
         and (avg(shifted) - interval '12 hours')::time >= time '18:00' then 'early_bird'
        else 'regular' end,
      'n', count(*)
    ) as j
    from (
      select ((sleep_start_raw::timestamptz at time zone 'Asia/Shanghai')::time
              + interval '12 hours') as shifted
      from valid
      where sleep_start_raw is not null
        and sleep_start_raw ~ '^\d{4}-'   -- 仅接受 ISO 格式,脏值跳过
    ) s
  ),
  recent as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'night', night, 'hours', hours, 'score', score
    ) order by night desc), '[]'::jsonb) as j
    from (select * from valid order by night desc limit 3) r
  ),
  cov as (
    select jsonb_build_object('nights_last7',
      count(*) filter (where night >= (now() at time zone 'Asia/Shanghai')::date - 6)
    ) as j from valid
  )
  select jsonb_build_object(
    'v', 1,
    'baseline',      (select j from baseline),
    'chronotype',    coalesce((select j from chrono), jsonb_build_object('type','unknown','n',0)),
    'recent_nights', (select j from recent),
    'coverage',      (select j from cov)
  );
$$;

-- ============================================================
-- 分发器:EF 归档后 fire-and-forget 调用;夜间 cron 也走这里
-- ============================================================
create or replace function public.refresh_domain_profile(p_user_id uuid, p_domain_key text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_profile jsonb;
  v_count   int;
  v_version int := 1;
begin
  if p_domain_key = 'expense' then
    v_profile := public.rebuild_expense_profile(p_user_id);
    select count(*) into v_count from public.transactions
      where user_id = p_user_id and type = 'expense'
        and transaction_date >= (now() at time zone 'Asia/Shanghai')::date - 90;
  elsif p_domain_key = 'sleep' then
    v_profile := public.rebuild_sleep_profile(p_user_id);
    select count(*) into v_count from public.data_records
      where user_id = p_user_id and domain_key = 'sleep'
        and occurred_at >= now() - interval '30 days';
  else
    return; -- sport/food/reading/wallet 在 067 补齐
  end if;

  insert into public.user_domain_profiles
    (user_id, domain_key, profile_version, profile, source_count, computed_at)
  values (p_user_id, p_domain_key, v_version, v_profile, coalesce(v_count,0), now())
  on conflict (user_id, domain_key) do update set
    profile_version = excluded.profile_version,
    profile         = excluded.profile,
    source_count    = excluded.source_count,
    computed_at     = excluded.computed_at;
end;
$$;

-- 权限:与 get_companion_context 同策略,仅 service_role 可执行
revoke execute on function public.rebuild_expense_profile(uuid) from anon, authenticated;
revoke execute on function public.rebuild_sleep_profile(uuid) from anon, authenticated;
revoke execute on function public.refresh_domain_profile(uuid, text) from anon, authenticated;
grant execute on function public.rebuild_expense_profile(uuid) to service_role;
grant execute on function public.rebuild_sleep_profile(uuid) to service_role;
grant execute on function public.refresh_domain_profile(uuid, text) to service_role;
