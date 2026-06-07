create table if not exists public.account_repayment_cycles (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  cycle_month text not null,
  statement_start_date date,
  statement_end_date date,
  due_date date,
  statement_amount numeric(14,2) not null default 0 check (statement_amount >= 0),
  paid_amount numeric(14,2) not null default 0 check (paid_amount >= 0),
  remaining_amount numeric(14,2) not null default 0 check (remaining_amount >= 0),
  carried_over_amount numeric(14,2) not null default 0 check (carried_over_amount >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'due_today', 'overdue_unconfirmed', 'partial_paid', 'carried_over', 'paid', 'ignored')),
  auto_debit_account_id uuid references public.accounts(id) on delete set null,
  auto_confirm_repayment boolean not null default false,
  source text not null default 'system'
    check (source in ('system', 'screenshot', 'manual', 'reconciliation')),
  note text,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (account_id, cycle_month)
);

create index if not exists idx_repayment_cycles_user_due
  on public.account_repayment_cycles (user_id, due_date, status);

create index if not exists idx_repayment_cycles_account_month
  on public.account_repayment_cycles (account_id, cycle_month);

alter table public.account_repayment_cycles enable row level security;

drop policy if exists "repayment_cycles_user_access" on public.account_repayment_cycles;
create policy "repayment_cycles_user_access"
  on public.account_repayment_cycles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update, delete on table public.account_repayment_cycles to authenticated;
grant all privileges on table public.account_repayment_cycles to service_role;

comment on table public.account_repayment_cycles is
  'Per-account liability repayment cycles for due reminders, partial repayment, carried-over balances, and repayment evidence matching.';
