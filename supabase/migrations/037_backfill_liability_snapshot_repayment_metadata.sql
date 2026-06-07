-- Backfill liability account repayment metadata from existing wallet snapshots.
-- Wallet snapshots already carry due_date/bill_day, but early account binding
-- only copied balance fields into accounts.

update public.data_records dr
set payload_jsonb = jsonb_set(
    dr.payload_jsonb,
    '{due_date}',
    to_jsonb(
      (
        extract(year from dr.occurred_at at time zone 'Asia/Shanghai')::int::text
        || substring(dr.payload_jsonb->>'due_date' from 5)
      )
    ),
    true
  )
where dr.domain_key = 'wallet'
  and dr.payload_jsonb->>'record_kind' = 'liability_snapshot'
  and dr.payload_jsonb->>'due_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  and dr.occurred_at is not null
  and abs(
    substring(dr.payload_jsonb->>'due_date' from 1 for 4)::int
    - extract(year from dr.occurred_at at time zone 'Asia/Shanghai')::int
  ) > 1;

with snapshot_meta as (
  select
    dr.id as record_id,
    dr.user_id,
    dr.linked_account_id,
    dr.occurred_at,
    dr.payload_jsonb,
    case
      when dr.payload_jsonb->>'bill_day' ~ '^[0-9]+$'
      then least(greatest((dr.payload_jsonb->>'bill_day')::int, 1), 31)
      else null
    end as bill_day,
    case
      when dr.payload_jsonb->>'due_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      then extract(day from (dr.payload_jsonb->>'due_date')::date)::int
      when dr.payload_jsonb->>'payment_due_day' ~ '^[0-9]+$'
      then least(greatest((dr.payload_jsonb->>'payment_due_day')::int, 1), 31)
      when dr.payload_jsonb->>'due_day' ~ '^[0-9]+$'
      then least(greatest((dr.payload_jsonb->>'due_day')::int, 1), 31)
      when dr.payload_jsonb->>'repayment_day' ~ '^[0-9]+$'
      then least(greatest((dr.payload_jsonb->>'repayment_day')::int, 1), 31)
      else null
    end as payment_due_day
  from public.data_records dr
  where dr.domain_key = 'wallet'
    and dr.linked_account_id is not null
    and dr.payload_jsonb->>'record_kind' = 'liability_snapshot'
)
update public.accounts account
set bill_day = coalesce(snapshot_meta.bill_day, account.bill_day),
    payment_due_day = coalesce(snapshot_meta.payment_due_day, account.payment_due_day),
    updated_at = now()
from snapshot_meta
where account.id = snapshot_meta.linked_account_id
  and account.user_id = snapshot_meta.user_id
  and account.type in ('credit_card', 'credit_line');

with snapshot_cycle_raw as (
  select
    dr.user_id,
    dr.linked_account_id as account_id,
    coalesce(
      nullif(substring(dr.payload_jsonb->>'cycle_month' from '^[0-9]{4}-[0-9]{2}'), ''),
      nullif(substring(dr.payload_jsonb->>'statement_month' from '^[0-9]{4}-[0-9]{2}'), ''),
      nullif(substring(dr.payload_jsonb->>'bill_month' from '^[0-9]{4}-[0-9]{2}'), ''),
      nullif(substring(dr.payload_jsonb->>'due_date' from '^[0-9]{4}-[0-9]{2}'), ''),
      to_char(dr.occurred_at at time zone 'Asia/Shanghai', 'YYYY-MM')
    ) as cycle_month,
    case
      when dr.payload_jsonb->>'due_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      then (dr.payload_jsonb->>'due_date')::date
      else null
    end as due_date,
    greatest(coalesce((dr.payload_jsonb->>'snapshot_balance')::numeric, (dr.payload_jsonb->>'amount')::numeric, 0), 0) as amount,
    case when dr.payload_jsonb->>'status' = 'paid' then 'paid' else 'pending' end as status
  from public.data_records dr
  join public.accounts account on account.id = dr.linked_account_id
  where dr.domain_key = 'wallet'
    and dr.linked_account_id is not null
    and dr.payload_jsonb->>'record_kind' = 'liability_snapshot'
    and account.type in ('credit_card', 'credit_line')
),
snapshot_cycles as (
  select distinct on (account_id, cycle_month)
    user_id,
    account_id,
    cycle_month,
    due_date,
    amount,
    status
  from snapshot_cycle_raw
  where cycle_month is not null
  order by
    account_id,
    cycle_month,
    case when status = 'paid' then 1 else 0 end desc,
    due_date desc nulls last,
    amount desc
)
insert into public.account_repayment_cycles (
  user_id,
  account_id,
  cycle_month,
  statement_end_date,
  due_date,
  statement_amount,
  paid_amount,
  remaining_amount,
  carried_over_amount,
  status,
  source,
  note
)
select
  user_id,
  account_id,
  cycle_month,
  due_date,
  due_date,
  amount,
  case when status = 'paid' then amount else 0 end,
  case when status = 'paid' then 0 else amount end,
  0,
  status,
  'screenshot',
  case when status = 'paid' then '历史快照显示已还款' else '历史快照生成待还周期' end
from snapshot_cycles
where amount > 0
on conflict (account_id, cycle_month) do update
   set statement_end_date = coalesce(excluded.statement_end_date, account_repayment_cycles.statement_end_date),
       due_date = coalesce(excluded.due_date, account_repayment_cycles.due_date),
       statement_amount = case
         when account_repayment_cycles.status in ('pending', 'due_today', 'overdue_unconfirmed')
           and account_repayment_cycles.paid_amount = 0
         then excluded.statement_amount
         else account_repayment_cycles.statement_amount
       end,
       remaining_amount = case
         when account_repayment_cycles.status in ('pending', 'due_today', 'overdue_unconfirmed')
           and account_repayment_cycles.paid_amount = 0
         then excluded.remaining_amount
         else account_repayment_cycles.remaining_amount
       end,
       status = case
         when account_repayment_cycles.status in ('paid', 'ignored', 'partial_paid', 'carried_over')
         then account_repayment_cycles.status
         else excluded.status
       end,
       source = case
         when account_repayment_cycles.source = 'system' then excluded.source
         else account_repayment_cycles.source
       end,
       updated_at = now();
