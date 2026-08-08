-- Persist a canonical finance occurrence instant while keeping the legacy
-- date/time columns available to older clients.

alter table public.transactions
  add column if not exists occurred_at timestamptz;

alter table public.income_records
  add column if not exists occurred_at timestamptz;

comment on column public.transactions.occurred_at is
  'Canonical business occurrence instant. Legacy transaction_date/time mirror Asia/Shanghai wall time.';

comment on column public.income_records.occurred_at is
  'Canonical business occurrence instant when source evidence includes a real time; nullable for date-only income.';

create index if not exists idx_transactions_user_occurred_at
  on public.transactions (user_id, occurred_at desc)
  where occurred_at is not null;

create index if not exists idx_income_records_user_occurred_at
  on public.income_records (user_id, occurred_at desc)
  where occurred_at is not null;

create or replace function public.finance_occurred_at_from_shanghai_wall_time(
  p_record_date date,
  p_record_time time
)
returns timestamptz
language sql
stable
strict
set search_path = pg_catalog, public
as $$
  select make_timestamptz(
    extract(year from p_record_date)::integer,
    extract(month from p_record_date)::integer,
    extract(day from p_record_date)::integer,
    extract(hour from p_record_time)::integer,
    extract(minute from p_record_time)::integer,
    extract(second from p_record_time)::double precision,
    'Asia/Shanghai'
  );
$$;

revoke all on function public.finance_occurred_at_from_shanghai_wall_time(date, time) from public, anon, authenticated;

create or replace function public.finance_parse_explicit_timestamptz(
  p_value text
)
returns timestamptz
language plpgsql
stable
strict
set search_path = pg_catalog, public
as $$
begin
  if trim(p_value) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}(:[0-9]{2}([.][0-9]+)?)?([Zz]|[+-][0-9]{2}:[0-9]{2})$' then
    return null;
  end if;

  begin
    return trim(p_value)::timestamptz;
  exception when others then
    return null;
  end;
end;
$$;

create or replace function public.finance_explicit_occurred_at_from_payload(
  p_payload jsonb
)
returns timestamptz
language plpgsql
stable
strict
set search_path = pg_catalog, public
as $$
declare
  v_parsed timestamptz;
  v_time_source text;
begin
  v_parsed := public.finance_parse_explicit_timestamptz(
    nullif(trim(p_payload->>'occurred_at'), '')
  );
  if v_parsed is not null then
    return v_parsed;
  end if;

  v_parsed := public.finance_parse_explicit_timestamptz(
    nullif(trim(p_payload->>'order_finished_at'), '')
  );
  if v_parsed is not null then
    return v_parsed;
  end if;

  v_time_source := nullif(trim(p_payload->'time_context'->>'event_time_source'), '');
  if v_time_source in ('ai_occurred_at', 'ai_order_finished_at') then
    return public.finance_parse_explicit_timestamptz(
      nullif(trim(p_payload->'time_context'->>'event_time'), '')
    );
  end if;

  return null;
end;
$$;

revoke all on function public.finance_parse_explicit_timestamptz(text) from public, anon, authenticated;
revoke all on function public.finance_explicit_occurred_at_from_payload(jsonb) from public, anon, authenticated;

-- Backfill only from stored event-time evidence. Legacy transaction_time may
-- have been synthesized by the database server clock, so it is not trusted by
-- itself. Rows without staging/log evidence intentionally remain null and can
-- be audited with `where occurred_at is null` before a later evidence repair.
-- Historical legacy date/time fields are deliberately left untouched: a user
-- may have corrected them after the AI log was written.
with staging_evidence as (
  select
    id,
    user_id,
    public.finance_explicit_occurred_at_from_payload(extracted_json) as occurred_at
  from public.staging_records
)
update public.transactions as transaction
   set occurred_at = evidence.occurred_at
  from staging_evidence as evidence
 where transaction.occurred_at is null
   and transaction.staging_record_id = evidence.id
   and transaction.user_id = evidence.user_id
   and evidence.occurred_at is not null;

with staging_evidence as (
  select
    id,
    user_id,
    public.finance_explicit_occurred_at_from_payload(extracted_json) as occurred_at
  from public.staging_records
)
update public.income_records as income
   set occurred_at = evidence.occurred_at
  from staging_evidence as evidence
 where income.occurred_at is null
   and income.staging_record_id = evidence.id
   and income.user_id = evidence.user_id
   and evidence.occurred_at is not null;

with latest_transaction_evidence as (
  select distinct on (candidate.target_id, candidate.user_id)
    candidate.target_id,
    candidate.user_id,
    candidate.occurred_at
  from (
    select
      id,
      created_at,
      target_id,
      user_id,
      public.finance_explicit_occurred_at_from_payload(ai_response) as occurred_at
    from public.ai_recognition_logs
    where target_table = 'transactions'
      and target_id is not null
  ) as candidate
  where candidate.occurred_at is not null
  order by target_id, user_id, created_at desc, id desc
)
update public.transactions as transaction
   set occurred_at = evidence.occurred_at
  from latest_transaction_evidence as evidence
 where transaction.occurred_at is null
   and transaction.id = evidence.target_id
   and transaction.user_id = evidence.user_id;

with latest_income_evidence as (
  select distinct on (candidate.target_id, candidate.user_id)
    candidate.target_id,
    candidate.user_id,
    candidate.occurred_at
  from (
    select
      id,
      created_at,
      target_id,
      user_id,
      public.finance_explicit_occurred_at_from_payload(ai_response) as occurred_at
    from public.ai_recognition_logs
    where target_table = 'income_records'
      and target_id is not null
  ) as candidate
  where candidate.occurred_at is not null
  order by target_id, user_id, created_at desc, id desc
)
update public.income_records as income
   set occurred_at = evidence.occurred_at
  from latest_income_evidence as evidence
 where income.occurred_at is null
   and income.id = evidence.target_id
   and income.user_id = evidence.user_id;

update public.account_entries as entry
   set occurred_at = transaction.occurred_at
  from public.transactions as transaction
 where entry.source_table = 'transactions'
   and entry.source_id = transaction.id
   and entry.user_id = transaction.user_id
   and transaction.occurred_at is not null
   and entry.occurred_at is distinct from transaction.occurred_at;

update public.account_entries as entry
   set occurred_at = income.occurred_at
  from public.income_records as income
 where entry.source_table = 'income_records'
   and entry.source_id = income.id
   and entry.user_id = income.user_id
   and income.occurred_at is not null
   and entry.occurred_at is distinct from income.occurred_at;

-- A ledger write and a business occurrence are different facts. Source-backed
-- entries may therefore keep occurred_at null while created_at still records
-- when the ledger entry itself was written.
alter table public.account_entries
  alter column occurred_at drop not null;

comment on column public.account_entries.occurred_at is
  'Canonical source occurrence instant; nullable when the source has no exact time evidence. created_at is the ledger write time.';

create or replace function public.create_account_entry_for_record(
  p_account_id uuid,
  p_direction text,
  p_amount numeric,
  p_entry_type text,
  p_source_table text default null,
  p_source_id uuid default null,
  p_occurred_at timestamptz default null,
  p_note text default null
)
returns public.account_entries
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_account public.accounts%rowtype;
  v_entry public.account_entries%rowtype;
begin
  if p_account_id is null then
    raise exception 'account_id is required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be greater than 0';
  end if;

  select *
    into v_account
  from public.accounts
  where id = p_account_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'account not found or permission denied';
  end if;

  if p_source_table is not null and p_source_id is not null then
    update public.account_entries
       set is_voided = true,
           voided_reason = 'replaced_by_upsert'
     where user_id = v_account.user_id
       and source_table = p_source_table
       and source_id = p_source_id
       and entry_type = p_entry_type::public.account_entry_type
       and is_voided = false;
  end if;

  insert into public.account_entries (
    user_id,
    account_id,
    direction,
    amount,
    entry_type,
    source_table,
    source_id,
    occurred_at,
    note
  ) values (
    v_account.user_id,
    p_account_id,
    p_direction::public.account_entry_direction,
    p_amount,
    p_entry_type::public.account_entry_type,
    p_source_table,
    p_source_id,
    p_occurred_at,
    p_note
  )
  returning * into v_entry;

  return v_entry;
end;
$$;

revoke all on function public.create_account_entry_for_record(uuid, text, numeric, text, text, uuid, timestamptz, text) from public, anon;
grant execute on function public.create_account_entry_for_record(uuid, text, numeric, text, text, uuid, timestamptz, text) to authenticated;

-- The canonical overload takes an explicit final p_occurred_at argument. The
-- original function identities remain below as compatibility shells.
create or replace function public.save_transaction_with_account(
  p_id uuid,
  p_amount numeric,
  p_merchant_name text,
  p_platform text,
  p_category text,
  p_payment_method text,
  p_transaction_date date,
  p_transaction_time time,
  p_note text,
  p_is_large_transport boolean,
  p_transport_type text,
  p_source text,
  p_image_url text,
  p_image_hash text,
  p_companion_message text,
  p_account_id uuid,
  p_occurred_at timestamptz
)
returns public.transactions
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_existing public.transactions%rowtype;
  v_row public.transactions%rowtype;
  v_direction public.account_entry_direction;
  v_local_now timestamp := timezone('Asia/Shanghai', clock_timestamp());
  v_record_date date;
  v_record_time time;
  v_occurred_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be greater than 0';
  end if;

  if p_id is not null then
    select *
      into v_existing
    from public.transactions
    where id = p_id
      and user_id = auth.uid()
    for update;

    if not found then
      raise exception 'transaction not found or permission denied';
    end if;
  end if;

  if p_occurred_at is not null then
    v_occurred_at := p_occurred_at;
    v_record_date := timezone('Asia/Shanghai', p_occurred_at)::date;
    v_record_time := timezone('Asia/Shanghai', p_occurred_at)::time(0);
  elsif p_id is not null and v_existing.occurred_at is not null then
    v_occurred_at := v_existing.occurred_at;
    v_record_date := timezone('Asia/Shanghai', v_existing.occurred_at)::date;
    v_record_time := timezone('Asia/Shanghai', v_existing.occurred_at)::time(0);
  else
    v_record_date := coalesce(p_transaction_date, v_existing.transaction_date, v_local_now::date);
    v_record_time := coalesce(p_transaction_time, v_existing.transaction_time);
    v_occurred_at := null;
  end if;

  if p_id is null then
    insert into public.transactions (
      type,
      amount,
      merchant_name,
      platform,
      category,
      payment_method,
      status,
      transaction_date,
      transaction_time,
      occurred_at,
      source,
      image_url,
      image_hash,
      companion_message,
      note,
      is_large_transport,
      transport_type,
      user_id,
      account_id
    ) values (
      'expense',
      p_amount,
      p_merchant_name,
      p_platform,
      p_category,
      p_payment_method,
      'done',
      v_record_date,
      v_record_time,
      v_occurred_at,
      coalesce(p_source, 'manual'),
      p_image_url,
      p_image_hash,
      p_companion_message,
      p_note,
      coalesce(p_is_large_transport, false),
      p_transport_type,
      auth.uid(),
      p_account_id
    )
    returning * into v_row;
  else
    update public.transactions
       set amount = p_amount,
           merchant_name = p_merchant_name,
           platform = p_platform,
           category = p_category,
           payment_method = p_payment_method,
           status = 'done',
           transaction_date = v_record_date,
           transaction_time = v_record_time,
           occurred_at = v_occurred_at,
           source = coalesce(p_source, source),
           image_url = coalesce(p_image_url, image_url),
           image_hash = coalesce(p_image_hash, image_hash),
           companion_message = coalesce(p_companion_message, companion_message),
           note = p_note,
           is_large_transport = coalesce(p_is_large_transport, false),
           transport_type = p_transport_type,
           account_id = p_account_id
     where id = p_id
       and user_id = auth.uid()
     returning * into v_row;
  end if;

  if p_account_id is null then
    perform public.void_account_entries_for_record('transactions', v_row.id, 'unbound_after_save');
  else
    v_direction := public.resolve_account_entry_direction(p_account_id, 'expense', 'out');
    perform public.create_account_entry_for_record(
      p_account_id,
      v_direction::text,
      p_amount,
      'expense',
      'transactions',
      v_row.id,
      v_row.occurred_at,
      case when p_id is null then '手动创建支出' else '手动编辑支出' end
    );
  end if;

  return v_row;
end;
$$;

create or replace function public.save_income_with_account(
  p_id uuid,
  p_category text,
  p_source_name text,
  p_amount numeric,
  p_income_date date,
  p_note text,
  p_source text,
  p_image_url text,
  p_image_hash text,
  p_companion_message text,
  p_account_id uuid,
  p_occurred_at timestamptz
)
returns public.income_records
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_existing public.income_records%rowtype;
  v_row public.income_records%rowtype;
  v_local_now timestamp := timezone('Asia/Shanghai', clock_timestamp());
  v_income_date date;
  v_occurred_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be greater than 0';
  end if;

  if p_id is not null then
    select *
      into v_existing
    from public.income_records
    where id = p_id
      and user_id = auth.uid()
    for update;

    if not found then
      raise exception 'income record not found or permission denied';
    end if;
  end if;

  if p_occurred_at is not null then
    v_occurred_at := p_occurred_at;
    v_income_date := timezone('Asia/Shanghai', p_occurred_at)::date;
  elsif p_id is not null and v_existing.occurred_at is not null then
    v_occurred_at := v_existing.occurred_at;
    v_income_date := timezone('Asia/Shanghai', v_existing.occurred_at)::date;
  else
    v_income_date := coalesce(p_income_date, v_existing.income_date, v_local_now::date);
    v_occurred_at := null;
  end if;

  if p_id is null then
    insert into public.income_records (
      category,
      source_name,
      amount,
      income_date,
      occurred_at,
      note,
      source,
      image_url,
      image_hash,
      companion_message,
      user_id,
      account_id
    ) values (
      p_category,
      p_source_name,
      p_amount,
      v_income_date,
      v_occurred_at,
      p_note,
      coalesce(p_source, 'manual'),
      p_image_url,
      p_image_hash,
      p_companion_message,
      auth.uid(),
      p_account_id
    )
    returning * into v_row;
  else
    update public.income_records
       set category = p_category,
           source_name = p_source_name,
           amount = p_amount,
           income_date = v_income_date,
           occurred_at = v_occurred_at,
           note = p_note,
           source = coalesce(p_source, source),
           image_url = coalesce(p_image_url, image_url),
           image_hash = coalesce(p_image_hash, image_hash),
           companion_message = coalesce(p_companion_message, companion_message),
           account_id = p_account_id
     where id = p_id
       and user_id = auth.uid()
     returning * into v_row;
  end if;

  if p_account_id is null then
    perform public.void_account_entries_for_record('income_records', v_row.id, 'unbound_after_save');
  else
    perform public.create_account_entry_for_record(
      p_account_id,
      'in',
      p_amount,
      'income',
      'income_records',
      v_row.id,
      v_row.occurred_at,
      case when p_id is null then '手动创建收入' else '手动编辑收入' end
    );
  end if;

  return v_row;
end;
$$;

-- Compatibility shell for the original 16-argument expense RPC. Keeping the
-- old identity avoids breaking clients that have not learned p_occurred_at.
create or replace function public.save_transaction_with_account(
  p_id uuid default null,
  p_amount numeric default null,
  p_merchant_name text default null,
  p_platform text default null,
  p_category text default null,
  p_payment_method text default null,
  p_transaction_date date default null,
  p_transaction_time time default null,
  p_note text default null,
  p_is_large_transport boolean default false,
  p_transport_type text default null,
  p_source text default 'manual',
  p_image_url text default null,
  p_image_hash text default null,
  p_companion_message text default null,
  p_account_id uuid default null
)
returns public.transactions
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_occurred_at timestamptz;
begin
  if coalesce(p_source, 'manual') = 'manual'
    and p_transaction_date is not null
    and p_transaction_time is not null
  then
    v_occurred_at := public.finance_occurred_at_from_shanghai_wall_time(
      p_transaction_date,
      p_transaction_time
    );
  end if;

  return public.save_transaction_with_account(
    p_id => $1,
    p_amount => $2,
    p_merchant_name => $3,
    p_platform => $4,
    p_category => $5,
    p_payment_method => $6,
    p_transaction_date => $7,
    p_transaction_time => $8,
    p_note => $9,
    p_is_large_transport => $10,
    p_transport_type => $11,
    p_source => $12,
    p_image_url => $13,
    p_image_hash => $14,
    p_companion_message => $15,
    p_account_id => $16,
    p_occurred_at => v_occurred_at
  );
end;
$$;

-- Compatibility shell for the original 11-argument income RPC.
create or replace function public.save_income_with_account(
  p_id uuid default null,
  p_category text default null,
  p_source_name text default null,
  p_amount numeric default null,
  p_income_date date default null,
  p_note text default null,
  p_source text default 'manual',
  p_image_url text default null,
  p_image_hash text default null,
  p_companion_message text default null,
  p_account_id uuid default null
)
returns public.income_records
language sql
security definer
set search_path = pg_catalog, public, auth
as $$
  select public.save_income_with_account(
    p_id => $1,
    p_category => $2,
    p_source_name => $3,
    p_amount => $4,
    p_income_date => $5,
    p_note => $6,
    p_source => $7,
    p_image_url => $8,
    p_image_hash => $9,
    p_companion_message => $10,
    p_account_id => $11,
    p_occurred_at => null
  );
$$;

create or replace function public.confirm_pending_transaction_with_account(
  p_pending_id uuid,
  p_entry_type text,
  p_amount numeric,
  p_merchant_or_source_name text default null,
  p_platform text default null,
  p_category text default null,
  p_payment_method text default null,
  p_income_category text default null,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_pending public.transactions%rowtype;
  v_tx public.transactions%rowtype;
  v_income public.income_records%rowtype;
  v_date date;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_pending_id is null then
    raise exception 'pending id is required';
  end if;

  select *
    into v_pending
  from public.transactions
  where id = p_pending_id
    and user_id = auth.uid()
  for update;

  if not found then
    if p_entry_type = 'income' then
      select *
        into v_income
      from public.income_records
      where source_pending_transaction_id = p_pending_id
        and user_id = auth.uid();

      if found then
        return jsonb_build_object(
          'record_type', 'income',
          'income_record', to_jsonb(v_income),
          'idempotent_retry', true
        );
      end if;
    elsif p_entry_type = 'expense' then
      select *
        into v_tx
      from public.transactions
      where id = p_pending_id
        and user_id = auth.uid()
        and status = 'done';

      if found then
        return jsonb_build_object(
          'record_type', 'expense',
          'transaction', to_jsonb(v_tx),
          'idempotent_retry', true
        );
      end if;
    end if;

    raise exception 'pending transaction not found or permission denied';
  end if;

  if p_entry_type = 'income' then
    if v_pending.status <> 'pending' then
      select *
        into v_income
      from public.income_records
      where source_pending_transaction_id = p_pending_id
        and user_id = auth.uid();

      if found then
        return jsonb_build_object(
          'record_type', 'income',
          'income_record', to_jsonb(v_income),
          'idempotent_retry', true
        );
      end if;

      raise exception 'pending transaction already resolved';
    end if;

    v_date := coalesce(
      timezone('Asia/Shanghai', v_pending.occurred_at)::date,
      v_pending.transaction_date,
      timezone('Asia/Shanghai', now())::date
    );

    select *
      into v_income
    from public.save_income_with_account(
      p_id => null,
      p_category => p_income_category,
      p_source_name => coalesce(nullif(p_merchant_or_source_name, ''), '收入'),
      p_amount => p_amount,
      p_income_date => v_date,
      p_note => case when v_pending.image_url is not null then '由截图待补充转入收入' else null end,
      p_source => 'ai_scan',
      p_image_url => v_pending.image_url,
      p_image_hash => v_pending.image_hash,
      p_companion_message => v_pending.companion_message,
      p_account_id => p_account_id,
      p_occurred_at => v_pending.occurred_at
    );

    update public.income_records
       set source_pending_transaction_id = p_pending_id
     where id = v_income.id
       and user_id = auth.uid();

    delete from public.transactions
    where id = v_pending.id
      and user_id = auth.uid();

    return jsonb_build_object('record_type', 'income', 'income_record', to_jsonb(v_income));
  end if;

  if p_entry_type <> 'expense' then
    raise exception 'entry_type must be expense or income';
  end if;

  if v_pending.status <> 'pending' then
    return jsonb_build_object(
      'record_type', 'expense',
      'transaction', to_jsonb(v_pending),
      'idempotent_retry', true
    );
  end if;

  v_date := coalesce(
    timezone('Asia/Shanghai', v_pending.occurred_at)::date,
    v_pending.transaction_date,
    timezone('Asia/Shanghai', now())::date
  );

  select *
    into v_tx
  from public.save_transaction_with_account(
    p_id => v_pending.id,
    p_amount => p_amount,
    p_merchant_name => coalesce(nullif(p_merchant_or_source_name, ''), coalesce(p_platform, '其他') || '消费'),
    p_platform => p_platform,
    p_category => p_category,
    p_payment_method => p_payment_method,
    p_transaction_date => v_date,
    p_transaction_time => v_pending.transaction_time,
    p_note => v_pending.note,
    p_is_large_transport => coalesce(p_category = '出行' and p_amount >= 200, false),
    p_transport_type => case when p_category = '出行' and p_amount >= 200 then '交通' else null end,
    p_source => coalesce(v_pending.source, 'ai_scan'),
    p_image_url => v_pending.image_url,
    p_image_hash => v_pending.image_hash,
    p_companion_message => v_pending.companion_message,
    p_account_id => p_account_id,
    p_occurred_at => v_pending.occurred_at
  );

  return jsonb_build_object('record_type', 'expense', 'transaction', to_jsonb(v_tx));
end;
$$;

create or replace function public.archive_staging_record(
  p_staging_id uuid,
  p_domain_key text,
  p_amount numeric default null,
  p_title text default null,
  p_platform text default null,
  p_category text default null,
  p_payment_method text default null,
  p_income_category text default null,
  p_record_date date default null,
  p_record_time time default null,
  p_occurred_at timestamptz default null,
  p_summary text default null,
  p_payload jsonb default '{}'::jsonb,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
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
        p_transaction_date => p_record_date,
        p_transaction_time => p_record_time,
        p_note => p_summary,
        p_is_large_transport => coalesce(p_category in ('transport', '出行') and p_amount >= 200, false),
        p_transport_type => case when p_category in ('transport', '出行') and p_amount >= 200 then '交通' else null end,
        p_source => 'ai_scan',
        p_image_url => v_staging.image_path,
        p_image_hash => v_staging.image_hash,
        p_companion_message => v_staging.companion_message,
        p_account_id => p_account_id,
        p_occurred_at => p_occurred_at
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
        p_income_date => p_record_date,
        p_note => p_summary,
        p_source => 'ai_scan',
        p_image_url => v_staging.image_path,
        p_image_hash => v_staging.image_hash,
        p_companion_message => v_staging.companion_message,
        p_account_id => p_account_id,
        p_occurred_at => p_occurred_at
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
        p_occurred_at,
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

revoke all on function public.save_transaction_with_account(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid, timestamptz) from public, anon;
revoke all on function public.save_income_with_account(uuid, text, text, numeric, date, text, text, text, text, text, uuid, timestamptz) from public, anon;
revoke all on function public.confirm_pending_transaction_with_account(uuid, text, numeric, text, text, text, text, text, uuid) from public, anon;
revoke all on function public.archive_staging_record(uuid, text, numeric, text, text, text, text, text, date, time, timestamptz, text, jsonb, uuid) from public, anon;
revoke all on function public.save_transaction_with_account(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid) from public, anon;
revoke all on function public.save_income_with_account(uuid, text, text, numeric, date, text, text, text, text, text, uuid) from public, anon;

grant execute on function public.save_transaction_with_account(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid, timestamptz) to authenticated;
grant execute on function public.save_income_with_account(uuid, text, text, numeric, date, text, text, text, text, text, uuid, timestamptz) to authenticated;
grant execute on function public.confirm_pending_transaction_with_account(uuid, text, numeric, text, text, text, text, text, uuid) to authenticated;
grant execute on function public.archive_staging_record(uuid, text, numeric, text, text, text, text, text, date, time, timestamptz, text, jsonb, uuid) to authenticated;
grant execute on function public.save_transaction_with_account(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid) to authenticated;
grant execute on function public.save_income_with_account(uuid, text, text, numeric, date, text, text, text, text, text, uuid) to authenticated;
