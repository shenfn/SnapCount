\set ON_ERROR_STOP on

create or replace function public.remote_sync_test_assert(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'D-REMOTE-003 assertion failed: %', p_message;
  end if;
end;
$$;

select public.remote_sync_test_assert(
  to_regclass('public.sync_entity_versions') is not null
    and to_regclass('public.sync_change_log') is not null
    and to_regclass('public.sync_operations') is not null,
  'sync metadata tables must exist'
);
select public.remote_sync_test_assert(
  to_regprocedure('public.sync_expense_batch(uuid,integer,text,jsonb)') is not null,
  'canonical batch RPC must exist'
);

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

do $$
declare
  v_first jsonb;
  v_retry jsonb;
  v_duplicate jsonb;
  v_conflict jsonb;
  v_cross_user jsonb;
  v_pull jsonb;
  v_operation_id uuid := '99000000-0000-4000-8000-000000000001';
  v_expense_id uuid := '77000000-0000-4000-8000-000000000002';
  v_account_id uuid := '66000000-0000-4000-8000-000000000001';
  v_before_count integer;
begin
  v_first := public.sync_expense_batch(
    'aa000000-0000-4000-8000-000000000001', 1, null,
    jsonb_build_array(jsonb_build_object(
      'operation_id', v_operation_id, 'idempotency_key', 'retry-key-001',
      'aggregate_kind', 'expense', 'aggregate_id', v_expense_id,
      'operation_kind', 'upsert', 'aggregate_version', 1, 'base_version', 0,
      'payload', jsonb_build_object('amount', 8.50, 'merchant_name', 'D-REMOTE 早餐',
        'category', 'food', 'account_id', v_account_id, 'transaction_date', '2026-08-26')
    ))
  );
  v_retry := public.sync_expense_batch(
    'aa000000-0000-4000-8000-000000000001', 1, null,
    jsonb_build_array(jsonb_build_object(
      'operation_id', v_operation_id, 'idempotency_key', 'retry-key-001',
      'aggregate_kind', 'expense', 'aggregate_id', v_expense_id,
      'operation_kind', 'upsert', 'aggregate_version', 1, 'base_version', 0,
      'payload', jsonb_build_object('amount', 8.50, 'account_id', v_account_id)
    ))
  );
  perform public.remote_sync_test_assert(
    v_first = v_retry
      and (select count(*) from public.transactions where id = v_expense_id) = 1
      and (select count(*) from public.account_entries where source_id = v_expense_id and not is_voided) = 1,
    'DREMOTE-001 retry must return the first result and create one fact'
  );

  v_duplicate := public.sync_expense_batch(
    'aa000000-0000-4000-8000-000000000001', 1, null,
    jsonb_build_array(jsonb_build_object(
      'operation_id', '99000000-0000-4000-8000-000000000002',
      'idempotency_key', 'retry-key-001', 'aggregate_kind', 'expense',
      'aggregate_id', '77000000-0000-4000-8000-000000000003',
      'aggregate_version', 1, 'base_version', 0,
      'payload', jsonb_build_object('amount', 9, 'account_id', v_account_id)
    ))
  );
  perform public.remote_sync_test_assert(
    v_duplicate->'rejected' @> jsonb_build_array(jsonb_build_object(
      'operation_id', '99000000-0000-4000-8000-000000000002', 'reason', 'idempotency_key_reused'
    )) and (select count(*) from public.transactions where id = '77000000-0000-4000-8000-000000000003') = 0,
    'DREMOTE-002 duplicate idempotency key must not create a second fact'
  );

  v_conflict := public.sync_expense_batch(
    'aa000000-0000-4000-8000-000000000001', 1, null,
    jsonb_build_array(jsonb_build_object(
      'operation_id', '99000000-0000-4000-8000-000000000003',
      'idempotency_key', 'stale-key-001', 'aggregate_kind', 'expense',
      'aggregate_id', v_expense_id, 'aggregate_version', 2, 'base_version', 0,
      'payload', jsonb_build_object('amount', 99, 'account_id', v_account_id)
    ))
  );
  perform public.remote_sync_test_assert(
    jsonb_array_length(v_conflict->'conflicts') = 1
      and (select amount = 8.50 from public.transactions where id = v_expense_id),
    'DREMOTE-003 stale base_version must not mutate the fact'
  );

  select count(*) into v_before_count from public.transactions;
  select public.sync_expense_batch(
    'aa000000-0000-4000-8000-000000000001', 1, null,
    jsonb_build_array(jsonb_build_object(
      'operation_id', '99000000-0000-4000-8000-000000000004',
      'idempotency_key', 'cross-user-key-001', 'aggregate_kind', 'account',
      'aggregate_id', '66000000-0000-4000-8000-000000000002',
      'aggregate_version', 1, 'base_version', 0,
      'payload', jsonb_build_object('name', '不应读取')
    )) into v_cross_user;
  perform public.remote_sync_test_assert(
    v_cross_user->'rejected' @> jsonb_build_array(jsonb_build_object(
      'operation_id', '99000000-0000-4000-8000-000000000004', 'reason', 'permission_denied'
    )) and (select count(*) from public.transactions) = v_before_count,
    'DREMOTE-007 cross-user aggregate must be rejected'
  );

  select count(*) into v_before_count from public.sync_operations;
  v_pull := public.sync_expense_batch(
    'aa000000-0000-4000-8000-000000000001', 1, null, '[]'::jsonb
  );
  perform public.remote_sync_test_assert(
    v_pull->>'next_pull_cursor' is not null
      and (select count(*) from public.sync_operations) = v_before_count,
    'DREMOTE-009 empty batch must only pull'
  );
end;
$$;

-- DREMOTE-004 entry replacement, DREMOTE-005 tombstones, DREMOTE-006 whole
-- batch rollback, and DREMOTE-008 cursor retention remain explicit red work
-- for the next migration slice.
