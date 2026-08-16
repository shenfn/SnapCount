\set ON_ERROR_STOP on

\ir test-repayment-contract-fixture.sql

do $$
begin
  if not exists (select 1 from pg_type where typname = 'account_type') then
    create type public.account_type as enum (
      'cash', 'wallet_balance', 'debit_card', 'credit_card', 'credit_line', 'other'
    );
  end if;
end;
$$;

alter table public.accounts
  alter column type type public.account_type using type::public.account_type;

alter table public.accounts
  add column institution text,
  add column last4 text,
  add column currency text not null default 'CNY',
  add column snapshot_balance numeric(14,2),
  add column snapshot_at timestamptz,
  add column source_record_table text,
  add column source_record_id uuid,
  add column is_default_expense boolean not null default false,
  add column is_default_income boolean not null default false,
  add column is_archived boolean not null default false,
  add column sort_order integer not null default 0,
  add column created_at timestamptz not null default now(),
  add column bill_day integer,
  add column payment_due_day integer,
  add column auto_confirm_repayment boolean not null default false,
  add column grace_period_days integer not null default 0,
  add column last_reconciled_at timestamptz;

create table public.data_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  domain_key text not null,
  occurred_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  title text,
  payload_jsonb jsonb not null default '{}'::jsonb,
  linked_account_id uuid references public.accounts(id),
  account_snapshot_kind text,
  snapshot_balance numeric(14,2),
  snapshot_at timestamptz
);

alter table public.account_repayment_cycles
  add column original_statement_amount numeric(14,2),
  add column min_payment_amount numeric(14,2),
  add column refund_applied_amount numeric(14,2) not null default 0,
  add column evidence_record_id uuid references public.data_records(id),
  add column confidence numeric(5,4),
  add column statement_source_priority integer not null default 0,
  add column auto_confirm_repayment boolean not null default false;

alter table public.liability_payments
  add column evidence_record_id uuid references public.data_records(id);

create unique index uq_wallet_fixture_cycle_account_month
  on public.account_repayment_cycles(account_id, cycle_month);

grant select, insert, update, delete on table public.data_records to authenticated;
