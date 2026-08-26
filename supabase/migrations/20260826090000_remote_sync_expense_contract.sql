-- D-REMOTE-003: first server-side sync slice for expense/accounts.
-- This migration is exercised by the disposable PostgreSQL contract fixture
-- before any iOS adapter is connected.

create table if not exists public.sync_entity_versions (
  user_id uuid not null references auth.users(id) on delete cascade,
  aggregate_kind text not null check (aggregate_kind in ('account', 'expense')),
  aggregate_id uuid not null,
  version integer not null check (version > 0),
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  payload_hash text not null,
  primary key (user_id, aggregate_kind, aggregate_id)
);

create table if not exists public.sync_change_log (
  cursor bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  aggregate_kind text not null check (aggregate_kind in ('account', 'expense')),
  aggregate_id uuid not null,
  version integer not null check (version > 0),
  change_kind text not null check (change_kind in ('upsert', 'delete')),
  created_at timestamptz not null default now()
);

create table if not exists public.sync_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  idempotency_key text not null,
  aggregate_kind text not null check (aggregate_kind in ('account', 'expense')),
  aggregate_id uuid not null,
  aggregate_version integer not null check (aggregate_version > 0),
  base_version integer not null check (base_version >= 0),
  result_kind text not null check (result_kind in ('accepted', 'conflict', 'rejected')),
  result_json jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, operation_id),
  unique (user_id, idempotency_key)
);

create table if not exists public.sync_cursor_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  minimum_cursor bigint not null default 0,
  updated_at timestamptz not null default now()
);

create index if not exists idx_sync_change_log_user_cursor
  on public.sync_change_log (user_id, cursor);
create index if not exists idx_sync_entity_versions_user_kind
  on public.sync_entity_versions (user_id, aggregate_kind, updated_at desc);

alter table public.sync_entity_versions enable row level security;
alter table public.sync_change_log enable row level security;
alter table public.sync_operations enable row level security;
alter table public.sync_cursor_state enable row level security;

drop policy if exists sync_entity_versions_user_access on public.sync_entity_versions;
create policy sync_entity_versions_user_access on public.sync_entity_versions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists sync_change_log_user_access on public.sync_change_log;
create policy sync_change_log_user_access on public.sync_change_log
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists sync_operations_user_access on public.sync_operations;
create policy sync_operations_user_access on public.sync_operations
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists sync_cursor_state_user_access on public.sync_cursor_state;
create policy sync_cursor_state_user_access on public.sync_cursor_state
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select on public.sync_entity_versions, public.sync_change_log,
  public.sync_operations, public.sync_cursor_state to authenticated;
revoke all on public.sync_entity_versions, public.sync_change_log,
  public.sync_operations, public.sync_cursor_state from anon;

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
        update public.transactions set status = 'deleted', updated_at = now()
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
        insert into public.transactions (id, user_id, amount, merchant_name, category, payment_method,
          transaction_date, transaction_time, account_id)
        values (v_aggregate_id, v_user_id, (v_payload->>'amount')::numeric, v_payload->>'merchant_name',
          v_payload->>'category', v_payload->>'payment_method', coalesce((v_payload->>'transaction_date')::date, current_date),
          (v_payload->>'transaction_time')::time, v_account.id) returning * into v_transaction;
        insert into public.account_entries (user_id, account_id, direction, amount, entry_type, source_table, source_id)
        values (v_user_id, v_account.id, 'out', v_transaction.amount, 'expense', 'transactions', v_transaction.id)
        returning * into v_entry;
      else
        update public.account_entries set is_voided = true, voided_reason = 'sync_replaced'
         where user_id = v_user_id and source_table = 'transactions' and source_id = v_aggregate_id and not is_voided;
        update public.transactions set amount = coalesce((v_payload->>'amount')::numeric, amount),
          merchant_name = coalesce(v_payload->>'merchant_name', merchant_name),
          category = coalesce(v_payload->>'category', category), account_id = v_account.id, updated_at = now()
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
  return jsonb_build_object('accepted_operation_ids', v_accepted, 'conflicts', v_conflicts,
    'rejected', v_rejected, 'remote_accounts', '[]'::jsonb, 'remote_expenses', '[]'::jsonb,
    'remote_account_entries', '[]'::jsonb, 'next_pull_cursor', 'c:' || v_next_cursor::text,
    'operation_count', v_operation_count);
end;
$$;

revoke all on function public.sync_expense_batch(uuid, integer, text, jsonb) from public, anon;
grant execute on function public.sync_expense_batch(uuid, integer, text, jsonb) to authenticated;
