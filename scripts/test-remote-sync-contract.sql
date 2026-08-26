\set ON_ERROR_STOP on

create or replace function public.remote_sync_test_assert(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'D-REMOTE-002 red test failed: %', p_message;
  end if;
end;
$$;

-- These assertions intentionally fail before the D-REMOTE-002 migration is
-- present. They are the durable red gate; the next implementation slice must
-- turn them green without changing the scenarios.
select public.remote_sync_test_assert(
  to_regclass('public.sync_entity_versions') is not null,
  'DREMOTE-001/003/004/005 require sync_entity_versions'
);
select public.remote_sync_test_assert(
  to_regclass('public.sync_change_log') is not null,
  'DREMOTE-005/008/009 require sync_change_log'
);
select public.remote_sync_test_assert(
  to_regclass('public.sync_operations') is not null,
  'DREMOTE-001/002/006 require sync_operations'
);
select public.remote_sync_test_assert(
  to_regprocedure('public.sync_expense_batch(uuid,integer,text,jsonb)') is not null,
  'DREMOTE-001..009 require the canonical batch RPC signature'
);

-- Scenario checklist retained next to the executable gate. Once the objects
-- exist, each row becomes a call/assertion in this same file:
-- DREMOTE-001 operation retry creates one transaction and one active entry.
-- DREMOTE-002 duplicate idempotency key returns the first result.
-- DREMOTE-003 stale base_version returns conflict and changes nothing.
-- DREMOTE-004 replacement voids the old entry and creates exactly one new entry.
-- DREMOTE-005 delete emits a tombstone/change event.
-- DREMOTE-006 a mid-batch failure rolls back all facts and metadata.
-- DREMOTE-007 cross-user UUID access is rejected without existence leakage.
-- DREMOTE-008 an expired cursor returns cursor_expired, never latest silently.
-- DREMOTE-009 an empty operation batch only pulls and does not write operations.
