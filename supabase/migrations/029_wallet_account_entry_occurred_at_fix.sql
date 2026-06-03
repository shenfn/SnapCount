-- Fix account entry occurred_at to preserve the source transaction time.
-- Older account entries were written at midnight for the transaction date,
-- which makes account timelines look wrong even when the source transaction
-- has a real time.

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
  v_occurred_at timestamptz;
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

  v_occurred_at := (
    coalesce(v_row.transaction_date, current_date)::text
    || 'T'
    || coalesce(to_char(v_row.transaction_time, 'HH24:MI:SS'), '00:00:00')
    || '+08:00'
  )::timestamptz;

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
      v_occurred_at,
      case when p_id is null then '手动创建支出' else '手动编辑支出' end
    );
  end if;

  return v_row;
end;
$$;

update public.account_entries ae
set occurred_at = (
  t.transaction_date::text
  || 'T'
  || coalesce(to_char(t.transaction_time, 'HH24:MI:SS'), '00:00:00')
  || '+08:00'
)::timestamptz
from public.transactions t
where ae.source_table = 'transactions'
  and ae.source_id = t.id
  and t.transaction_date is not null
  and ae.occurred_at is distinct from (
    t.transaction_date::text
    || 'T'
    || coalesce(to_char(t.transaction_time, 'HH24:MI:SS'), '00:00:00')
    || '+08:00'
  )::timestamptz;
