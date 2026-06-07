-- A repayment cycle is a bill/evidence object, not a projection from current_balance.
-- Current balance can estimate the liability account, but it must not create a
-- monthly bill amount without a statement/snapshot/repayment evidence.

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
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if v_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'cycle month must be YYYY-MM';
  end if;

  with month_ctx as (
    select
      (v_month || '-01')::date as month_start,
      ((v_month || '-01')::date + interval '1 month - 1 day')::date as month_end
  ),
  liability_orders as (
    select
      account.user_id,
      account.id as account_id,
      v_month as cycle_month,
      make_date(
        extract(year from month_ctx.month_start)::int,
        extract(month from month_ctx.month_start)::int,
        least(account.payment_due_day, extract(day from month_ctx.month_end)::int)
      ) as due_date,
      sum(entry.amount)::numeric(14,2) as statement_amount,
      account.auto_debit_account_id,
      account.auto_confirm_repayment
    from public.accounts account
    cross join month_ctx
    join public.account_entries entry on entry.account_id = account.id
      and entry.user_id = account.user_id
      and entry.is_voided = false
      and entry.entry_type = 'expense'
      and entry.direction = 'in'
      and entry.source_table = 'transactions'
      and (entry.occurred_at at time zone 'Asia/Shanghai')::date >
        make_date(
          extract(year from (month_ctx.month_start - interval '1 month'))::int,
          extract(month from (month_ctx.month_start - interval '1 month'))::int,
          least(
            account.payment_due_day,
            extract(day from ((month_ctx.month_start - interval '1 month') + interval '1 month - 1 day'))::int
          )
        )
      and (entry.occurred_at at time zone 'Asia/Shanghai')::date <=
        make_date(
          extract(year from month_ctx.month_start)::int,
          extract(month from month_ctx.month_start)::int,
          least(account.payment_due_day, extract(day from month_ctx.month_end)::int)
        )
    where account.user_id = auth.uid()
      and account.type in ('credit_card', 'credit_line')
      and account.is_archived = false
      and account.payment_due_day is not null
    group by account.user_id, account.id, account.payment_due_day, account.auto_debit_account_id, account.auto_confirm_repayment, month_ctx.month_start, month_ctx.month_end
    having sum(entry.amount) > 0
  )
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
    user_id,
    account_id,
    cycle_month,
    null,
    due_date,
    due_date,
    statement_amount,
    0,
    statement_amount,
    0,
    case
      when due_date = current_date then 'due_today'
      when due_date < current_date then 'overdue_unconfirmed'
      else 'pending'
    end,
    auto_debit_account_id,
    auto_confirm_repayment,
    'system',
    '按已绑定消费流水估算'
  from liability_orders
  on conflict (account_id, cycle_month) do update
     set statement_end_date = coalesce(account_repayment_cycles.statement_end_date, excluded.statement_end_date),
         due_date = coalesce(account_repayment_cycles.due_date, excluded.due_date),
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
           when account_repayment_cycles.source <> 'system'
           then account_repayment_cycles.status
           else excluded.status
         end,
         note = case
           when account_repayment_cycles.source = 'system' then excluded.note
           else account_repayment_cycles.note
         end,
         updated_at = now();

  update public.account_repayment_cycles cycle
     set status = case
           when cycle.status in ('paid', 'ignored', 'partial_paid', 'carried_over') then cycle.status
           when cycle.due_date = current_date then 'due_today'
           when cycle.due_date < current_date then 'overdue_unconfirmed'
           else 'pending'
         end,
         updated_at = now()
   where cycle.user_id = auth.uid()
     and cycle.cycle_month = v_month
     and cycle.status in ('pending', 'due_today', 'overdue_unconfirmed')
     and cycle.due_date is not null;

  return query
  select *
  from public.account_repayment_cycles
  where user_id = auth.uid()
    and cycle_month = v_month
  order by due_date asc nulls last, created_at desc;
end;
$$;

revoke all on function public.ensure_liability_repayment_cycles(text) from public;
revoke execute on function public.ensure_liability_repayment_cycles(text) from anon;
grant execute on function public.ensure_liability_repayment_cycles(text) to authenticated;

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
    and amount > 0
  order by
    account_id,
    cycle_month,
    case when status = 'paid' then 1 else 0 end desc,
    due_date desc nulls last,
    amount desc
)
update public.account_repayment_cycles cycle
   set statement_end_date = coalesce(snapshot_cycles.due_date, cycle.statement_end_date),
       due_date = coalesce(snapshot_cycles.due_date, cycle.due_date),
       statement_amount = snapshot_cycles.amount,
       paid_amount = case when snapshot_cycles.status = 'paid' then snapshot_cycles.amount else 0 end,
       remaining_amount = case when snapshot_cycles.status = 'paid' then 0 else snapshot_cycles.amount end,
       carried_over_amount = 0,
       status = snapshot_cycles.status,
       source = 'screenshot',
       note = case
         when snapshot_cycles.status = 'paid' then '快照证据显示已还款'
         else '快照证据生成待还周期'
       end,
       updated_at = now()
from snapshot_cycles
where cycle.account_id = snapshot_cycles.account_id
  and cycle.cycle_month = snapshot_cycles.cycle_month
  and cycle.source = 'screenshot';

delete from public.account_repayment_cycles cycle
where cycle.source = 'system'
  and not exists (
    select 1
    from public.account_entries entry
    join public.accounts account on account.id = cycle.account_id
    where entry.account_id = cycle.account_id
      and entry.user_id = cycle.user_id
      and entry.is_voided = false
      and entry.entry_type = 'expense'
      and entry.direction = 'in'
      and entry.source_table = 'transactions'
      and account.payment_due_day is not null
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
  );
