begin;

-- The legacy context RPC intentionally keeps its short-term shape for rollback
-- compatibility.  The packet assembler uses this narrow RPC so provenance is
-- available without exposing the complete mixed context to the model.
create or replace function public.get_companion_semantic_memories(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'type', memory_type,
    'key', memory_key,
    'content', content,
    'confidence', confidence,
    'weight', weight,
    'last_seen_at', last_seen_at,
    'expires_at', expires_at,
    'source_table', source_table,
    'source_id', source_id,
    'evidence', evidence_jsonb
  ) order by weight desc, last_seen_at desc), '[]'::jsonb)
  from public.user_companion_memories
  where user_id = p_user_id
    and (expires_at is null or expires_at > now());
$$;

revoke execute on function public.get_companion_semantic_memories(uuid)
  from public, anon, authenticated;
grant execute on function public.get_companion_semantic_memories(uuid)
  to service_role;

-- A user may inspect and delete an understanding, but may not edit its content,
-- provenance, confidence, or weight. Edge writes continue through service_role.
revoke all on table public.user_companion_memories from anon;
revoke insert, update on table public.user_companion_memories from authenticated;
grant select, delete on table public.user_companion_memories to authenticated;
grant all on table public.user_companion_memories to service_role;

drop policy if exists user_companion_memories_access on public.user_companion_memories;
drop policy if exists user_companion_memories_select on public.user_companion_memories;
drop policy if exists user_companion_memories_delete on public.user_companion_memories;

create policy user_companion_memories_select
  on public.user_companion_memories
  for select
  using (auth.uid() = user_id);

create policy user_companion_memories_delete
  on public.user_companion_memories
  for delete
  using (auth.uid() = user_id);

commit;
