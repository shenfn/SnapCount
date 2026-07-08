-- 067: 补齐 sport/food/reading/wallet 四域画像 rebuild + 扩展分发器
-- 承接 066,口径与演进钩子同 docs/profile-schema-v1.md
-- 线上数据现实约束(2026-07-08 抽查):
--   sport: 存在同一运动重复归档(同 occurred_at 同类型),需去重
--   reading: 存在 manual 测试脏数据,字段可能缺失
--   wallet: 金额优先 snapshot_balance,回退 amount
--   sport.avg_pace: 混合格式 "6.62" / "4'51\"" / "8'55''/公里",需解析,解析不了置 null

-- ============================================================
-- sport 画像 v1
-- ============================================================
create or replace function public.rebuild_sport_profile(p_user_id uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with tz_now as (
    select (now() at time zone 'Asia/Shanghai')::date as today,
           date_trunc('week', now() at time zone 'Asia/Shanghai')::date as week_start
  ),
  -- 按 (发生时刻, 运动类型) 去重:同一条运动可能被归档多次
  sessions as (
    select distinct on (occurred_at, payload_jsonb->>'sport_type')
      occurred_at,
      (occurred_at at time zone 'Asia/Shanghai')::date as d,
      coalesce(nullif(payload_jsonb->>'sport_type',''), '未知') as sport_type,
      nullif(payload_jsonb->>'duration_minutes','')::numeric as duration_min,
      nullif(payload_jsonb->>'distance_km','')::numeric      as distance_km,
      -- avg_pace 线上混合格式:"6.62"(分钟小数) / "4'51""" / "8'55''/公里" → 统一为分钟小数
      case
        when payload_jsonb->>'avg_pace' ~ '^\d+(\.\d+)?$'
          then (payload_jsonb->>'avg_pace')::numeric
        when payload_jsonb->>'avg_pace' ~ '^\d+''\d{1,2}'
          then (substring(payload_jsonb->>'avg_pace' from '^(\d+)'''))::numeric
             + round((substring(payload_jsonb->>'avg_pace' from '^\d+''(\d{1,2})'))::numeric / 60, 4)
        else null
      end as avg_pace,
      nullif(payload_jsonb->>'calories','')::numeric         as calories
    from public.data_records
    where user_id = p_user_id
      and domain_key = 'sport'
      and occurred_at >= now() - interval '90 days'
    order by occurred_at, payload_jsonb->>'sport_type', created_at desc
  ),
  rhythm as (
    select jsonb_build_object(
      'sessions_per_week_4w', round((count(*) filter
        (where d >= (select today from tz_now) - 27))::numeric / 4, 1),
      'minutes_per_week_4w', round(coalesce(sum(duration_min) filter
        (where d >= (select today from tz_now) - 27), 0)::numeric / 4, 0)
    ) as j
    from sessions
  ),
  type_stats as (
    select jsonb_object_agg(sport_type, jsonb_build_object(
      'count_90d', cnt,
      'last_date', last_date,
      'median_duration_min', med_dur,
      'median_distance_km', med_dist,
      'median_pace', med_pace,
      'best_pace', best_pace
    )) as j
    from (
      select sport_type,
        count(*) as cnt,
        max(d)::text as last_date,
        round((percentile_cont(0.5) within group (order by duration_min))::numeric, 0) as med_dur,
        round((percentile_cont(0.5) within group (order by distance_km))::numeric, 1)  as med_dist,
        round((percentile_cont(0.5) within group (order by avg_pace))::numeric, 2)     as med_pace,
        round(min(avg_pace)::numeric, 2)                                               as best_pace
      from sessions
      group by sport_type
    ) t
  ),
  cur_week as (
    select jsonb_build_object(
      'sessions', count(*),
      'minutes', round(coalesce(sum(duration_min), 0)::numeric, 0)
    ) as j
    from sessions
    where d >= (select week_start from tz_now)
  ),
  gap as (
    select ((select today from tz_now) - max(d)) as days from sessions
  )
  select jsonb_build_object(
    'v', 1,
    'weekly_rhythm', (select j from rhythm),
    'type_stats',    coalesce((select j from type_stats), '{}'::jsonb),
    'current_week',  (select j from cur_week),
    'gap_days',      (select days from gap)
  );
$$;

-- ============================================================
-- food 画像 v1
-- ============================================================
create or replace function public.rebuild_food_profile(p_user_id uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with tz_now as (
    select (now() at time zone 'Asia/Shanghai')::date as today
  ),
  meals as (
    select
      (occurred_at at time zone 'Asia/Shanghai')::date as d,
      (occurred_at at time zone 'Asia/Shanghai')::time as t,
      coalesce(nullif(payload_jsonb->>'meal_type',''), 'unknown') as meal_type,
      nullif(payload_jsonb->>'total_calorie_kcal','')::numeric    as kcal,
      payload_jsonb->'dishes' as dishes
    from public.data_records
    where user_id = p_user_id
      and domain_key = 'food'
      and occurred_at >= now() - interval '30 days'
  ),
  meal_baseline as (
    select jsonb_object_agg(meal_type, jsonb_build_object(
      'n', n, 'median_kcal', med
    )) as j
    from (
      select meal_type, count(*) as n,
        round((percentile_cont(0.5) within group (order by kcal))::numeric, 0) as med
      from meals
      where kcal is not null and meal_type <> 'unknown'
      group by meal_type
    ) m
  ),
  daily as (
    select jsonb_build_object(
      'avg', round(avg(day_kcal)::numeric, 0),
      'days_recorded', count(*)
    ) as j
    from (
      select d, sum(kcal) as day_kcal
      from meals
      where kcal is not null
        and d >= (select today from tz_now) - 6
      group by d
    ) dd
  ),
  late_snack as (
    select count(*) as n
    from meals
    where t >= time '21:00'
      and d >= (select today from tz_now) - 13
  ),
  dishes_flat as (
    select trim(dish->>'name') as name
    from meals, lateral jsonb_array_elements(
      case when jsonb_typeof(dishes) = 'array' then dishes else '[]'::jsonb end
    ) as dish
    where trim(coalesce(dish->>'name','')) <> ''
  ),
  recurring as (
    select coalesce(jsonb_agg(name order by cnt desc), '[]'::jsonb) as j
    from (
      select name, count(*) as cnt
      from dishes_flat
      group by name
      having count(*) >= 3
      order by cnt desc
      limit 5
    ) r
  )
  select jsonb_build_object(
    'v', 1,
    'meal_baseline',    coalesce((select j from meal_baseline), '{}'::jsonb),
    'daily_kcal_7d',    (select j from daily),
    'late_snack_14d',   (select n from late_snack),
    'recurring_dishes', (select j from recurring)
  );
$$;

-- ============================================================
-- reading 画像 v1
-- ============================================================
create or replace function public.rebuild_reading_profile(p_user_id uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with tz_now as (
    select (now() at time zone 'Asia/Shanghai')::date as today
  ),
  sessions as (
    select
      (occurred_at at time zone 'Asia/Shanghai')::date as d,
      nullif(trim(payload_jsonb->>'book_name'),'')          as book_name,
      nullif(payload_jsonb->>'reading_minutes','')::numeric as minutes,
      nullif(payload_jsonb->>'progress_percent','')::numeric as progress,
      occurred_at
    from public.data_records
    where user_id = p_user_id
      and domain_key = 'reading'
      and occurred_at >= now() - interval '30 days'
  ),
  latest as (
    select * from sessions
    where book_name is not null
    order by occurred_at desc limit 1
  ),
  current_book as (
    select jsonb_build_object(
      'name', l.book_name,
      'last_progress_percent', l.progress,
      'last_read_date', l.d::text,
      'sessions_30d', (select count(*) from sessions s where s.book_name = l.book_name),
      -- 一周进度推进:当前进度 - 7天前该书最早一条进度
      'progress_delta_7d', case
        when l.progress is not null then round(l.progress - coalesce((
          select s2.progress from sessions s2
          where s2.book_name = l.book_name
            and s2.progress is not null
            and s2.d >= (select today from tz_now) - 6
          order by s2.occurred_at asc limit 1
        ), l.progress), 0)
        else null end
    ) as j
    from latest l
  ),
  minutes_baseline as (
    select jsonb_build_object(
      'median_daily_30d', round((percentile_cont(0.5) within group (order by day_min))::numeric, 0),
      'days_read_30d', count(*)
    ) as j
    from (
      select d, sum(minutes) as day_min
      from sessions
      where minutes is not null
      group by d
    ) dd
  ),
  read_days as (select distinct d from sessions),
  streak as (
    -- 当前连续阅读天数:从今天(或昨天)往回数连续命中的天数
    select jsonb_build_object(
      'current_days', (
        select count(*) from read_days rd
        where rd.d > (
          -- 最近一个"断档日":今天往前第一个没读的日子
          select coalesce(max(gap_day), '1970-01-01'::date) from (
            select g.day as gap_day
            from generate_series(
              (select today from tz_now) - 29,
              (select today from tz_now), '1 day'
            ) as g(day)
            where g.day::date not in (select d from read_days)
              and g.day::date < (select today from tz_now)  -- 今天还没读不算断
          ) gaps
        )
      ),
      'best_30d', coalesce((
        select max(len) from (
          select count(*) as len
          from (select d, d - (row_number() over (order by d))::int as grp from read_days) t
          group by grp
        ) runs
      ), 0)
    ) as j
  )
  select jsonb_build_object(
    'v', 1,
    'current_book',     coalesce((select j from current_book), 'null'::jsonb),
    'minutes_baseline', (select j from minutes_baseline),
    'streak',           (select j from streak)
  );
$$;

-- ============================================================
-- wallet 画像 v1
-- 金额优先 snapshot_balance,回退 amount;按 account_name 取最新两次快照
-- ============================================================
create or replace function public.rebuild_wallet_profile(p_user_id uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with tz_now as (
    select (now() at time zone 'Asia/Shanghai')::date as today
  ),
  snaps as (
    select
      (occurred_at at time zone 'Asia/Shanghai')::date as d,
      occurred_at,
      coalesce(nullif(payload_jsonb->>'account_name',''), '未知账户') as account,
      coalesce(nullif(payload_jsonb->>'record_kind',''), 'cash_snapshot') as kind,
      coalesce(
        nullif(payload_jsonb->>'snapshot_balance','')::numeric,
        nullif(payload_jsonb->>'amount','')::numeric
      ) as balance,
      nullif(payload_jsonb->>'payment_due_day','')::numeric as due_day,
      nullif(payload_jsonb->>'due_date','') as due_date
    from public.data_records
    where user_id = p_user_id
      and domain_key = 'wallet'
      and occurred_at >= now() - interval '90 days'
  ),
  ranked as (
    select *, row_number() over (partition by account order by occurred_at desc) as rn
    from snaps
    where balance is not null
  ),
  per_account as (
    select
      account,
      max(kind) as kind,
      max(balance) filter (where rn = 1) as latest,
      max(balance) filter (where rn = 2) as prev,
      max(d::text) filter (where rn = 1) as last_snapshot,
      max(due_day) filter (where rn = 1) as due_day,
      max(due_date) filter (where rn = 1) as due_date
    from ranked
    where rn <= 2
    group by account
  ),
  liabilities as (
    select jsonb_object_agg(account, jsonb_build_object(
      'latest_amount', latest,
      'prev_amount', prev,
      'delta', case when prev is not null then round((latest - prev)::numeric, 2) else null end,
      'payment_due_day', due_day,
      'last_snapshot', last_snapshot
    )) as j
    from per_account where kind = 'liability_snapshot'
  ),
  cash as (
    select jsonb_object_agg(account, jsonb_build_object(
      'latest', latest,
      'prev', prev,
      'last_snapshot', last_snapshot
    )) as j
    from per_account where kind = 'cash_snapshot'
  ),
  due_soon as (
    -- 未来7天内到期:优先具体 due_date,否则用 payment_due_day 推算本月/下月还款日
    select coalesce(jsonb_agg(jsonb_build_object(
      'account', account, 'due_date', resolved_due::text, 'amount', latest
    ) order by resolved_due), '[]'::jsonb) as j
    from (
      select account, latest,
        case
          when due_date is not null and due_date ~ '^\d{4}-\d{2}-\d{2}' then due_date::date
          when due_day is not null then
            case when extract(day from (select today from tz_now)) <= due_day
              then make_date(
                extract(year from (select today from tz_now))::int,
                extract(month from (select today from tz_now))::int,
                least(due_day::int, 28))
              else (make_date(
                extract(year from (select today from tz_now))::int,
                extract(month from (select today from tz_now))::int,
                least(due_day::int, 28)) + interval '1 month')::date
            end
          else null
        end as resolved_due
      from per_account
      where kind = 'liability_snapshot'
    ) x
    where resolved_due is not null
      and resolved_due between (select today from tz_now)
                           and (select today from tz_now) + 7
  )
  select jsonb_build_object(
    'v', 1,
    'liabilities', coalesce((select j from liabilities), '{}'::jsonb),
    'cash',        coalesce((select j from cash), '{}'::jsonb),
    'due_soon',    (select j from due_soon)
  );
$$;

-- ============================================================
-- 分发器扩展:覆盖全部六域
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
  elsif p_domain_key = 'sport' then
    v_profile := public.rebuild_sport_profile(p_user_id);
    select count(*) into v_count from public.data_records
      where user_id = p_user_id and domain_key = 'sport'
        and occurred_at >= now() - interval '90 days';
  elsif p_domain_key = 'food' then
    v_profile := public.rebuild_food_profile(p_user_id);
    select count(*) into v_count from public.data_records
      where user_id = p_user_id and domain_key = 'food'
        and occurred_at >= now() - interval '30 days';
  elsif p_domain_key = 'reading' then
    v_profile := public.rebuild_reading_profile(p_user_id);
    select count(*) into v_count from public.data_records
      where user_id = p_user_id and domain_key = 'reading'
        and occurred_at >= now() - interval '30 days';
  elsif p_domain_key = 'wallet' then
    v_profile := public.rebuild_wallet_profile(p_user_id);
    select count(*) into v_count from public.data_records
      where user_id = p_user_id and domain_key = 'wallet'
        and occurred_at >= now() - interval '90 days';
  else
    return;
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

revoke execute on function public.rebuild_sport_profile(uuid) from anon, authenticated;
revoke execute on function public.rebuild_food_profile(uuid) from anon, authenticated;
revoke execute on function public.rebuild_reading_profile(uuid) from anon, authenticated;
revoke execute on function public.rebuild_wallet_profile(uuid) from anon, authenticated;
grant execute on function public.rebuild_sport_profile(uuid) to service_role;
grant execute on function public.rebuild_food_profile(uuid) to service_role;
grant execute on function public.rebuild_reading_profile(uuid) to service_role;
grant execute on function public.rebuild_wallet_profile(uuid) to service_role;
