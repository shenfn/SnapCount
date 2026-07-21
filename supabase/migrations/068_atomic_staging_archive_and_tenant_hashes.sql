-- Keep screenshot identity and staging archives isolated per user.

alter table public.transactions
  drop constraint if exists transactions_image_hash_key;

drop index if exists public.idx_inc_image_hash_unique;

alter table public.staging_records
  drop constraint if exists staging_records_image_hash_key;

create unique index if not exists idx_transactions_user_image_hash_unique
  on public.transactions (user_id, image_hash)
  where image_hash is not null;

create unique index if not exists idx_income_user_image_hash_unique
  on public.income_records (user_id, image_hash)
  where image_hash is not null;

create unique index if not exists idx_staging_user_image_hash_unique
  on public.staging_records (user_id, image_hash)
  where image_hash is not null;

alter table public.transactions
  add column if not exists staging_record_id uuid references public.staging_records(id) on delete set null;

alter table public.income_records
  add column if not exists staging_record_id uuid references public.staging_records(id) on delete set null;

create unique index if not exists idx_transactions_user_staging_unique
  on public.transactions (user_id, staging_record_id)
  where staging_record_id is not null;

create unique index if not exists idx_income_user_staging_unique
  on public.income_records (user_id, staging_record_id)
  where staging_record_id is not null;

create or replace function public.archive_staging_record(
  p_staging_id uuid,
  p_domain_key text,
  p_amount numeric default null,
  p_title text default null,
  p_platform text default null,
  p_category text default null,
  p_payment_method text default null,
  p_income_category text default null,
  p_record_date date default current_date,
  p_record_time time default null,
  p_occurred_at timestamptz default now(),
  p_summary text default null,
  p_payload jsonb default '{}'::jsonb,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_staging public.staging_records%rowtype;
  v_transaction public.transactions%rowtype;
  v_income public.income_records%rowtype;
  v_data_record public.data_records%rowtype;
  v_domain public.data_domains%rowtype;
  v_target_id uuid;
  v_target_domain_id uuid;
  v_target_reference text;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  if p_staging_id is null or nullif(trim(p_domain_key), '') is null then
    raise exception 'staging id and domain key are required';
  end if;

  select *
    into v_staging
  from public.staging_records
  where id = p_staging_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'staging record not found or permission denied';
  end if;

  if v_staging.status = 'archived' and v_staging.target_record_id is not null then
    return jsonb_build_object(
      'target_record_id', v_staging.target_record_id,
      'target_reference', case
        when p_domain_key = 'expense' then 'expense/' || v_staging.target_record_id::text
        when p_domain_key = 'income' then 'income/' || v_staging.target_record_id::text
        else 'data/' || v_staging.target_record_id::text
      end,
      'idempotent_retry', true
    );
  end if;

  if p_domain_key = 'expense' then
    if p_amount is null or p_amount <= 0 then
      raise exception 'expense amount must be greater than 0';
    end if;

    if v_staging.image_hash is not null then
      select * into v_transaction
      from public.transactions
      where user_id = v_user_id
        and image_hash = v_staging.image_hash
      order by created_at desc
      limit 1;
    end if;

    if v_transaction.id is null then
      select *
        into v_transaction
      from public.save_transaction_with_account(
        p_id => null,
        p_amount => p_amount,
        p_merchant_name => coalesce(nullif(trim(p_title), ''), '消费记录'),
        p_platform => coalesce(nullif(trim(p_platform), ''), '截图识别'),
        p_category => coalesce(nullif(trim(p_category), ''), 'other'),
        p_payment_method => coalesce(nullif(trim(p_payment_method), ''), '未知'),
        p_transaction_date => coalesce(p_record_date, current_date),
        p_transaction_time => p_record_time,
        p_note => p_summary,
        p_is_large_transport => coalesce(p_category in ('transport', '出行') and p_amount >= 200, false),
        p_transport_type => case when p_category in ('transport', '出行') and p_amount >= 200 then '交通' else null end,
        p_source => 'ai_scan',
        p_image_url => v_staging.image_path,
        p_image_hash => v_staging.image_hash,
        p_companion_message => v_staging.companion_message,
        p_account_id => p_account_id
      );
    end if;

    update public.transactions
       set staging_record_id = v_staging.id
     where id = v_transaction.id
       and user_id = v_user_id;

    v_target_id := v_transaction.id;
    v_target_domain_id := null;
    v_target_reference := 'expense/' || v_transaction.id::text;

  elsif p_domain_key = 'income' then
    if p_amount is null or p_amount <= 0 then
      raise exception 'income amount must be greater than 0';
    end if;

    if v_staging.image_hash is not null then
      select * into v_income
      from public.income_records
      where user_id = v_user_id
        and image_hash = v_staging.image_hash
      order by created_at desc
      limit 1;
    end if;

    if v_income.id is null then
      select *
        into v_income
      from public.save_income_with_account(
        p_id => null,
        p_category => coalesce(nullif(trim(p_income_category), ''), 'other'),
        p_source_name => coalesce(nullif(trim(p_title), ''), '收入记录'),
        p_amount => p_amount,
        p_income_date => coalesce(p_record_date, current_date),
        p_note => p_summary,
        p_source => 'ai_scan',
        p_image_url => v_staging.image_path,
        p_image_hash => v_staging.image_hash,
        p_companion_message => v_staging.companion_message,
        p_account_id => p_account_id
      );
    end if;

    update public.income_records
       set staging_record_id = v_staging.id
     where id = v_income.id
       and user_id = v_user_id;

    v_target_id := v_income.id;
    v_target_domain_id := null;
    v_target_reference := 'income/' || v_income.id::text;

  else
    select *
      into v_domain
    from public.data_domains
    where key = p_domain_key
      and status = 'active'
      and (user_id = v_user_id or user_id is null or is_system = true)
    order by (user_id = v_user_id) desc nulls last
    limit 1;

    if not found then
      raise exception 'data domain not found: %', p_domain_key;
    end if;

    if v_staging.image_hash is not null then
      select * into v_data_record
      from public.data_records
      where user_id = v_user_id
        and domain_key = p_domain_key
        and source_image_hash = v_staging.image_hash
      order by created_at desc
      limit 1;
    end if;

    if v_data_record.id is null then
      insert into public.data_records (
      domain_id,
      domain_key,
      domain_version,
      occurred_at,
      title,
      summary,
      payload_jsonb,
      source,
      source_image_path,
      source_image_hash,
      staging_record_id,
      user_id
    ) values (
      v_domain.id,
      v_domain.key,
      coalesce(v_domain.version, '1.0'),
      coalesce(p_occurred_at, now()),
      coalesce(nullif(trim(p_title), ''), v_domain.name),
      p_summary,
      coalesce(p_payload, '{}'::jsonb),
      'staging',
      v_staging.image_path,
      v_staging.image_hash,
      v_staging.id,
      v_user_id
    )
      returning * into v_data_record;
    end if;

    v_target_id := v_data_record.id;
    v_target_domain_id := v_domain.id;
    v_target_reference := 'data/' || v_data_record.id::text;
  end if;

  update public.staging_records
     set status = 'archived',
         target_domain_id = v_target_domain_id,
         target_record_id = v_target_id,
         resolved_action = 'archived',
         resolved_at = now(),
         updated_at = now()
   where id = v_staging.id
     and user_id = v_user_id;

  insert into public.user_routing_feedback (
    staging_record_id,
    image_hash,
    original_domain_key,
    corrected_domain_key,
    action,
    confidence,
    payload_jsonb,
    user_id
  ) values (
    v_staging.id,
    v_staging.image_hash,
    v_staging.detected_domain_key,
    p_domain_key,
    'archive',
    v_staging.confidence,
    coalesce(p_payload, '{}'::jsonb),
    v_user_id
  );

  return jsonb_build_object(
    'target_record_id', v_target_id,
    'target_reference', v_target_reference,
    'idempotent_retry', false
  );
end;
$$;

revoke all on function public.archive_staging_record(uuid, text, numeric, text, text, text, text, text, date, time, timestamptz, text, jsonb, uuid) from public;
revoke execute on function public.archive_staging_record(uuid, text, numeric, text, text, text, text, text, date, time, timestamptz, text, jsonb, uuid) from anon;
grant execute on function public.archive_staging_record(uuid, text, numeric, text, text, text, text, text, date, time, timestamptz, text, jsonb, uuid) to authenticated;
