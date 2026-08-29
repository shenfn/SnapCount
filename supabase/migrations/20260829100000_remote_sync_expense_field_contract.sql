-- LOCAL-003 RC: replace the already-deployed sync function so its expense
-- writes match the production transactions field and deletion contracts.

create or replace function public.sync_expense_batch(
  p_workspace_id uuid,
  p_client_generation integer,
  p_pull_cursor text,
  p_operations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_operation jsonb;
  v_operation_id uuid;
  v_idempotency_key text;
  v_kind text;
  v_aggregate_id uuid;
  v_operation_kind text;
  v_aggregate_version integer;
  v_base_version integer;
  v_existing_operation public.sync_operations%rowtype;
  v_entity public.sync_entity_versions%rowtype;
  v_account public.accounts%rowtype;
  v_transaction public.transactions%rowtype;
  v_entry public.account_entries%rowtype;
  v_old_account_id uuid;
  v_payload jsonb;
  v_result jsonb;
  v_result_kind text;
  v_cursor bigint;
  v_next_cursor bigint;
  v_pull_cursor bigint;
  v_remote_accounts jsonb := '[]'::jsonb;
  v_remote_expenses jsonb := '[]'::jsonb;
  v_remote_entries jsonb := '[]'::jsonb;
  v_accepted jsonb := '[]'::jsonb;
  v_conflicts jsonb := '[]'::jsonb;
  v_rejected jsonb := '[]'::jsonb;
  v_operation_count integer := 0;
begin
  if v_user_id is null then raise exception 'not authenticated'; end if;
  if p_client_generation is null or p_client_generation < 0 then raise exception 'invalid client generation'; end if;
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then raise exception 'operations must be a JSON array'; end if;
  if jsonb_array_length(p_operations) > 100 then raise exception 'batch too large'; end if;
  if p_pull_cursor = 'expired' then return jsonb_build_object('error', 'cursor_expired'); end if;
  if p_pull_cursor like 'c:%' then
    begin
      v_pull_cursor := substring(p_pull_cursor from 3)::bigint;
    exception when others then
      return jsonb_build_object('error', 'invalid_cursor');
    end;
    if v_pull_cursor < 0 then return jsonb_build_object('error', 'invalid_cursor'); end if;
    if exists (
      select 1 from public.sync_cursor_state
       where user_id = v_user_id and v_pull_cursor < minimum_cursor
    ) then
      return jsonb_build_object('error', 'cursor_expired');
    end if;
  end if;

  insert into public.sync_cursor_state (user_id) values (v_user_id) on conflict (user_id) do nothing;

  for v_operation in select value from jsonb_array_elements(p_operations)
  loop
    v_operation_count := v_operation_count + 1;
    v_operation_id := nullif(v_operation->>'operation_id', '')::uuid;
    v_idempotency_key := nullif(v_operation->>'idempotency_key', '');
    v_kind := v_operation->>'aggregate_kind';
    v_aggregate_id := nullif(v_operation->>'aggregate_id', '')::uuid;
    v_operation_kind := coalesce(v_operation->>'operation_kind', 'upsert');
    v_aggregate_version := nullif(v_operation->>'aggregate_version', '')::integer;
    v_base_version := coalesce(nullif(v_operation->>'base_version', '')::integer, 0);
    v_payload := coalesce(v_operation->'payload', '{}'::jsonb);
    if v_operation_id is null or v_idempotency_key is null or v_kind not in ('account', 'expense')
       or v_aggregate_id is null or v_aggregate_version is null then raise exception 'invalid sync operation'; end if;
    if coalesce((v_operation->'payload'->>'force_failure')::boolean, false) then
      raise exception 'sync_batch_forced_failure';
    end if;

    select * into v_existing_operation from public.sync_operations
     where user_id = v_user_id and (operation_id = v_operation_id or idempotency_key = v_idempotency_key)
     limit 1 for update;
    if found then
      if v_existing_operation.operation_id = v_operation_id and v_existing_operation.idempotency_key = v_idempotency_key then
        if v_existing_operation.result_kind = 'accepted' then v_accepted := v_accepted || jsonb_build_array(v_operation_id);
        elsif v_existing_operation.result_kind = 'conflict' then v_conflicts := v_conflicts || jsonb_build_array(v_existing_operation.result_json);
        else v_rejected := v_rejected || jsonb_build_array(v_existing_operation.result_json); end if;
      else
        v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('operation_id', v_operation_id, 'reason', 'idempotency_key_reused'));
      end if;
      continue;
    end if;

    select * into v_entity from public.sync_entity_versions
     where user_id = v_user_id and aggregate_kind = v_kind and aggregate_id = v_aggregate_id for update;
    if found and v_base_version <> v_entity.version then
      v_result := jsonb_build_object('operation_id', v_operation_id, 'aggregate_kind', v_kind,
        'aggregate_id', v_aggregate_id, 'expected_base_version', v_base_version,
        'actual_version', v_entity.version, 'reason', 'version_conflict');
      insert into public.sync_operations (user_id, operation_id, idempotency_key, aggregate_kind, aggregate_id,
        aggregate_version, base_version, result_kind, result_json)
      values (v_user_id, v_operation_id, v_idempotency_key, v_kind, v_aggregate_id,
        v_aggregate_version, v_base_version, 'conflict', v_result);
      v_conflicts := v_conflicts || jsonb_build_array(v_result);
      continue;
    end if;

    if v_operation_kind = 'delete' then
      if not found then
        v_result := jsonb_build_object('operation_id', v_operation_id, 'reason', 'not_found');
        insert into public.sync_operations (user_id, operation_id, idempotency_key, aggregate_kind, aggregate_id,
          aggregate_version, base_version, result_kind, result_json)
        values (v_user_id, v_operation_id, v_idempotency_key, v_kind, v_aggregate_id,
          v_aggregate_version, v_base_version, 'rejected', v_result);
        v_rejected := v_rejected || jsonb_build_array(v_result);
        continue;
      end if;
      if v_kind = 'expense' then
        update public.account_entries set is_voided = true, voided_reason = 'sync_deleted'
         where user_id = v_user_id and source_table = 'transactions' and source_id = v_aggregate_id and not is_voided;
        update public.transactions set deleted_at = now(), updated_at = now()
         where id = v_aggregate_id and user_id = v_user_id;
      else
        update public.accounts set is_archived = true, updated_at = now()
         where id = v_aggregate_id and user_id = v_user_id;
      end if;
      insert into public.sync_entity_versions (user_id, aggregate_kind, aggregate_id, version,
        deleted_at, updated_at, payload_hash)
      values (v_user_id, v_kind, v_aggregate_id, v_aggregate_version,
        now(), now(), md5(v_payload::text))
      on conflict (user_id, aggregate_kind, aggregate_id) do update set version = excluded.version,
        deleted_at = excluded.deleted_at, updated_at = excluded.updated_at, payload_hash = excluded.payload_hash;
      insert into public.sync_change_log (user_id, aggregate_kind, aggregate_id, version, change_kind)
      values (v_user_id, v_kind, v_aggregate_id, v_aggregate_version, 'delete') returning cursor into v_cursor;
      v_result := jsonb_build_object('operation_id', v_operation_id, 'result', 'accepted');
      insert into public.sync_operations (user_id, operation_id, idempotency_key, aggregate_kind, aggregate_id,
        aggregate_version, base_version, result_kind, result_json)
      values (v_user_id, v_operation_id, v_idempotency_key, v_kind, v_aggregate_id,
        v_aggregate_version, v_base_version, 'accepted', v_result);
      v_accepted := v_accepted || jsonb_build_array(v_operation_id);
      continue;
    end if;

    if v_operation_kind <> 'upsert' then
      v_result := jsonb_build_object('operation_id', v_operation_id, 'reason', 'unsupported_operation');
      insert into public.sync_operations (user_id, operation_id, idempotency_key, aggregate_kind, aggregate_id,
        aggregate_version, base_version, result_kind, result_json)
      values (v_user_id, v_operation_id, v_idempotency_key, v_kind, v_aggregate_id,
        v_aggregate_version, v_base_version, 'rejected', v_result);
      v_rejected := v_rejected || jsonb_build_array(v_result);
      continue;
    end if;

    if v_kind = 'account' then
      select * into v_account from public.accounts where id = v_aggregate_id for update;
      if found and v_account.user_id <> v_user_id then
        v_result := jsonb_build_object('operation_id', v_operation_id, 'reason', 'permission_denied');
        v_rejected := v_rejected || jsonb_build_array(v_result); continue;
      end if;
      if not found then
        insert into public.accounts (id, user_id, name, type, currency, initial_balance, current_balance)
        values (v_aggregate_id, v_user_id, coalesce(v_payload->>'name', '未命名账户'),
          coalesce(v_payload->>'kind', 'other')::public.account_type, coalesce(v_payload->>'currency', 'CNY'),
          coalesce((v_payload->>'opening_balance_minor')::numeric / 100, 0),
          coalesce((v_payload->>'opening_balance_minor')::numeric / 100, 0)) returning * into v_account;
      else
        update public.accounts set name = coalesce(v_payload->>'name', name),
          currency = coalesce(v_payload->>'currency', currency), updated_at = now()
        where id = v_aggregate_id and user_id = v_user_id returning * into v_account;
      end if;
    else
      select * into v_transaction from public.transactions where id = v_aggregate_id for update;
      if found and v_transaction.user_id <> v_user_id then
        v_result := jsonb_build_object('operation_id', v_operation_id, 'reason', 'permission_denied');
        v_rejected := v_rejected || jsonb_build_array(v_result); continue;
      end if;
      select * into v_account from public.accounts
       where id = nullif(v_payload->>'account_id', '')::uuid and user_id = v_user_id;
      if not found then raise exception 'account not found'; end if;
      v_old_account_id := v_transaction.account_id;
      if v_transaction.id is null then
        insert into public.transactions (id, user_id, type, status, source, amount, merchant_name,
          platform, category, payment_method, transaction_date, transaction_time, note, account_id, deleted_at)
        values (v_aggregate_id, v_user_id, 'expense', 'done', coalesce(v_payload->>'source', 'manual'),
          (v_payload->>'amount')::numeric, v_payload->>'merchant_name', v_payload->>'platform',
          v_payload->>'category', v_payload->>'payment_method',
          coalesce((v_payload->>'transaction_date')::date, current_date),
          (v_payload->>'transaction_time')::time, v_payload->>'note', v_account.id, null)
        returning * into v_transaction;
        insert into public.account_entries (user_id, account_id, direction, amount, entry_type, source_table, source_id)
        values (v_user_id, v_account.id, 'out', v_transaction.amount, 'expense', 'transactions', v_transaction.id)
        returning * into v_entry;
      else
        update public.account_entries set is_voided = true, voided_reason = 'sync_replaced'
         where user_id = v_user_id and source_table = 'transactions' and source_id = v_aggregate_id and not is_voided;
        update public.transactions set type = 'expense', status = 'done',
          source = coalesce(v_payload->>'source', source, 'manual'),
          amount = coalesce((v_payload->>'amount')::numeric, amount),
          merchant_name = coalesce(v_payload->>'merchant_name', merchant_name),
          platform = case when v_payload ? 'platform' then v_payload->>'platform' else platform end,
          category = coalesce(v_payload->>'category', category),
          payment_method = case when v_payload ? 'payment_method' then v_payload->>'payment_method' else payment_method end,
          transaction_date = coalesce((v_payload->>'transaction_date')::date, transaction_date),
          transaction_time = case when v_payload ? 'transaction_time' then (v_payload->>'transaction_time')::time else transaction_time end,
          note = case when v_payload ? 'note' then v_payload->>'note' else note end,
          account_id = v_account.id, deleted_at = null, updated_at = now()
        where id = v_aggregate_id and user_id = v_user_id returning * into v_transaction;
        insert into public.account_entries (user_id, account_id, direction, amount, entry_type, source_table, source_id)
        values (v_user_id, v_account.id, 'out', v_transaction.amount, 'expense', 'transactions', v_transaction.id)
        returning * into v_entry;
      end if;
      update public.accounts account_row set current_balance = account_row.initial_balance + coalesce((
        select sum(case when direction = 'in' then amount else -amount end)
        from public.account_entries where account_id = account_row.id and not is_voided
          and entry_type <> 'snapshot_initialization'), 0), updated_at = now()
       where account_row.id = v_account.id or account_row.id = v_old_account_id;
    end if;

    insert into public.sync_entity_versions (user_id, aggregate_kind, aggregate_id, version, updated_at, payload_hash)
    values (v_user_id, v_kind, v_aggregate_id, v_aggregate_version, now(), md5(v_payload::text))
    on conflict (user_id, aggregate_kind, aggregate_id) do update set version = excluded.version,
      updated_at = excluded.updated_at, payload_hash = excluded.payload_hash, deleted_at = null;
    insert into public.sync_change_log (user_id, aggregate_kind, aggregate_id, version, change_kind)
    values (v_user_id, v_kind, v_aggregate_id, v_aggregate_version, 'upsert') returning cursor into v_cursor;
    v_result := jsonb_build_object('operation_id', v_operation_id, 'result', 'accepted');
    insert into public.sync_operations (user_id, operation_id, idempotency_key, aggregate_kind, aggregate_id,
      aggregate_version, base_version, result_kind, result_json)
    values (v_user_id, v_operation_id, v_idempotency_key, v_kind, v_aggregate_id,
      v_aggregate_version, v_base_version, 'accepted', v_result);
    v_accepted := v_accepted || jsonb_build_array(v_operation_id);
  end loop;

  select coalesce(max(cursor), 0) into v_next_cursor from public.sync_change_log where user_id = v_user_id;
  select coalesce(jsonb_agg(to_jsonb(account_row) order by account_row.cursor), '[]'::jsonb)
    into v_remote_accounts
    from (
      select distinct on (c.aggregate_id)
        c.cursor, c.aggregate_id, c.version, c.change_kind,
        a.name, a.type, a.currency, a.initial_balance, a.current_balance,
        e.deleted_at
        from public.sync_change_log c
        left join public.accounts a
          on a.id = c.aggregate_id and a.user_id = v_user_id
        left join public.sync_entity_versions e
          on e.user_id = v_user_id and e.aggregate_kind = 'account'
         and e.aggregate_id = c.aggregate_id
       where c.user_id = v_user_id and c.aggregate_kind = 'account'
         and (v_pull_cursor is null or c.cursor > v_pull_cursor)
       order by c.aggregate_id, c.cursor desc
    ) account_row;
  select coalesce(jsonb_agg(to_jsonb(expense_row) order by expense_row.cursor), '[]'::jsonb)
    into v_remote_expenses
    from (
      select distinct on (c.aggregate_id)
        c.cursor, c.aggregate_id, c.version, c.change_kind,
        t.amount, t.merchant_name, t.platform, t.category, t.payment_method,
        t.transaction_date, t.transaction_time, t.note, t.account_id,
        e.deleted_at
        from public.sync_change_log c
        left join public.transactions t
          on t.id = c.aggregate_id and t.user_id = v_user_id
        left join public.sync_entity_versions e
          on e.user_id = v_user_id and e.aggregate_kind = 'expense'
         and e.aggregate_id = c.aggregate_id
       where c.user_id = v_user_id and c.aggregate_kind = 'expense'
         and (v_pull_cursor is null or c.cursor > v_pull_cursor)
       order by c.aggregate_id, c.cursor desc
    ) expense_row;
  select coalesce(jsonb_agg(to_jsonb(entry_row) order by entry_row.cursor), '[]'::jsonb)
    into v_remote_entries
    from (
      select distinct on (c.aggregate_id)
        c.cursor, c.aggregate_id, c.version, c.change_kind,
        ae.account_id, ae.direction, ae.amount, ae.entry_type,
        ae.source_table, ae.source_id, ae.is_voided, ae.voided_reason
        from public.sync_change_log c
        join public.account_entries ae
          on ae.source_id = c.aggregate_id and ae.user_id = v_user_id
         and ae.source_table = 'transactions'
       where c.user_id = v_user_id and c.aggregate_kind = 'expense'
         and (v_pull_cursor is null or c.cursor > v_pull_cursor)
       order by c.aggregate_id, c.cursor desc
    ) entry_row;
  return jsonb_build_object('accepted_operation_ids', v_accepted, 'conflicts', v_conflicts,
    'rejected', v_rejected, 'remote_accounts', v_remote_accounts, 'remote_expenses', v_remote_expenses,
    'remote_account_entries', v_remote_entries, 'next_pull_cursor', 'c:' || v_next_cursor::text,
    'operation_count', v_operation_count);
end;
$$;

revoke all on function public.sync_expense_batch(uuid, integer, text, jsonb) from public, anon;
grant execute on function public.sync_expense_batch(uuid, integer, text, jsonb) to authenticated;
