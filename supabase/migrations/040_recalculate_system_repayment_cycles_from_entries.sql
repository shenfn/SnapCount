with system_cycle_amounts as (
  select
    cycle.id,
    coalesce(sum(entry.amount), 0)::numeric(14,2) as amount
  from public.account_repayment_cycles cycle
  join public.accounts account on account.id = cycle.account_id
  left join public.account_entries entry on entry.account_id = cycle.account_id
    and entry.user_id = cycle.user_id
    and entry.is_voided = false
    and entry.entry_type = 'expense'
    and entry.direction = 'in'
    and entry.source_table = 'transactions'
    and account.payment_due_day is not null
    and cycle.due_date is not null
    and (entry.occurred_at at time zone 'Asia/Shanghai')::date >
      make_date(
        extract(year from ((cycle.cycle_month || '-01')::date - interval '1 month'))::int,
        extract(month from ((cycle.cycle_month || '-01')::date - interval '1 month'))::int,
        least(
          account.payment_due_day,
          extract(day from (((cycle.cycle_month || '-01')::date - interval '1 month') + interval '1 month - 1 day'))::int
        )
      )
    and (entry.occurred_at at time zone 'Asia/Shanghai')::date <= cycle.due_date
  where cycle.source = 'system'
    and cycle.status in ('pending', 'due_today', 'overdue_unconfirmed')
    and cycle.paid_amount = 0
  group by cycle.id
)
update public.account_repayment_cycles cycle
set statement_amount = system_cycle_amounts.amount,
    remaining_amount = system_cycle_amounts.amount,
    note = '按已绑定消费流水估算',
    updated_at = now()
from system_cycle_amounts
where cycle.id = system_cycle_amounts.id
  and system_cycle_amounts.amount > 0;

with system_cycle_amounts as (
  select
    cycle.id,
    coalesce(sum(entry.amount), 0)::numeric(14,2) as amount
  from public.account_repayment_cycles cycle
  join public.accounts account on account.id = cycle.account_id
  left join public.account_entries entry on entry.account_id = cycle.account_id
    and entry.user_id = cycle.user_id
    and entry.is_voided = false
    and entry.entry_type = 'expense'
    and entry.direction = 'in'
    and entry.source_table = 'transactions'
    and account.payment_due_day is not null
    and cycle.due_date is not null
    and (entry.occurred_at at time zone 'Asia/Shanghai')::date >
      make_date(
        extract(year from ((cycle.cycle_month || '-01')::date - interval '1 month'))::int,
        extract(month from ((cycle.cycle_month || '-01')::date - interval '1 month'))::int,
        least(
          account.payment_due_day,
          extract(day from (((cycle.cycle_month || '-01')::date - interval '1 month') + interval '1 month - 1 day'))::int
        )
      )
    and (entry.occurred_at at time zone 'Asia/Shanghai')::date <= cycle.due_date
  where cycle.source = 'system'
    and cycle.status in ('pending', 'due_today', 'overdue_unconfirmed')
    and cycle.paid_amount = 0
  group by cycle.id
)
delete from public.account_repayment_cycles cycle
using system_cycle_amounts
where cycle.id = system_cycle_amounts.id
  and system_cycle_amounts.amount <= 0;
