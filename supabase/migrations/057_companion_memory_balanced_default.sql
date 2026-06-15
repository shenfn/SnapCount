-- Make companion memory less eager by default.
-- The previous "bold" default made recent merchants leak into unrelated food photos.

alter table public.user_configs
  alter column companion_memory_strength set default 'balanced';

update public.user_configs
set companion_memory_strength = 'balanced',
    updated_at = now()
where companion_memory_strength = 'bold'
  and companion_custom_note is null;

create or replace function public.get_companion_context(p_user_id uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with cfg as (
    select
      companion_enabled,
      companion_memory_enabled,
      companion_persona,
      companion_memory_strength,
      companion_expression_style,
      companion_custom_note
    from public.user_configs
    where user_id = p_user_id
  ),
  today_spend as (
    select
      coalesce(sum(amount), 0) as total,
      count(*) as count,
      count(*) filter (where category in ('food','餐饮','美食','餐厅')) as food_count,
      count(*) filter (where transaction_time >= time '21:00') as late_count
    from public.transactions
    where user_id = p_user_id
      and type = 'expense'
      and transaction_date = (now() at time zone 'Asia/Shanghai')::date
  ),
  week_spend as (
    select
      coalesce(sum(amount), 0) as total,
      count(*) as count,
      count(*) filter (where category in ('food','餐饮','美食','餐厅')) as food_count,
      count(*) filter (where transaction_time >= time '21:00') as late_count
    from public.transactions
    where user_id = p_user_id
      and type = 'expense'
      and transaction_date >= (now() at time zone 'Asia/Shanghai')::date - 6
  ),
  frequent_merchants as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'name', merchant_name,
      'times', cnt,
      'total', total
    ) order by cnt desc, total desc), '[]'::jsonb) as items
    from (
      select merchant_name, count(*) as cnt, round(sum(amount)::numeric, 2) as total
      from public.transactions
      where user_id = p_user_id
        and type = 'expense'
        and transaction_date >= (now() at time zone 'Asia/Shanghai')::date - 29
        and merchant_name is not null
        and merchant_name <> ''
      group by merchant_name
      having count(*) >= 2
      order by cnt desc, total desc
      limit 5
    ) m
  ),
  sport_week as (
    select
      count(*) as count,
      max((occurred_at at time zone 'Asia/Shanghai')::date) as last_date,
      round(coalesce(sum(nullif(payload_jsonb->>'duration_minutes','')::numeric), 0), 1) as minutes
    from public.data_records
    where user_id = p_user_id
      and domain_key = 'sport'
      and occurred_at >= date_trunc('week', now() at time zone 'Asia/Shanghai')
  ),
  last_sleep as (
    select jsonb_build_object(
      'hours', payload_jsonb->>'sleep_hours',
      'minutes', payload_jsonb->>'sleep_minutes',
      'score', payload_jsonb->>'quality_score',
      'date', (occurred_at at time zone 'Asia/Shanghai')::date
    ) as item
    from public.data_records
    where user_id = p_user_id
      and domain_key = 'sleep'
    order by occurred_at desc
    limit 1
  ),
  food_week as (
    select
      count(*) as count,
      round(coalesce(sum(nullif(payload_jsonb->>'total_calorie_kcal','')::numeric), 0), 0) as calories
    from public.data_records
    where user_id = p_user_id
      and domain_key = 'food'
      and occurred_at >= (now() at time zone 'Asia/Shanghai') - interval '7 days'
  ),
  recent_companions as (
    select coalesce(jsonb_agg(jsonb_build_object('d', d, 't', t) order by created_at desc), '[]'::jsonb) as items
    from (
      select created_at, transaction_date as d, companion_message as t
      from public.transactions
      where user_id = p_user_id and companion_message is not null and companion_message <> ''
      union all
      select created_at, income_date as d, companion_message as t
      from public.income_records
      where user_id = p_user_id and companion_message is not null and companion_message <> ''
      union all
      select created_at, (occurred_at at time zone 'Asia/Shanghai')::date as d, payload_jsonb->>'companion_message' as t
      from public.data_records
      where user_id = p_user_id and payload_jsonb->>'companion_message' is not null and payload_jsonb->>'companion_message' <> ''
      order by created_at desc
      limit 8
    ) c
  ),
  memories as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'type', memory_type,
      'key', memory_key,
      'content', content,
      'confidence', confidence,
      'weight', weight,
      'last_seen_at', last_seen_at,
      'evidence', evidence_jsonb
    ) order by weight desc, last_seen_at desc), '[]'::jsonb) as items
    from (
      select *
      from public.user_companion_memories
      where user_id = p_user_id
        and (expires_at is null or expires_at > now())
      order by weight desc, last_seen_at desc
      limit 8
    ) mm
  )
  select jsonb_build_object(
    'settings', jsonb_build_object(
      'enabled', coalesce((select companion_enabled from cfg), true),
      'memory_enabled', coalesce((select companion_memory_enabled from cfg), true),
      'persona', coalesce((select companion_persona from cfg), 'observer'),
      'memory_strength', coalesce((select companion_memory_strength from cfg), 'balanced'),
      'expression_style', coalesce((select companion_expression_style from cfg), 'plain'),
      'custom_note', (select companion_custom_note from cfg)
    ),
    'short_term', jsonb_build_object(
      'today_spend', (select to_jsonb(today_spend) from today_spend),
      'week_spend', (select to_jsonb(week_spend) from week_spend),
      'frequent_merchants_30d', (select items from frequent_merchants),
      'sport_this_week', (select to_jsonb(sport_week) from sport_week),
      'last_sleep', coalesce((select item from last_sleep), 'null'::jsonb),
      'food_this_week', (select to_jsonb(food_week) from food_week),
      'recent_companions', (select items from recent_companions)
    ),
    'long_term', (select items from memories)
  );
$$;

revoke execute on function public.get_companion_context(uuid) from public;
revoke execute on function public.get_companion_context(uuid) from anon;
revoke execute on function public.get_companion_context(uuid) from authenticated;
grant execute on function public.get_companion_context(uuid) to service_role;
