\set ON_ERROR_STOP on

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end;
$$;

create schema auth;
grant usage on schema auth, public to anon, authenticated;

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table auth.users (
  id uuid primary key
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  type text not null,
  initial_balance numeric(14,2) not null default 0,
  current_balance numeric(14,2) not null default 0,
  auto_debit_account_id uuid,
  updated_at timestamptz not null default now()
);

create table public.account_repayment_cycles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  account_id uuid not null references public.accounts(id),
  cycle_month text not null,
  statement_amount numeric(14,2) not null default 0,
  paid_amount numeric(14,2) not null default 0,
  remaining_amount numeric(14,2) not null default 0,
  carried_over_amount numeric(14,2) not null default 0,
  min_payment_amount numeric(14,2),
  status text not null default 'pending',
  due_date date,
  auto_debit_account_id uuid,
  source text not null default 'system',
  note text,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.liability_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  account_id uuid not null references public.accounts(id),
  statement_id uuid references public.account_repayment_cycles(id),
  debit_account_id uuid references public.accounts(id),
  amount numeric(14,2) not null,
  overpayment_amount numeric(14,2) not null default 0,
  paid_at timestamptz not null,
  source text not null default 'manual',
  status text not null default 'confirmed',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.account_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  account_id uuid not null references public.accounts(id),
  direction text not null,
  amount numeric(14,2) not null,
  entry_type text not null,
  source_table text,
  source_id uuid,
  occurred_at timestamptz,
  note text,
  is_voided boolean not null default false,
  voided_reason text,
  created_at timestamptz not null default now()
);

create or replace function public.maintain_account_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  delta numeric(14,2);
begin
  if tg_op = 'INSERT' then
    if new.is_voided = false and new.entry_type <> 'snapshot_initialization' then
      delta := case when new.direction = 'in' then new.amount else -new.amount end;
      update public.accounts
         set current_balance = current_balance + delta,
             updated_at = now()
       where id = new.account_id;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
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

  if tg_op = 'DELETE' then
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

create trigger tr_account_entries_balance
after insert or update or delete on public.account_entries
for each row execute function public.maintain_account_balance();

grant select, insert, update, delete on table public.accounts to authenticated;
grant select, insert, update, delete on table public.account_repayment_cycles to authenticated;
grant select, insert, update, delete on table public.liability_payments to authenticated;
grant select, insert, update, delete on table public.account_entries to authenticated;
