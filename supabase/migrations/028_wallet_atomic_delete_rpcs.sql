-- Atomic delete RPCs for account-bound records.
-- Deleting a source record and voiding its account entries must succeed or fail
-- together so account balances cannot drift.

create or replace function public.delete_transaction_with_account(
  p_id uuid
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.transactions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_id is null then
    raise exception 'transaction id is required';
  end if;

  select *
    into v_row
  from public.transactions
  where id = p_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'transaction not found or permission denied';
  end if;

  perform public.void_account_entries_for_record('transactions', p_id, 'transaction_deleted');

  delete from public.transactions
  where id = p_id
    and user_id = auth.uid();

  return v_row;
end;
$$;

create or replace function public.delete_income_with_account(
  p_id uuid
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

  if p_id is null then
    raise exception 'income record id is required';
  end if;

  select *
    into v_row
  from public.income_records
  where id = p_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'income record not found or permission denied';
  end if;

  perform public.void_account_entries_for_record('income_records', p_id, 'income_deleted');

  delete from public.income_records
  where id = p_id
    and user_id = auth.uid();

  return v_row;
end;
$$;

revoke all on function public.delete_transaction_with_account(uuid) from public;
revoke all on function public.delete_income_with_account(uuid) from public;

grant execute on function public.delete_transaction_with_account(uuid) to authenticated;
grant execute on function public.delete_income_with_account(uuid) to authenticated;
