-- Account entry RPCs:
-- Keep balance-changing account entry writes inside database functions so the
-- frontend does not need to compose void + insert operations by hand.

create or replace function public.create_account_entry_for_record(
  p_account_id uuid,
  p_direction text,
  p_amount numeric,
  p_entry_type text,
  p_source_table text default null,
  p_source_id uuid default null,
  p_occurred_at timestamptz default now(),
  p_note text default null
)
returns public.account_entries
language plpgsql
security definer
set search_path = public
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
  )
  values (
    v_account.user_id,
    p_account_id,
    p_direction::public.account_entry_direction,
    p_amount,
    p_entry_type::public.account_entry_type,
    p_source_table,
    p_source_id,
    coalesce(p_occurred_at, now()),
    p_note
  )
  returning * into v_entry;

  return v_entry;
end;
$$;

create or replace function public.void_account_entries_for_record(
  p_source_table text,
  p_source_id uuid,
  p_reason text default 'source_deleted'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if p_source_table is null or p_source_id is null then
    return 0;
  end if;

  update public.account_entries
     set is_voided = true,
         voided_reason = coalesce(p_reason, 'source_deleted')
   where user_id = auth.uid()
     and source_table = p_source_table
     and source_id = p_source_id
     and is_voided = false;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.create_account_entry_for_record(uuid, text, numeric, text, text, uuid, timestamptz, text) from public;
revoke all on function public.void_account_entries_for_record(text, uuid, text) from public;

grant execute on function public.create_account_entry_for_record(uuid, text, numeric, text, text, uuid, timestamptz, text) to authenticated;
grant execute on function public.void_account_entries_for_record(text, uuid, text) to authenticated;
