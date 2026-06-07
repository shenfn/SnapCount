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
        and account.payment_due_day is not null
        and entry.user_id = account.user_id
        and entry.is_voided = false
        and entry.entry_type = 'expense'
        and entry.direction = 'in'
        and entry.source_table = 'transactions'
        and (entry.occurred_at at time zone 'Asia/Shanghai')::date >
          make_date(
            extract(year from (v_month_start - interval '1 month'))::int,
            extract(month from (v_month_start - interval '1 month'))::int,
            least(
              account.payment_due_day,
              extract(day from ((v_month_start - interval '1 month') + interval '1 month - 1 day'))::int
            )
          )
        and (entry.occurred_at at time zone 'Asia/Shanghai')::date <=
          make_date(
            extract(year from v_month_start)::int,
            extract(month from v_month_start)::int,
            least(account.payment_due_day, extract(day from v_month_end)::int)
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
    paid_amount,
    remaining_amount,
    carried_over_amount,
    status,
    auto_debit_account_id,
    auto_confirm_repayment,
    source,
    note
  )
  select
    account.user_id,
    account.id,
    v_month,
    make_date(
      extract(year from (v_month_start - interval '1 month'))::int,
      extract(month from (v_month_start - interval '1 month'))::int,
      least(
        account.payment_due_day,
        extract(day from ((v_month_start - interval '1 month') + interval '1 month - 1 day'))::int
      )
    ) + 1,
    make_date(
      extract(year from v_month_start)::int,
      extract(month from v_month_start)::int,
      least(account.payment_due_day, extract(day from v_month_end)::int)
    ),
    make_date(
      extract(year from v_month_start)::int,
      extract(month from v_month_start)::int,
      least(account.payment_due_day, extract(day from v_month_end)::int)
    ),
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
    '按已绑定消费流水估算'
  from public.accounts account
  join public.account_entries entry on entry.account_id = account.id
  where account.user_id = auth.uid()
    and account.type in ('credit_card', 'credit_line')
    and account.is_archived = false
    and account.payment_due_day is not null
    and entry.user_id = account.user_id
    and entry.is_voided = false
    and entry.entry_type = 'expense'
    and entry.direction = 'in'
    and entry.source_table = 'transactions'
    and (entry.occurred_at at time zone 'Asia/Shanghai')::date >
      make_date(
        extract(year from (v_month_start - interval '1 month'))::int,
        extract(month from (v_month_start - interval '1 month'))::int,
        least(
          account.payment_due_day,
          extract(day from ((v_month_start - interval '1 month') + interval '1 month - 1 day'))::int
        )
      )
    and (entry.occurred_at at time zone 'Asia/Shanghai')::date <=
      make_date(
        extract(year from v_month_start)::int,
        extract(month from v_month_start)::int,
        least(account.payment_due_day, extract(day from v_month_end)::int)
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
         remaining_amount = case
           when account_repayment_cycles.source = 'system'
             and account_repayment_cycles.status in ('pending', 'due_today', 'overdue_unconfirmed')
             and account_repayment_cycles.paid_amount = 0
           then excluded.remaining_amount
           else account_repayment_cycles.remaining_amount
         end,
         status = case
           when account_repayment_cycles.status in ('paid', 'ignored', 'partial_paid', 'carried_over')
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
