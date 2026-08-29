\set ON_ERROR_STOP on

-- D-REMOTE-002 test-only fixture. It models the smallest existing finance
-- schema and deliberately does not provide the remote-sync objects yet.
-- The fixture is safe to run in a disposable PostgreSQL database only.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$$;

create schema if not exists auth;
grant usage on schema auth, public to anon, authenticated, service_role;

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table if not exists auth.users (
  id uuid primary key
);

do $$
begin
  if not exists (select 1 from pg_type where typname = 'account_type') then
    create type public.account_type as enum (
      'cash', 'wallet_balance', 'debit_card', 'credit_card', 'credit_line', 'other'
    );
  end if;
  if not exists (select 1 from pg_type where typname = 'account_entry_direction') then
    create type public.account_entry_direction as enum ('in', 'out');
  end if;
  if not exists (select 1 from pg_type where typname = 'account_entry_type') then
    create type public.account_entry_type as enum (
      'opening_balance', 'snapshot_initialization', 'expense', 'income', 'transfer', 'adjustment'
    );
  end if;
end;
$$;

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  type public.account_type not null default 'other',
  currency text not null default 'CNY',
  initial_balance numeric(14,2) not null default 0,
  current_balance numeric(14,2) not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('expense', 'income')),
  amount numeric(14,2) not null check (amount > 0),
  merchant_name text,
  platform text,
  category text,
  payment_method text,
  transaction_date date not null default current_date,
  transaction_time time,
  account_id uuid references public.accounts(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'done')),
  source text not null default 'ai_scan' check (source in ('ai_scan', 'manual')),
  note text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.account_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  direction public.account_entry_direction not null,
  amount numeric(14,2) not null check (amount > 0),
  entry_type public.account_entry_type not null,
  source_table text,
  source_id uuid,
  occurred_at timestamptz not null default now(),
  is_voided boolean not null default false,
  voided_reason text,
  created_at timestamptz not null default now()
);

alter table public.accounts enable row level security;
alter table public.transactions enable row level security;
alter table public.account_entries enable row level security;

drop policy if exists remote_fixture_accounts on public.accounts;
create policy remote_fixture_accounts on public.accounts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists remote_fixture_transactions on public.transactions;
create policy remote_fixture_transactions on public.transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists remote_fixture_entries on public.account_entries;
create policy remote_fixture_entries on public.account_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update, delete on public.accounts, public.transactions, public.account_entries
  to authenticated;

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222')
on conflict do nothing;

insert into public.accounts (id, user_id, name, type, initial_balance, current_balance)
values
  ('66000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '测试现金', 'cash', 1000, 1000),
  ('66000000-0000-4000-8000-000000000002', '22222222-2222-4222-8222-222222222222', '另一用户账户', 'cash', 500, 500)
on conflict (id) do nothing;

insert into public.transactions (
  id, user_id, type, amount, merchant_name, category, transaction_date, account_id
)
values (
  '77000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  'expense', 12.50, 'fixture 早餐', 'food', '2026-08-25',
  '66000000-0000-4000-8000-000000000001'
)
on conflict (id) do nothing;

insert into public.account_entries (
  id, user_id, account_id, direction, amount, entry_type, source_table, source_id
)
values (
  '88000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '66000000-0000-4000-8000-000000000001',
  'out', 12.50, 'expense', 'transactions',
  '77000000-0000-4000-8000-000000000001'
)
on conflict (id) do nothing;
