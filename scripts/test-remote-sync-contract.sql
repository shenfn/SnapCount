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
select public.remote_sync_test_assert(
  exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'transactions' and column_name = 'deleted_at')
    and exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'transactions' and column_name = 'updated_at'),
  'transactions must expose the sync tombstone and update-time columns'
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
        'platform', '线下消费', 'category', 'food', 'payment_method', '现金',
        'note', '初次同步备注', 'account_id', v_account_id,
        'transaction_date', '2026-08-26', 'transaction_time', '08:30:00')
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
      and (select type = 'expense' and status = 'done' and source = 'manual'
             and platform = '线下消费' and note = '初次同步备注'
           from public.transactions where id = v_expense_id)
      and (select count(*) from public.account_entries where source_id = v_expense_id and not is_voided) = 1,
    'DREMOTE-001 retry must create one complete production-compatible expense fact'
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
    ))) into v_cross_user;
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
      and jsonb_array_length(v_pull->'remote_expenses') >= 1
      and (select count(*) from public.sync_operations) = v_before_count,
    'DREMOTE-009 empty batch must only pull the current remote snapshot'
  );
  perform public.remote_sync_test_assert(
    jsonb_array_length(public.sync_expense_batch(
      'aa000000-0000-4000-8000-000000000001', 1,
      v_pull->>'next_pull_cursor', '[]'::jsonb
    )->'remote_expenses') = 0,
    'a consumed cursor must not return the same expense again'
  );
end;
$$;

do $$
declare
  v_replace jsonb;
  v_delete jsonb;
  v_before_transactions integer;
  v_before_operations integer;
  v_rollback boolean := false;
  v_expense_id uuid := '77000000-0000-4000-8000-000000000002';
  v_account_id uuid := '66000000-0000-4000-8000-000000000001';
begin
  v_replace := public.sync_expense_batch(
    'aa000000-0000-4000-8000-000000000001', 1, null,
    jsonb_build_array(jsonb_build_object(
      'operation_id', '99000000-0000-4000-8000-000000000005',
      'idempotency_key', 'replace-key-001', 'aggregate_kind', 'expense',
      'aggregate_id', v_expense_id, 'aggregate_version', 2, 'base_version', 1,
      'payload', jsonb_build_object('amount', 10, 'merchant_name', 'D-REMOTE 午餐',
        'platform', '外卖', 'category', 'dining', 'payment_method', '银行卡',
        'transaction_date', '2026-08-27', 'transaction_time', '12:15:00',
        'note', '更新后备注', 'source', 'manual', 'account_id', v_account_id)
    ))
  );
  perform public.remote_sync_test_assert(
    jsonb_array_length(v_replace->'accepted_operation_ids') = 1
      and (select count(*) from public.account_entries where source_id = v_expense_id and not is_voided) = 1
      and (select count(*) from public.account_entries where source_id = v_expense_id and is_voided) = 1
      and (select amount = 10 and merchant_name = 'D-REMOTE 午餐' and platform = '外卖'
             and category = 'dining' and payment_method = '银行卡'
             and transaction_date = '2026-08-27' and transaction_time = '12:15:00'
             and note = '更新后备注' and status = 'done' and deleted_at is null
           from public.transactions where id = v_expense_id),
    'DREMOTE-004 replacement must update every editable field and replace the ledger entry'
  );

  v_delete := public.sync_expense_batch(
    'aa000000-0000-4000-8000-000000000001', 1, null,
    jsonb_build_array(jsonb_build_object(
      'operation_id', '99000000-0000-4000-8000-000000000006',
      'idempotency_key', 'delete-key-001', 'aggregate_kind', 'expense',
      'aggregate_id', v_expense_id, 'operation_kind', 'delete',
      'aggregate_version', 3, 'base_version', 2, 'payload', '{}'::jsonb
    ))
  );
  perform public.remote_sync_test_assert(
    jsonb_array_length(v_delete->'accepted_operation_ids') = 1
      and (select status = 'done' and deleted_at is not null from public.transactions where id = v_expense_id)
      and (select count(*) from public.account_entries where source_id = v_expense_id and not is_voided) = 0
      and (select change_kind = 'delete' from public.sync_change_log
            where aggregate_id = v_expense_id order by cursor desc limit 1),
    'DREMOTE-005 delete must use deleted_at tombstone without violating status constraint'
  );

  select count(*) into v_before_transactions from public.transactions;
  select count(*) into v_before_operations from public.sync_operations;
  begin
    perform public.sync_expense_batch(
      'aa000000-0000-4000-8000-000000000001', 1, null,
      jsonb_build_array(
        jsonb_build_object(
          'operation_id', '99000000-0000-4000-8000-000000000007',
          'idempotency_key', 'rollback-key-001', 'aggregate_kind', 'expense',
          'aggregate_id', '77000000-0000-4000-8000-000000000004',
          'aggregate_version', 1, 'base_version', 0,
          'payload', jsonb_build_object('amount', 11, 'account_id', v_account_id)
        ),
        jsonb_build_object(
          'operation_id', '99000000-0000-4000-8000-000000000008',
          'idempotency_key', 'rollback-key-002', 'aggregate_kind', 'expense',
          'aggregate_id', '77000000-0000-4000-8000-000000000005',
          'aggregate_version', 1, 'base_version', 0,
          'payload', jsonb_build_object('force_failure', true, 'amount', 12, 'account_id', v_account_id)
        )
      )
    );
  exception when others then
    v_rollback := position('sync_batch_forced_failure' in sqlerrm) > 0;
  end;
  perform public.remote_sync_test_assert(
    v_rollback
      and (select count(*) from public.transactions) = v_before_transactions
      and (select count(*) from public.sync_operations) = v_before_operations,
    'DREMOTE-006 mid-batch failure must roll back all facts and metadata'
  );

  update public.sync_cursor_state set minimum_cursor = 100
   where user_id = '11111111-1111-4111-8111-111111111111';
  perform public.remote_sync_test_assert(
    public.sync_expense_batch(
      'aa000000-0000-4000-8000-000000000001', 1, 'c:0', '[]'::jsonb
    )->>'error' = 'cursor_expired',
    'DREMOTE-008 expired cursor must return cursor_expired'
  );
end;
$$;
