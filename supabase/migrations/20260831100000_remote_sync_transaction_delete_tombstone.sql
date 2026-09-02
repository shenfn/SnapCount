-- LOCAL-003 RC: bridge legacy hard deletes into the remote sync stream.
--
-- The canonical sync RPC uses a tombstone update, but older/PWA deletion
-- paths physically delete transactions. Without this bridge, other devices
-- never receive a delete change and keep the record in their local projection.

create or replace function public.record_transaction_sync_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version integer;
begin
  if OLD.user_id is null then
    return OLD;
  end if;

  select coalesce(max(version), 0) + 1
    into v_version
    from public.sync_entity_versions
   where user_id = OLD.user_id
     and aggregate_kind = 'expense'
     and aggregate_id = OLD.id;

  insert into public.sync_entity_versions (
    user_id, aggregate_kind, aggregate_id, version, deleted_at, updated_at, payload_hash
  ) values (
    OLD.user_id, 'expense', OLD.id, v_version, now(), now(), md5(OLD.id::text || ':delete')
  )
  on conflict (user_id, aggregate_kind, aggregate_id) do update set
    version = excluded.version,
    deleted_at = excluded.deleted_at,
    updated_at = excluded.updated_at,
    payload_hash = excluded.payload_hash;

  insert into public.sync_change_log (
    user_id, aggregate_kind, aggregate_id, version, change_kind
  ) values (
    OLD.user_id, 'expense', OLD.id, v_version, 'delete'
  );

  return OLD;
end;
$$;

drop trigger if exists transactions_sync_delete_tombstone on public.transactions;
create trigger transactions_sync_delete_tombstone
after delete on public.transactions
for each row execute function public.record_transaction_sync_delete();

revoke all on function public.record_transaction_sync_delete() from public, anon, authenticated;
