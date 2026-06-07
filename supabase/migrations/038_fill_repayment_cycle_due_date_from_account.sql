update public.account_repayment_cycles cycle
set due_date = make_date(
      substring(cycle.cycle_month from 1 for 4)::int,
      substring(cycle.cycle_month from 6 for 2)::int,
      least(
        account.payment_due_day,
        extract(day from (
          make_date(
            substring(cycle.cycle_month from 1 for 4)::int,
            substring(cycle.cycle_month from 6 for 2)::int,
            1
          ) + interval '1 month - 1 day'
        ))::int
      )
    ),
    updated_at = now()
from public.accounts account
where account.id = cycle.account_id
  and cycle.due_date is null
  and cycle.cycle_month ~ '^[0-9]{4}-[0-9]{2}$'
  and account.payment_due_day is not null
  and account.payment_due_day between 1 and 31;
