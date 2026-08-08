\set ON_ERROR_STOP on

create or replace function public.finance_test_assert(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'finance occurred_at assertion failed: %', p_message;
  end if;
end;
$$;

select public.finance_test_assert(
  (
    select occurred_at = '2026-08-07T22:41:00Z'::timestamptz
    from public.transactions
    where id = '20000000-0000-4000-8000-000000000001'
  ),
  'staging raw AI occurred_at evidence must backfill'
);

select public.finance_test_assert(
  (
    select occurred_at is null
    from public.transactions
    where id = '20000000-0000-4000-8000-000000000002'
  ),
  'a staging occurred_at column without payload evidence must stay unknown'
);

select public.finance_test_assert(
  (
    select occurred_at is null
    from public.transactions
    where id = '20000000-0000-4000-8000-000000000003'
  ),
  'date-only AI evidence must not become an occurrence instant'
);

select public.finance_test_assert(
  (
    select occurred_at is null
    from public.transactions
    where id = '20000000-0000-4000-8000-000000000004'
  ),
  'fallback time context must not become canonical occurrence evidence'
);

select public.finance_test_assert(
  (
    select occurred_at is null
    from public.transactions
    where id = '20000000-0000-4000-8000-000000000005'
  ),
  'cross-tenant staging evidence must not backfill a transaction'
);

select public.finance_test_assert(
  (
    select occurred_at = '2026-08-07T22:47:00Z'::timestamptz
    from public.transactions
    where id = '20000000-0000-4000-8000-000000000006'
  ),
  'AI log order_finished_at evidence must backfill'
);

select public.finance_test_assert(
  (
    select occurred_at is null
    from public.transactions
    where id = '20000000-0000-4000-8000-000000000007'
  ),
  'AI log date-only payload must not trust its occurred_at column'
);

select public.finance_test_assert(
  (
    select occurred_at = '2026-08-07T22:45:00Z'::timestamptz
    from public.income_records
    where id = '30000000-0000-4000-8000-000000000001'
  ),
  'AI-sourced time_context evidence must backfill income'
);

select public.finance_test_assert(
  (
    select occurred_at is null
    from public.income_records
    where id = '30000000-0000-4000-8000-000000000002'
  ),
  'invalid AI datetime evidence must fail closed'
);

select public.finance_test_assert(
  (
    select occurred_at = '2026-08-07T22:41:00Z'::timestamptz
    from public.account_entries
    where id = '50000000-0000-4000-8000-000000000001'
  ),
  'same-tenant expense account entry must follow canonical occurrence time'
);

select public.finance_test_assert(
  (
    select occurred_at = '2020-01-02T00:00:00Z'::timestamptz
    from public.account_entries
    where id = '50000000-0000-4000-8000-000000000002'
  ),
  'cross-tenant account entry must not be rewritten by source_id alone'
);

select public.finance_test_assert(
  (
    select occurred_at = '2026-08-07T22:45:00Z'::timestamptz
    from public.account_entries
    where id = '50000000-0000-4000-8000-000000000003'
  ),
  'same-tenant income account entry must follow canonical occurrence time'
);

select public.finance_test_assert(
  (
    select is_nullable = 'YES'
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'account_entries'
      and column_name = 'occurred_at'
  ),
  'account entry occurrence must allow unknown time'
);

select public.finance_test_assert(
  public.finance_parse_explicit_timestamptz('2026-08-07T22:41:00Z') = '2026-08-07T22:41:00Z'::timestamptz,
  'explicit UTC timestamp parser must preserve the instant'
);

select public.finance_test_assert(
  public.finance_parse_explicit_timestamptz('2026-08-08') is null,
  'date-only parser input must be rejected'
);

select public.finance_test_assert(
  public.finance_parse_explicit_timestamptz('2026-99-99T22:41:00Z') is null,
  'invalid explicit datetime must fail closed'
);

select public.finance_test_assert(
  (
    select count(*) = 2
    from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'save_transaction_with_account'
  ),
  'expense RPC must expose canonical and compatibility overloads only'
);

select public.finance_test_assert(
  (
    select count(*) = 2
    from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'save_income_with_account'
  ),
  'income RPC must expose canonical and compatibility overloads only'
);

select public.finance_test_assert(
  has_function_privilege(
    'authenticated',
    'public.save_transaction_with_account(uuid,numeric,text,text,text,text,date,time without time zone,text,boolean,text,text,text,text,text,uuid,timestamp with time zone)',
    'EXECUTE'
  ),
  'authenticated must execute canonical expense RPC'
);

select public.finance_test_assert(
  has_function_privilege(
    'authenticated',
    'public.save_transaction_with_account(uuid,numeric,text,text,text,text,date,time without time zone,text,boolean,text,text,text,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated must execute legacy expense RPC'
);

select public.finance_test_assert(
  not has_function_privilege(
    'anon',
    'public.save_transaction_with_account(uuid,numeric,text,text,text,text,date,time without time zone,text,boolean,text,text,text,text,text,uuid,timestamp with time zone)',
    'EXECUTE'
  ),
  'anon and PUBLIC must not execute canonical expense RPC'
);

select public.finance_test_assert(
  not has_function_privilege(
    'anon',
    'public.save_transaction_with_account(uuid,numeric,text,text,text,text,date,time without time zone,text,boolean,text,text,text,text,text,uuid)',
    'EXECUTE'
  ),
  'anon and PUBLIC must not execute legacy expense RPC'
);

select public.finance_test_assert(
  not has_function_privilege(
    'authenticated',
    'public.finance_parse_explicit_timestamptz(text)',
    'EXECUTE'
  ),
  'payload parsing helper must remain private'
);

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

do $$
declare
  v_tx public.transactions%rowtype;
  v_preserved_id uuid;
  v_income public.income_records%rowtype;
  v_archive jsonb;
begin
  select * into v_tx
  from public.save_transaction_with_account(
    p_id => null,
    p_amount => 6.41,
    p_merchant_name => 'canonical-explicit',
    p_platform => 'fixture',
    p_category => 'other',
    p_payment_method => 'cash',
    p_transaction_date => null,
    p_transaction_time => null,
    p_note => null,
    p_is_large_transport => false,
    p_transport_type => null,
    p_source => 'ai_scan',
    p_image_url => null,
    p_image_hash => null,
    p_companion_message => null,
    p_account_id => null,
    p_occurred_at => '2026-08-07T22:41:00Z'
  );

  perform public.finance_test_assert(
    v_tx.occurred_at = '2026-08-07T22:41:00Z'::timestamptz
      and v_tx.transaction_date = '2026-08-08'::date
      and v_tx.transaction_time = '06:41:00'::time,
    '22:41Z must mirror as Shanghai 06:41 on the following date'
  );

  select * into v_tx
  from public.save_transaction_with_account(
    p_id => null,
    p_amount => 5,
    p_merchant_name => 'canonical-unknown',
    p_platform => 'fixture',
    p_category => 'other',
    p_payment_method => 'cash',
    p_transaction_date => '2026-08-08',
    p_transaction_time => '06:41:00',
    p_note => null,
    p_is_large_transport => false,
    p_transport_type => null,
    p_source => 'ai_scan',
    p_image_url => null,
    p_image_hash => null,
    p_companion_message => null,
    p_account_id => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    p_occurred_at => null
  );

  perform public.finance_test_assert(
    v_tx.occurred_at is null,
    'canonical RPC must not promote compatibility date/time to occurred_at'
  );
  perform public.finance_test_assert(
    (
      select occurred_at is null
      from public.account_entries
      where source_table = 'transactions'
        and source_id = v_tx.id
        and is_voided = false
    ),
    'unknown transaction time must remain null in its account entry'
  );

  select * into v_tx
  from public.save_transaction_with_account(
    p_amount => 5,
    p_merchant_name => 'legacy-manual',
    p_platform => 'fixture',
    p_category => 'other',
    p_payment_method => 'cash',
    p_transaction_date => '2026-08-08',
    p_transaction_time => '06:41:00',
    p_source => 'manual'
  );
  perform public.finance_test_assert(
    v_tx.occurred_at = '2026-08-07T22:41:00Z'::timestamptz,
    'legacy manual date and time must convert to canonical Shanghai instant'
  );

  select * into v_tx
  from public.save_transaction_with_account(
    p_amount => 5,
    p_merchant_name => 'legacy-ai-scan',
    p_platform => 'fixture',
    p_category => 'other',
    p_payment_method => 'cash',
    p_transaction_date => '2026-08-08',
    p_transaction_time => '06:41:00',
    p_source => 'ai_scan'
  );
  perform public.finance_test_assert(
    v_tx.occurred_at is null,
    'legacy AI date/time must not be promoted to canonical occurrence'
  );

  select * into v_tx
  from public.save_transaction_with_account(
    p_id => null,
    p_amount => 5,
    p_merchant_name => 'preserve-canonical',
    p_platform => 'fixture',
    p_category => 'other',
    p_payment_method => 'cash',
    p_transaction_date => null,
    p_transaction_time => null,
    p_note => null,
    p_is_large_transport => false,
    p_transport_type => null,
    p_source => 'manual',
    p_image_url => null,
    p_image_hash => null,
    p_companion_message => null,
    p_account_id => null,
    p_occurred_at => '2026-08-07T22:41:00Z'
  );
  v_preserved_id := v_tx.id;

  select * into v_tx
  from public.save_transaction_with_account(
    p_id => v_preserved_id,
    p_amount => 6,
    p_merchant_name => 'preserve-canonical',
    p_platform => 'fixture',
    p_category => 'other',
    p_payment_method => 'cash',
    p_transaction_date => '2026-09-01',
    p_transaction_time => '23:59:00',
    p_note => null,
    p_is_large_transport => false,
    p_transport_type => null,
    p_source => 'manual',
    p_image_url => null,
    p_image_hash => null,
    p_companion_message => null,
    p_account_id => null,
    p_occurred_at => null
  );
  perform public.finance_test_assert(
    v_tx.occurred_at = '2026-08-07T22:41:00Z'::timestamptz
      and v_tx.transaction_date = '2026-08-08'::date
      and v_tx.transaction_time = '06:41:00'::time,
    'canonical edit without new evidence must preserve the existing instant and mirrors'
  );

  select * into v_income
  from public.save_income_with_account(
    p_category => 'other',
    p_source_name => 'legacy-date-only-income',
    p_amount => 8,
    p_income_date => '2026-08-08',
    p_account_id => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  );
  perform public.finance_test_assert(
    v_income.occurred_at is null,
    'date-only legacy income must keep canonical occurrence unknown'
  );
  perform public.finance_test_assert(
    (
      select occurred_at is null
      from public.account_entries
      where source_table = 'income_records'
        and source_id = v_income.id
        and is_voided = false
    ),
    'date-only income account entry must not invent noon or write time'
  );

  insert into public.data_domains (
    id, key, name, status, is_system, version, user_id
  ) values (
    '60000000-0000-4000-8000-000000000001',
    'reading',
    '阅读',
    'active',
    true,
    '1.0',
    null
  );
  insert into public.staging_records (
    id, user_id, status, image_path, image_hash
  ) values (
    '70000000-0000-4000-8000-000000000001',
    '11111111-1111-4111-8111-111111111111',
    'pending_review',
    'fixture/reading.png',
    'fixture-reading-hash'
  );

  select public.archive_staging_record(
    p_staging_id => '70000000-0000-4000-8000-000000000001',
    p_domain_key => 'reading',
    p_title => '日期已知但时刻未知',
    p_record_date => '2026-08-08',
    p_occurred_at => null
  ) into v_archive;

  perform public.finance_test_assert(
    (
      select occurred_at is null
      from public.data_records
      where id = (v_archive->>'target_record_id')::uuid
    ),
    'generic staging archive must preserve an unknown event instant'
  );
end;
$$;

drop function public.finance_test_assert(boolean, text);

select 'finance occurred_at PostgreSQL migration contract: ok' as result;
