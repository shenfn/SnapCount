alter table public.accounts
  add column if not exists bill_day integer,
  add column if not exists payment_due_day integer,
  add column if not exists auto_debit_account_id uuid references public.accounts(id) on delete set null,
  add column if not exists auto_confirm_repayment boolean not null default false;

alter table public.accounts
  drop constraint if exists accounts_bill_day_range,
  add constraint accounts_bill_day_range
    check (bill_day is null or bill_day between 1 and 31);

alter table public.accounts
  drop constraint if exists accounts_payment_due_day_range,
  add constraint accounts_payment_due_day_range
    check (payment_due_day is null or payment_due_day between 1 and 31);

comment on column public.accounts.bill_day is
  'Monthly statement day for liability accounts.';

comment on column public.accounts.payment_due_day is
  'Monthly repayment due day for liability accounts.';

comment on column public.accounts.auto_debit_account_id is
  'Optional asset account used for automatic repayment deduction.';

comment on column public.accounts.auto_confirm_repayment is
  'Whether high-confidence repayment evidence can auto-confirm repayment reminders.';
