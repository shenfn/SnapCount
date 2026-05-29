-- Atomic record + account-entry RPCs.
-- These functions wrap record writes and account-entry writes in one database
-- transaction, avoiding half-saved UI flows when a later write fails.

create or replace function public.resolve_account_entry_direction(
  p_account_id uuid,
  p_entry_type text,
  p_fallback_direction text
)
returns public.account_entry_direction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type public.account_type;
begin
  select type
    into v_type
  from public.accounts
  where id = p_account_id
    and user_id = auth.uid();

  if p_entry_type = 'expense' and v_type in ('credit_card', 'credit_line') then
    return 'in'::public.account_entry_direction;
  end if;

  return p_fallback_direction::public.account_entry_direction;
end;
$$;

create or replace function public.save_transaction_with_account(
  p_id uuid default null,
  p_amount numeric default null,
  p_merchant_name text default null,
  p_platform text default null,
  p_category text default null,
  p_payment_method text default null,
  p_transaction_date date default current_date,
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
set search_path = public
as $$
declare
  v_row public.transactions%rowtype;
  v_direction public.account_entry_direction;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be greater than 0';
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
      source,
      image_url,
      image_hash,
      companion_message,
      note,
      is_large_transport,
      transport_type,
      user_id,
      account_id
    )
    values (
      'expense',
      p_amount,
      p_merchant_name,
      p_platform,
      p_category,
      p_payment_method,
      'done',
      coalesce(p_transaction_date, current_date),
      coalesce(p_transaction_time, localtime(0)),
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
           transaction_date = coalesce(p_transaction_date, current_date),
           transaction_time = p_transaction_time,
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

    if not found then
      raise exception 'transaction not found or permission denied';
    end if;
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
      (coalesce(p_transaction_date, current_date)::text || 'T00:00:00+08:00')::timestamptz,
      case when p_id is null then '手动创建支出' else '手动编辑支出' end
    );
  end if;

  return v_row;
end;
$$;

create or replace function public.save_income_with_account(
  p_id uuid default null,
  p_category text default null,
  p_source_name text default null,
  p_amount numeric default null,
  p_income_date date default current_date,
  p_note text default null,
  p_source text default 'manual',
  p_image_url text default null,
  p_image_hash text default null,
  p_companion_message text default null,
  p_account_id uuid default null
)
returns public.income_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.income_records%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be greater than 0';
  end if;

  if p_id is null then
    insert into public.income_records (
      category,
      source_name,
      amount,
      income_date,
      note,
      source,
      image_url,
      image_hash,
      companion_message,
      user_id,
      account_id
    )
    values (
      p_category,
      p_source_name,
      p_amount,
      coalesce(p_income_date, current_date),
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
           income_date = coalesce(p_income_date, current_date),
           note = p_note,
           source = coalesce(p_source, source),
           image_url = coalesce(p_image_url, image_url),
           image_hash = coalesce(p_image_hash, image_hash),
           companion_message = coalesce(p_companion_message, companion_message),
           account_id = p_account_id
     where id = p_id
       and user_id = auth.uid()
     returning * into v_row;

    if not found then
      raise exception 'income record not found or permission denied';
    end if;
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
      (coalesce(p_income_date, current_date)::text || 'T00:00:00+08:00')::timestamptz,
      case when p_id is null then '手动创建收入' else '手动编辑收入' end
    );
  end if;

  return v_row;
end;
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
set search_path = public
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
    raise exception 'pending transaction not found or permission denied';
  end if;

  v_date := coalesce(v_pending.transaction_date, current_date);

  if p_entry_type = 'income' then
    select *
      into v_income
    from public.save_income_with_account(
      null,
      p_income_category,
      coalesce(nullif(p_merchant_or_source_name, ''), '收入'),
      p_amount,
      v_date,
      case when v_pending.image_url is not null then '由截图待补充转入收入' else null end,
      'ai_scan',
      v_pending.image_url,
      v_pending.image_hash,
      v_pending.companion_message,
      p_account_id
    );

    delete from public.transactions
    where id = v_pending.id
      and user_id = auth.uid();

    return jsonb_build_object('record_type', 'income', 'income_record', to_jsonb(v_income));
  end if;

  if p_entry_type <> 'expense' then
    raise exception 'entry_type must be expense or income';
  end if;

  select *
    into v_tx
  from public.save_transaction_with_account(
    v_pending.id,
    p_amount,
    coalesce(nullif(p_merchant_or_source_name, ''), coalesce(p_platform, '其他') || '消费'),
    p_platform,
    p_category,
    p_payment_method,
    v_date,
    v_pending.transaction_time,
    v_pending.note,
    coalesce(p_category = '出行' and p_amount >= 200, false),
    case when p_category = '出行' and p_amount >= 200 then '交通' else null end,
    coalesce(v_pending.source, 'ai_scan'),
    v_pending.image_url,
    v_pending.image_hash,
    v_pending.companion_message,
    p_account_id
  );

  return jsonb_build_object('record_type', 'expense', 'transaction', to_jsonb(v_tx));
end;
$$;

revoke all on function public.resolve_account_entry_direction(uuid, text, text) from public;
revoke all on function public.save_transaction_with_account(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid) from public;
revoke all on function public.save_income_with_account(uuid, text, text, numeric, date, text, text, text, text, text, uuid) from public;
revoke all on function public.confirm_pending_transaction_with_account(uuid, text, numeric, text, text, text, text, text, uuid) from public;

grant execute on function public.resolve_account_entry_direction(uuid, text, text) to authenticated;
grant execute on function public.save_transaction_with_account(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid) to authenticated;
grant execute on function public.save_income_with_account(uuid, text, text, numeric, date, text, text, text, text, text, uuid) to authenticated;
grant execute on function public.confirm_pending_transaction_with_account(uuid, text, numeric, text, text, text, text, text, uuid) to authenticated;
