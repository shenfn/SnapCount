update public.account_repayment_cycles cycle
set statement_start_date = null,
    statement_end_date = null,
    updated_at = now()
where cycle.source = 'screenshot'
  and exists (
    select 1
    from public.data_records record
    where record.linked_account_id = cycle.account_id
      and record.domain_key = 'wallet'
      and record.payload_jsonb->>'record_kind' = 'liability_snapshot'
      and coalesce(
        substring(record.payload_jsonb->>'cycle_month' from '^[0-9]{4}-[0-9]{2}'),
        substring(record.payload_jsonb->>'statement_month' from '^[0-9]{4}-[0-9]{2}'),
        substring(record.payload_jsonb->>'bill_month' from '^[0-9]{4}-[0-9]{2}'),
        substring(record.payload_jsonb->>'due_date' from '^[0-9]{4}-[0-9]{2}')
      ) = cycle.cycle_month
      and not (
        coalesce(record.payload_jsonb->>'statement_start_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$', false)
        or coalesce(record.payload_jsonb->>'statement_end_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$', false)
      )
  );
