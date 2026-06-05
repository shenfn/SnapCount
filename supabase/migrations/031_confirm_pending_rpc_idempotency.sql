alter table public.income_records
  add column if not exists source_pending_transaction_id uuid;

create unique index if not exists idx_income_records_source_pending_tx_unique
  on public.income_records (source_pending_transaction_id)
  where source_pending_transaction_id is not null;

comment on column public.income_records.source_pending_transaction_id is
  'Original pending transactions.id used when confirming a screenshot into income; retained for idempotent retries.';

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

    v_date := coalesce(v_pending.transaction_date, current_date);

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

  v_date := coalesce(v_pending.transaction_date, current_date);

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
