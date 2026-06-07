alter table public.accounts
  add column if not exists grace_period_days integer not null default 0,
  add column if not exists last_reconciled_at timestamptz;

alter table public.accounts
  drop constraint if exists accounts_grace_period_days_range,
  add constraint accounts_grace_period_days_range
    check (grace_period_days between 0 and 60);

alter table public.account_repayment_cycles
  add column if not exists original_statement_amount numeric(14,2),
  add column if not exists min_payment_amount numeric(14,2),
  add column if not exists refund_applied_amount numeric(14,2) not null default 0,
  add column if not exists evidence_record_id uuid references public.data_records(id) on delete set null,
  add column if not exists confidence numeric(5,4),
  add column if not exists statement_source_priority integer not null default 0;

alter table public.account_repayment_cycles
  drop constraint if exists account_repayment_cycles_status_check,
  add constraint account_repayment_cycles_status_check
    check (status in (
      'draft_estimated',
      'pending',
      'due_today',
      'overdue_unconfirmed',
      'partial_paid',
      'minimum_paid',
      'carried_over',
      'paid',
      'ignored',
      'historical_unconfirmed',
      'reconciled',
      'replaced',
      'reopened'
    ));

alter table public.account_repayment_cycles
  drop constraint if exists repayment_cycles_original_statement_amount_nonnegative,
  add constraint repayment_cycles_original_statement_amount_nonnegative
    check (original_statement_amount is null or original_statement_amount >= 0);

alter table public.account_repayment_cycles
  drop constraint if exists repayment_cycles_min_payment_amount_nonnegative,
  add constraint repayment_cycles_min_payment_amount_nonnegative
    check (min_payment_amount is null or min_payment_amount >= 0);

alter table public.account_repayment_cycles
  drop constraint if exists repayment_cycles_refund_applied_amount_nonnegative,
  add constraint repayment_cycles_refund_applied_amount_nonnegative
    check (refund_applied_amount >= 0);

update public.account_repayment_cycles
set original_statement_amount = statement_amount
where original_statement_amount is null;

comment on column public.accounts.grace_period_days is
  'Days after due date before a liability statement is downgraded from active reminder to historical confirmation.';

comment on column public.accounts.last_reconciled_at is
  'Last account reconciliation or chapter opening timestamp. Entries before this time should not mutate current balance or system-estimated statements.';

comment on column public.account_repayment_cycles.original_statement_amount is
  'Original statement amount from screenshot, manual confirmation, or first system estimate before refunds or later adjustments.';

comment on column public.account_repayment_cycles.min_payment_amount is
  'Minimum payment amount. If paid amount reaches this value, the statement can be treated as minimum-paid instead of risky partial-paid.';

comment on column public.account_repayment_cycles.refund_applied_amount is
  'Refund amount applied to reduce this statement. It must never make remaining_amount negative.';

create or replace function public.ensure_liability_repayment_cycles(
  p_cycle_month text default null
)
returns setof public.account_repayment_cycles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_month text := coalesce(p_cycle_month, to_char(current_date, 'YYYY-MM'));
  v_month_start date;
  v_month_end date;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if v_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'cycle month must be YYYY-MM';
  end if;

  v_month_start := (v_month || '-01')::date;
  v_month_end := (v_month_start + interval '1 month - 1 day')::date;

  update public.account_repayment_cycles cycle
     set status = 'historical_unconfirmed',
         updated_at = now()
    from public.accounts account
   where cycle.account_id = account.id
     and cycle.user_id = auth.uid()
     and account.user_id = auth.uid()
     and cycle.status = 'overdue_unconfirmed'
     and cycle.due_date is not null
     and cycle.due_date + coalesce(account.grace_period_days, 0) < current_date
     and cycle.source = 'system'
     and cycle.paid_amount = 0;

  delete from public.account_repayment_cycles cycle
  where cycle.user_id = auth.uid()
    and cycle.cycle_month = v_month
    and cycle.source = 'system'
    and cycle.status in ('pending', 'due_today', 'overdue_unconfirmed')
    and cycle.paid_amount = 0
    and not exists (
      select 1
      from public.accounts account
      join public.account_entries entry on entry.account_id = account.id
      where account.id = cycle.account_id
        and account.user_id = auth.uid()
        and account.type in ('credit_card', 'credit_line')
        and account.is_archived = false
        and account.bill_day is not null
        and account.payment_due_day is not null
        and entry.user_id = account.user_id
        and entry.is_voided = false
        and entry.entry_type = 'expense'
        and entry.direction = 'in'
        and entry.source_table = 'transactions'
        and (
          account.last_reconciled_at is null
          or entry.occurred_at > account.last_reconciled_at
        )
        and (entry.occurred_at at time zone 'Asia/Shanghai')::date >
          make_date(
            extract(year from (v_month_start - interval '1 month'))::int,
            extract(month from (v_month_start - interval '1 month'))::int,
            least(
              account.bill_day,
              extract(day from ((v_month_start - interval '1 month') + interval '1 month - 1 day'))::int
            )
          )
        and (entry.occurred_at at time zone 'Asia/Shanghai')::date <=
          make_date(
            extract(year from v_month_start)::int,
            extract(month from v_month_start)::int,
            least(account.bill_day, extract(day from v_month_end)::int)
          )
    );

  insert into public.account_repayment_cycles (
    user_id,
    account_id,
    cycle_month,
    statement_start_date,
    statement_end_date,
    due_date,
    statement_amount,
    original_statement_amount,
    paid_amount,
    remaining_amount,
    carried_over_amount,
    status,
    auto_debit_account_id,
    auto_confirm_repayment,
    source,
    note,
    statement_source_priority
  )
  select
    account.user_id,
    account.id,
    v_month,
    make_date(
      extract(year from (v_month_start - interval '1 month'))::int,
      extract(month from (v_month_start - interval '1 month'))::int,
      least(
        account.bill_day,
        extract(day from ((v_month_start - interval '1 month') + interval '1 month - 1 day'))::int
      )
    ) + 1,
    make_date(
      extract(year from v_month_start)::int,
      extract(month from v_month_start)::int,
      least(account.bill_day, extract(day from v_month_end)::int)
    ),
    make_date(
      extract(year from v_month_start)::int,
      extract(month from v_month_start)::int,
      least(account.payment_due_day, extract(day from v_month_end)::int)
    ),
    sum(entry.amount)::numeric(14,2),
    sum(entry.amount)::numeric(14,2),
    0,
    sum(entry.amount)::numeric(14,2),
    0,
    case
      when make_date(
        extract(year from v_month_start)::int,
        extract(month from v_month_start)::int,
        least(account.payment_due_day, extract(day from v_month_end)::int)
      ) = current_date then 'due_today'
      when make_date(
        extract(year from v_month_start)::int,
        extract(month from v_month_start)::int,
        least(account.payment_due_day, extract(day from v_month_end)::int)
      ) < current_date then 'overdue_unconfirmed'
      else 'pending'
    end,
    account.auto_debit_account_id,
    account.auto_confirm_repayment,
    'system',
    '按已绑定消费流水估算',
    10
  from public.accounts account
  join public.account_entries entry on entry.account_id = account.id
  where account.user_id = auth.uid()
    and account.type in ('credit_card', 'credit_line')
    and account.is_archived = false
    and account.bill_day is not null
    and account.payment_due_day is not null
    and entry.user_id = account.user_id
    and entry.is_voided = false
    and entry.entry_type = 'expense'
    and entry.direction = 'in'
    and entry.source_table = 'transactions'
    and (
      account.last_reconciled_at is null
      or entry.occurred_at > account.last_reconciled_at
    )
    and (entry.occurred_at at time zone 'Asia/Shanghai')::date >
      make_date(
        extract(year from (v_month_start - interval '1 month'))::int,
        extract(month from (v_month_start - interval '1 month'))::int,
        least(
          account.bill_day,
          extract(day from ((v_month_start - interval '1 month') + interval '1 month - 1 day'))::int
        )
      )
    and (entry.occurred_at at time zone 'Asia/Shanghai')::date <=
      make_date(
        extract(year from v_month_start)::int,
        extract(month from v_month_start)::int,
        least(account.bill_day, extract(day from v_month_end)::int)
      )
  group by account.id, v_month_start, v_month_end
  having sum(entry.amount) > 0
  on conflict (account_id, cycle_month) do update
     set statement_start_date = excluded.statement_start_date,
         statement_end_date = excluded.statement_end_date,
         due_date = excluded.due_date,
         auto_debit_account_id = excluded.auto_debit_account_id,
         auto_confirm_repayment = excluded.auto_confirm_repayment,
         statement_amount = case
           when account_repayment_cycles.source = 'system'
             and account_repayment_cycles.status in ('pending', 'due_today', 'overdue_unconfirmed')
             and account_repayment_cycles.paid_amount = 0
           then excluded.statement_amount
           else account_repayment_cycles.statement_amount
         end,
         original_statement_amount = case
           when account_repayment_cycles.original_statement_amount is null
             and account_repayment_cycles.source = 'system'
           then excluded.original_statement_amount
           else account_repayment_cycles.original_statement_amount
         end,
         remaining_amount = case
           when account_repayment_cycles.source = 'system'
             and account_repayment_cycles.status in ('pending', 'due_today', 'overdue_unconfirmed')
             and account_repayment_cycles.paid_amount = 0
           then excluded.remaining_amount
           else account_repayment_cycles.remaining_amount
         end,
         status = case
           when account_repayment_cycles.status in ('paid', 'ignored', 'partial_paid', 'carried_over', 'historical_unconfirmed')
           then account_repayment_cycles.status
           when account_repayment_cycles.source = 'system'
           then excluded.status
           else account_repayment_cycles.status
         end,
         note = case
           when account_repayment_cycles.source = 'system'
           then excluded.note
           else account_repayment_cycles.note
         end,
         updated_at = now();

  return query
  select *
  from public.account_repayment_cycles
  where user_id = auth.uid()
    and cycle_month = v_month
  order by due_date asc nulls last, created_at desc;
end;
$$;

revoke all on function public.ensure_liability_repayment_cycles(text) from public;
grant execute on function public.ensure_liability_repayment_cycles(text) to authenticated;
