update public.account_repayment_cycles cycle
set evidence_record_id = record.id,
    confidence = coalesce(cycle.confidence, (record.payload_jsonb #>> '{time_context,confidence}')::numeric),
    statement_source_priority = greatest(coalesce(cycle.statement_source_priority, 0), 90),
    original_statement_amount = coalesce(cycle.original_statement_amount, cycle.statement_amount),
    due_date = coalesce(
      cycle.due_date,
      case
        when (record.payload_jsonb->>'due_date') ~ '^\d{4}-\d{2}-\d{2}$'
        then (record.payload_jsonb->>'due_date')::date
        when account.payment_due_day is not null
        then make_date(
          split_part(cycle.cycle_month, '-', 1)::int,
          split_part(cycle.cycle_month, '-', 2)::int,
          least(
            account.payment_due_day,
            extract(day from (
              make_date(split_part(cycle.cycle_month, '-', 1)::int, split_part(cycle.cycle_month, '-', 2)::int, 1)
              + interval '1 month - 1 day'
            ))::int
          )
        )
        else null
      end
    ),
    updated_at = now()
from public.data_records record
join public.accounts account
  on account.id = record.linked_account_id
where cycle.source = 'screenshot'
  and account.id = cycle.account_id
  and cycle.account_id = record.linked_account_id
  and coalesce(record.account_snapshot_kind, record.payload_jsonb->>'account_snapshot_kind') = 'liability'
  and coalesce(record.payload_jsonb->>'cycle_month', record.payload_jsonb->>'statement_month', record.payload_jsonb->>'bill_month') = cycle.cycle_month
  and (
    cycle.evidence_record_id is null
    or cycle.due_date is null
    or cycle.statement_source_priority < 90
    or cycle.original_statement_amount is null
  );
