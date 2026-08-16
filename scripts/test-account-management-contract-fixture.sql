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
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end;
$$;

create schema auth;
grant usage on schema auth, public to anon, authenticated, service_role;

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

create type public.account_type as enum (
  'cash', 'wallet_balance', 'debit_card', 'credit_card', 'credit_line', 'other'
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  type public.account_type not null default 'other',
  institution text,
  last4 text,
  currency text not null default 'CNY',
  initial_balance numeric(14,2) not null default 0,
  current_balance numeric(14,2) not null default 0,
  snapshot_balance numeric(14,2),
  snapshot_at timestamptz,
  source_record_table text,
  source_record_id uuid,
  bill_day integer,
  payment_due_day integer,
  auto_debit_account_id uuid references public.accounts(id) on delete set null,
  auto_confirm_repayment boolean not null default false,
  grace_period_days integer not null default 0,
  last_reconciled_at timestamptz,
  is_default_expense boolean not null default false,
  is_default_income boolean not null default false,
  is_archived boolean not null default false,
  sort_order integer not null default 0,
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
  is_voided boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.account_repayment_cycles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  account_id uuid not null references public.accounts(id),
  cycle_month text not null,
  status text not null default 'pending',
  auto_debit_account_id uuid references public.accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.liability_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  account_id uuid not null references public.accounts(id),
  debit_account_id uuid references public.accounts(id) on delete set null,
  amount numeric(14,2) not null default 1,
  created_at timestamptz not null default now()
);

grant select, insert, update, delete on public.accounts to authenticated;
grant select, insert, update, delete on public.account_entries to authenticated;
grant select, insert, update, delete on public.account_repayment_cycles to authenticated;
grant select, insert, update, delete on public.liability_payments to authenticated;

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into public.accounts (
  id, user_id, name, type, initial_balance, current_balance,
  is_default_expense, is_default_income, is_archived, sort_order, created_at
) values
  ('66000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '第一默认账户', 'debit_card', 100, 100, true, true, false, 0, '2026-01-01T00:00:00Z'),
  ('66000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '重复默认账户', 'wallet_balance', 20, 20, true, false, false, 1, '2026-01-02T00:00:00Z'),
  ('66000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', '归档默认账户', 'cash', 30, 30, true, true, true, 2, '2026-01-03T00:00:00Z'),
  ('66000000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', '自动扣款资产', 'debit_card', 500, 500, false, false, false, 3, '2026-01-04T00:00:00Z'),
  ('66000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', '负债账户', 'credit_card', 200, 200, false, false, false, 4, '2026-01-05T00:00:00Z'),
  ('66000000-0000-4000-8000-000000000006', '11111111-1111-4111-8111-111111111111', '空账户', 'cash', 0, 0, false, false, false, 5, '2026-01-06T00:00:00Z'),
  ('66000000-0000-4000-8000-000000000007', '22222222-2222-4222-8222-222222222222', '其他用户账户', 'cash', 70, 70, true, true, false, 0, '2026-01-01T00:00:00Z');

update public.accounts
set auto_debit_account_id = '66000000-0000-4000-8000-000000000004'
where id = '66000000-0000-4000-8000-000000000005';

insert into public.account_entries (
  id, user_id, account_id, direction, amount, entry_type
) values (
  '66100000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '66000000-0000-4000-8000-000000000001',
  'in', 1, 'income'
);

insert into public.account_repayment_cycles (
  id, user_id, account_id, cycle_month, status, auto_debit_account_id
) values
  ('66200000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '66000000-0000-4000-8000-000000000005', '2026-08', 'pending', '66000000-0000-4000-8000-000000000004'),
  ('66200000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '66000000-0000-4000-8000-000000000005', '2026-07', 'paid', '66000000-0000-4000-8000-000000000004');

insert into public.liability_payments (
  id, user_id, account_id, debit_account_id, amount
) values (
  '66300000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '66000000-0000-4000-8000-000000000005',
  '66000000-0000-4000-8000-000000000004',
  10
);
