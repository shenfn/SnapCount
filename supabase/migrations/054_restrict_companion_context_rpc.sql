-- Tighten companion memory RPC exposure and optimize the new table RLS predicate.

revoke execute on function public.get_companion_context(uuid) from public;
revoke execute on function public.get_companion_context(uuid) from anon;
revoke execute on function public.get_companion_context(uuid) from authenticated;
grant execute on function public.get_companion_context(uuid) to service_role;

drop policy if exists user_companion_memories_access on public.user_companion_memories;
create policy user_companion_memories_access on public.user_companion_memories
  for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
