-- DRAFT ONLY: do not apply automatically.
-- Shadow collector for real shortcut responses. Never changes user-visible output.

create table if not exists public.expression_shadow_runs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  occurred_at timestamptz not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_key text not null unique,
  trace_id text,
  ai_log_id uuid,
  record_type text,
  record_id uuid,
  surface text not null check (surface in ('shortcut_notification')),
  response_mode text not null check (response_mode in ('json', 'text')),
  rollout_mode text not null check (rollout_mode in ('shadow', 'enforced_owner_only', 'canary')),
  lifecycle_state text not null check (lifecycle_state = 'returned_to_shortcut'),
  baseline_payload jsonb not null default '{}'::jsonb,
  visible_field_paths text[] not null default '{}',
  persisted_only_field_paths text[] not null default '{}',
  collector_result jsonb not null default '{}'::jsonb,
  proposed_plan jsonb not null default '{}'::jsonb,
  proposed_score_summary jsonb not null default '{}'::jsonb,
  changes_user_output boolean not null default false check (changes_user_output = false),
  collector_version text not null,
  processed_at timestamptz,
  processing_error text
);

create index if not exists idx_expression_shadow_user_time
  on public.expression_shadow_runs (user_id, occurred_at desc);
create index if not exists idx_expression_shadow_unprocessed
  on public.expression_shadow_runs (created_at)
  where processed_at is null;
create index if not exists idx_expression_shadow_ai_log
  on public.expression_shadow_runs (ai_log_id)
  where ai_log_id is not null;

alter table public.expression_shadow_runs enable row level security;
drop policy if exists expression_shadow_runs_read_own on public.expression_shadow_runs;
create policy expression_shadow_runs_read_own
  on public.expression_shadow_runs for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.expression_shadow_runs from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.expression_shadow_runs from authenticated;
grant select on table public.expression_shadow_runs to authenticated;
grant all on table public.expression_shadow_runs to service_role;
