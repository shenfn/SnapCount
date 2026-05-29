-- Wallet balance semantics:
-- - account_entries.direction means account balance direction, not income/expense direction.
-- - snapshot_initialization is an audit marker for the opening snapshot and must not
--   change current_balance because accounts.initial_balance already stores that amount.

create or replace function public.maintain_account_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  delta numeric(14,2);
begin
  if TG_OP = 'INSERT' then
    if new.is_voided = false and new.entry_type <> 'snapshot_initialization' then
      delta := case when new.direction = 'in' then new.amount else -new.amount end;
      update public.accounts
        set current_balance = current_balance + delta,
            updated_at = now()
        where id = new.account_id;
    end if;
    return new;
  end if;

  if TG_OP = 'UPDATE' then
    if old.is_voided = false and old.entry_type <> 'snapshot_initialization' then
      delta := case when old.direction = 'in' then -old.amount else old.amount end;
      update public.accounts
        set current_balance = current_balance + delta,
            updated_at = now()
        where id = old.account_id;
    end if;
    if new.is_voided = false and new.entry_type <> 'snapshot_initialization' then
      delta := case when new.direction = 'in' then new.amount else -new.amount end;
      update public.accounts
        set current_balance = current_balance + delta,
            updated_at = now()
        where id = new.account_id;
    end if;
    return new;
  end if;

  if TG_OP = 'DELETE' then
    if old.is_voided = false and old.entry_type <> 'snapshot_initialization' then
      delta := case when old.direction = 'in' then -old.amount else old.amount end;
      update public.accounts
        set current_balance = current_balance + delta,
            updated_at = now()
        where id = old.account_id;
    end if;
    return old;
  end if;

  return null;
end;
$$;

create or replace function public.recalculate_account_balance(p_account_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  initial numeric(14,2);
  net numeric(14,2);
  result numeric(14,2);
begin
  select initial_balance into initial
  from public.accounts
  where id = p_account_id;

  if initial is null then
    return null;
  end if;

  select coalesce(sum(case when direction = 'in' then amount else -amount end), 0)
    into net
  from public.account_entries
  where account_id = p_account_id
    and is_voided = false
    and entry_type <> 'snapshot_initialization';

  result := initial + net;
  update public.accounts
    set current_balance = result,
        updated_at = now()
    where id = p_account_id;
  return result;
end;
$$;

revoke all on function public.recalculate_account_balance(uuid) from public;
grant execute on function public.recalculate_account_balance(uuid) to authenticated;
