-- LOCAL-003 Phase A: single-device + cloud-writer sync contract.
-- Keep the already-applied implementation intact behind a private name and
-- expose an operation-isolating wrapper. This migration is additive and can
-- be applied after 20260829100000 without rewriting production history.

do $$
begin
  if to_regprocedure('public.sync_expense_batch(uuid,integer,text,jsonb)') is not null
     and to_regprocedure('public.sync_expense_batch_operation(uuid,integer,text,jsonb)') is null then
    alter function public.sync_expense_batch(uuid, integer, text, jsonb)
      rename to sync_expense_batch_operation;
  end if;
end;
$$;

revoke all on function public.sync_expense_batch_operation(uuid, integer, text, jsonb)
  from public, anon, authenticated;

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
  v_sanitized_operation jsonb;
  v_result jsonb;
  v_pull jsonb;
  v_rejected jsonb := '[]'::jsonb;
  v_accepted jsonb := '[]'::jsonb;
  v_conflicts jsonb := '[]'::jsonb;
  v_operation_count integer := 0;
  v_cursor text := nullif(p_pull_cursor, 'expired');
begin
  if v_user_id is null then raise exception 'not authenticated'; end if;
  if p_client_generation is null or p_client_generation < 0 then
    raise exception 'invalid client generation';
  end if;
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'operations must be a JSON array';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'batch too large';
  end if;

  for v_operation in select value from jsonb_array_elements(p_operations)
  loop
    v_operation_count := v_operation_count + 1;
    begin
      -- Test-only payload controls must never reach the production function.
      v_sanitized_operation := v_operation || jsonb_build_object(
        'payload', coalesce(v_operation->'payload', '{}'::jsonb) - 'force_failure'
      );
      v_result := public.sync_expense_batch_operation(
        p_workspace_id,
        p_client_generation,
        v_cursor,
        jsonb_build_array(v_sanitized_operation)
      );
      if v_result ? 'error' then
        return v_result;
      end if;
      v_accepted := v_accepted || coalesce(v_result->'accepted_operation_ids', '[]'::jsonb);
      v_conflicts := v_conflicts || coalesce(v_result->'conflicts', '[]'::jsonb);
      v_rejected := v_rejected || coalesce(v_result->'rejected', '[]'::jsonb);
    exception when others then
      begin
        insert into public.sync_operations (
          user_id, operation_id, idempotency_key, aggregate_kind, aggregate_id,
          aggregate_version, base_version, result_kind, result_json
        ) values (
          v_user_id,
          nullif(v_operation->>'operation_id', '')::uuid,
          nullif(v_operation->>'idempotency_key', ''),
          v_operation->>'aggregate_kind',
          nullif(v_operation->>'aggregate_id', '')::uuid,
          nullif(v_operation->>'aggregate_version', '')::integer,
          coalesce(nullif(v_operation->>'base_version', '')::integer, 0),
          'rejected', jsonb_build_object(
            'operation_id', nullif(v_operation->>'operation_id', ''),
            'reason', sqlerrm
          )
        );
      exception when others then
        null;
      end;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object(
        'operation_id', nullif(v_operation->>'operation_id', ''),
        'aggregate_kind', nullif(v_operation->>'aggregate_kind', ''),
        'aggregate_id', nullif(v_operation->>'aggregate_id', ''),
        'reason', sqlerrm
      ));
    end;
  end loop;

  -- Pull once after all isolated writes. The private function still owns the
  -- existing snapshot queries, while this public contract omits derived
  -- account entries that can disagree with local expense projection.
  v_pull := public.sync_expense_batch_operation(
    p_workspace_id,
    p_client_generation,
    v_cursor,
    '[]'::jsonb
  );
  if v_pull ? 'error' then return v_pull; end if;

  return jsonb_build_object(
    'accepted_operation_ids', v_accepted,
    'conflicts', v_conflicts,
    'rejected', v_rejected,
    'remote_accounts', coalesce(v_pull->'remote_accounts', '[]'::jsonb),
    'remote_expenses', coalesce(v_pull->'remote_expenses', '[]'::jsonb),
    'next_pull_cursor', v_pull->'next_pull_cursor',
    'operation_count', v_operation_count
  );
end;
$$;

revoke all on function public.sync_expense_batch(uuid, integer, text, jsonb)
  from public, anon;
grant execute on function public.sync_expense_batch(uuid, integer, text, jsonb)
  to authenticated;
