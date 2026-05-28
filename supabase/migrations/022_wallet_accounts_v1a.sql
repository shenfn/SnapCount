create extension if not exists "uuid-ossp";

do $$
begin
  if not exists (select 1 from pg_type where typname = 'account_type') then
    create type public.account_type as enum (
      'cash',
      'wallet_balance',
      'debit_card',
      'credit_card',
      'credit_line',
      'other'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'account_entry_direction') then
    create type public.account_entry_direction as enum ('in', 'out');
  end if;

  if not exists (select 1 from pg_type where typname = 'account_entry_type') then
    create type public.account_entry_type as enum (
      'opening_balance',
      'snapshot_initialization',
      'expense',
      'income',
      'transfer',
      'adjustment'
    );
  end if;
end $$;

create table if not exists public.accounts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  type public.account_type not null default 'other',
  institution text,
  last4 text,
  currency text not null default 'CNY',
  initial_balance numeric(14,2) not null default 0 check (initial_balance >= 0),
  current_balance numeric(14,2) not null default 0 check (current_balance >= 0),
  snapshot_balance numeric(14,2) check (snapshot_balance is null or snapshot_balance >= 0),
  snapshot_at timestamptz,
  source_record_table text,
  source_record_id uuid,
  is_default_expense boolean not null default false,
  is_default_income boolean not null default false,
  is_archived boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_last4_format check (last4 is null or last4 ~ '^[0-9]{4}$')
);

create table if not exists public.account_entries (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  direction public.account_entry_direction not null,
  amount numeric(14,2) not null check (amount > 0),
  entry_type public.account_entry_type not null,
  source_table text,
  source_id uuid,
  occurred_at timestamptz not null default now(),
  note text,
  is_voided boolean not null default false,
  voided_reason text,
  created_at timestamptz not null default now()
);

create index if not exists idx_accounts_user_archived_sort
  on public.accounts (user_id, is_archived, sort_order, created_at desc);

create index if not exists idx_accounts_user_type
  on public.accounts (user_id, type);

create index if not exists idx_account_entries_account_time
  on public.account_entries (account_id, occurred_at desc);

create index if not exists idx_account_entries_source
  on public.account_entries (source_table, source_id);

create unique index if not exists uq_account_entries_active_source
  on public.account_entries (source_table, source_id, entry_type, account_id)
  where is_voided = false and source_table is not null and source_id is not null;

alter table public.data_records
  add column if not exists linked_account_id uuid references public.accounts(id) on delete set null,
  add column if not exists account_snapshot_kind text check (account_snapshot_kind is null or account_snapshot_kind in ('asset', 'liability')),
  add column if not exists snapshot_balance numeric(14,2) check (snapshot_balance is null or snapshot_balance >= 0),
  add column if not exists snapshot_at timestamptz;

create index if not exists idx_data_records_linked_account
  on public.data_records (linked_account_id);

alter table public.accounts enable row level security;
alter table public.account_entries enable row level security;

drop policy if exists "accounts_user_access" on public.accounts;
create policy "accounts_user_access"
  on public.accounts
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "account_entries_user_access" on public.account_entries;
create policy "account_entries_user_access"
  on public.account_entries
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.accounts to authenticated;
grant select, insert, update, delete on table public.account_entries to authenticated;
grant all privileges on table public.accounts, public.account_entries to service_role;
