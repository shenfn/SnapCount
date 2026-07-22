begin;

create or replace function public.invalidate_companion_context_after_record_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_domain_key text;
begin
  delete from public.user_companion_memories
  where user_id = old.user_id
    and source_table = tg_table_name
    and source_id = old.id;

  if tg_table_name = 'transactions' then
    v_domain_key := 'expense';
  elsif tg_table_name = 'data_records' then
    v_domain_key := nullif(to_jsonb(old)->>'domain_key', '');
  end if;

  if v_domain_key in ('expense', 'sleep', 'sport', 'food', 'reading', 'wallet') then
    delete from public.user_domain_profiles
    where user_id = old.user_id
      and domain_key = v_domain_key;
  end if;

  return old;
end;
$$;

revoke all on function public.invalidate_companion_context_after_record_delete()
  from public, anon, authenticated;

drop trigger if exists tr_invalidate_transaction_context_after_delete on public.transactions;
create trigger tr_invalidate_transaction_context_after_delete
  after delete on public.transactions
  for each row execute function public.invalidate_companion_context_after_record_delete();

drop trigger if exists tr_invalidate_income_context_after_delete on public.income_records;
create trigger tr_invalidate_income_context_after_delete
  after delete on public.income_records
  for each row execute function public.invalidate_companion_context_after_record_delete();

drop trigger if exists tr_invalidate_data_context_after_delete on public.data_records;
create trigger tr_invalidate_data_context_after_delete
  after delete on public.data_records
  for each row execute function public.invalidate_companion_context_after_record_delete();

delete from public.user_companion_memories m
where m.source_table = 'transactions'
  and m.source_id is not null
  and not exists (
    select 1
    from public.transactions t
    where t.id = m.source_id
      and t.user_id = m.user_id
  );

delete from public.user_companion_memories m
where m.source_table = 'income_records'
  and m.source_id is not null
  and not exists (
    select 1
    from public.income_records i
    where i.id = m.source_id
      and i.user_id = m.user_id
  );

delete from public.user_companion_memories m
where m.source_table = 'data_records'
  and m.source_id is not null
  and not exists (
    select 1
    from public.data_records d
    where d.id = m.source_id
      and d.user_id = m.user_id
  );

do $$
declare
  v_unsafe_pattern constant text := '(第几笔|凑个单|小确幸|给生活充个值|看来是|应该不错|确实地道|本周|这周|上周|本月|上月|近[[:space:]]*[0-9一二两三四五六七八九十]+[天周月]|第[[:space:]]*[0-9一二两三四五六七八九十百]+[次笔顿天晚家回]|连续[[:space:]]*[0-9一二两三四五六七八九十百]+[天晚次周月]|比(昨天|之前|过去|上次|上周|上月|平时|常态|平均|中位|历史)|最近.{0,12}(总是|一直|经常|频繁|反复|又))';
begin
  update public.transactions
  set companion_message = null,
      ai_feedback = case
        when coalesce(ai_feedback->>'source', '') = 'rule' then ai_feedback
        else null
      end
  where coalesce(companion_message, '') ~ v_unsafe_pattern
     or (
       coalesce(ai_feedback->>'source', '') <> 'rule'
       and coalesce(ai_feedback::text, '') ~ v_unsafe_pattern
     );

  update public.income_records
  set companion_message = null,
      ai_feedback = case
        when coalesce(ai_feedback->>'source', '') = 'rule' then ai_feedback
        else null
      end
  where coalesce(companion_message, '') ~ v_unsafe_pattern
     or (
       coalesce(ai_feedback->>'source', '') <> 'rule'
       and coalesce(ai_feedback::text, '') ~ v_unsafe_pattern
     );

  update public.staging_records
  set companion_message = null,
      extracted_json = case
        when coalesce(extracted_json->'ai_feedback'->>'source', '') = 'rule'
          then coalesce(extracted_json, '{}'::jsonb) - 'companion_message'
        else coalesce(extracted_json, '{}'::jsonb) - 'companion_message' - 'ai_feedback'
      end
  where coalesce(companion_message, '') ~ v_unsafe_pattern
     or (
       coalesce(extracted_json->'ai_feedback'->>'source', '') <> 'rule'
       and coalesce(extracted_json->'ai_feedback', 'null'::jsonb)::text ~ v_unsafe_pattern
     );

  update public.data_records
  set payload_jsonb = case
    when coalesce(payload_jsonb->'ai_feedback'->>'source', '') = 'rule'
      then coalesce(payload_jsonb, '{}'::jsonb) - 'companion_message'
    else coalesce(payload_jsonb, '{}'::jsonb) - 'companion_message' - 'ai_feedback'
  end
  where coalesce(payload_jsonb->>'companion_message', '') ~ v_unsafe_pattern
     or (
       coalesce(payload_jsonb->'ai_feedback'->>'source', '') <> 'rule'
       and coalesce(payload_jsonb->'ai_feedback', 'null'::jsonb)::text ~ v_unsafe_pattern
     );

  delete from public.user_companion_memories
  where coalesce(content, '') ~ v_unsafe_pattern;
end;
$$;

delete from public.user_domain_profiles p
where p.source_count <> case p.domain_key
  when 'expense' then (
    select count(*)
    from public.transactions t
    where t.user_id = p.user_id
      and t.type = 'expense'
      and t.transaction_date >= (now() at time zone 'Asia/Shanghai')::date - 90
  )
  when 'sleep' then (
    select count(*)
    from public.data_records d
    where d.user_id = p.user_id
      and d.domain_key = 'sleep'
      and d.occurred_at >= now() - interval '30 days'
  )
  when 'sport' then (
    select count(*)
    from public.data_records d
    where d.user_id = p.user_id
      and d.domain_key = 'sport'
      and d.occurred_at >= now() - interval '90 days'
  )
  when 'food' then (
    select count(*)
    from public.data_records d
    where d.user_id = p.user_id
      and d.domain_key = 'food'
      and d.occurred_at >= now() - interval '30 days'
  )
  when 'reading' then (
    select count(*)
    from public.data_records d
    where d.user_id = p.user_id
      and d.domain_key = 'reading'
      and d.occurred_at >= now() - interval '30 days'
  )
  when 'wallet' then (
    select count(*)
    from public.data_records d
    where d.user_id = p.user_id
      and d.domain_key = 'wallet'
      and d.occurred_at >= now() - interval '90 days'
  )
  else p.source_count
end;

commit;
