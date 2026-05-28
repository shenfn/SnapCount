create unique index if not exists uq_accounts_source_record
  on public.accounts (source_record_table, source_record_id)
  where source_record_table is not null and source_record_id is not null;
