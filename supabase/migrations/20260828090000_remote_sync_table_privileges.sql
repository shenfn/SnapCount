-- Restrict direct client writes to sync metadata tables.
-- Business writes must go through the SECURITY DEFINER sync RPC.

revoke all on public.sync_entity_versions,
  public.sync_change_log,
  public.sync_operations,
  public.sync_cursor_state
from authenticated;

grant select on public.sync_entity_versions,
  public.sync_change_log,
  public.sync_operations,
  public.sync_cursor_state
to authenticated;
