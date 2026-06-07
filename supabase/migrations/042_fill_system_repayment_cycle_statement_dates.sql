update public.account_repayment_cycles cycle
set statement_start_date = make_date(
      extract(year from ((cycle.cycle_month || '-01')::date - interval '1 month'))::int,
      extract(month from ((cycle.cycle_month || '-01')::date - interval '1 month'))::int,
      least(
        account.payment_due_day,
        extract(day from (((cycle.cycle_month || '-01')::date - interval '1 month') + interval '1 month - 1 day'))::int
      )
    ) + 1,
    statement_end_date = coalesce(
      cycle.statement_end_date,
      make_date(
        extract(year from (cycle.cycle_month || '-01')::date)::int,
        extract(month from (cycle.cycle_month || '-01')::date)::int,
        least(
          account.payment_due_day,
          extract(day from (((cycle.cycle_month || '-01')::date) + interval '1 month - 1 day'))::int
        )
      )
    ),
    updated_at = now()
from public.accounts account
where account.id = cycle.account_id
  and cycle.source = 'system'
  and account.payment_due_day is not null
  and (cycle.statement_start_date is null or cycle.statement_end_date is null);
