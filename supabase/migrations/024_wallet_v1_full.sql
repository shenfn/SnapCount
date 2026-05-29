-- ════════════════════════════════════════════════════════════════════
-- 024_wallet_v1_full.sql
-- Wallet V1：支出/收入账户绑定 + 中转站账户候选 + 余额自动维护 trigger
-- ════════════════════════════════════════════════════════════════════

-- 1. transactions 增加 account_id（实际出资账户）
alter table public.transactions
  add column if not exists account_id uuid references public.accounts(id) on delete set null;

create index if not exists idx_transactions_account
  on public.transactions(account_id);

-- 2. income_records 增加 account_id（到账账户）
alter table public.income_records
  add column if not exists account_id uuid references public.accounts(id) on delete set null;

create index if not exists idx_income_records_account
  on public.income_records(account_id);

-- 3. staging_records 增加 AI 账户推断 + 候选 + 用户纠错记忆
alter table public.staging_records
  add column if not exists payment_channel jsonb,
  add column if not exists funding_source jsonb,
  add column if not exists account_candidates jsonb,
  add column if not exists account_inference jsonb,
  add column if not exists requires_account_review boolean not null default false;

-- 4. 余额约束放宽：允许信用账户出现暂时为零或负值（trigger 维护过程可能短暂越界）
alter table public.accounts drop constraint if exists accounts_current_balance_check;
alter table public.accounts drop constraint if exists accounts_initial_balance_check;

-- 5. 余额自动维护：account_entries 触发器
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

drop trigger if exists tr_account_entries_balance on public.account_entries;
create trigger tr_account_entries_balance
  after insert or update or delete on public.account_entries
  for each row execute function public.maintain_account_balance();

-- 6. 余额重算函数（用于人工修复或测试）
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
