-- DRAFT ONLY: do not apply automatically.
-- Append-only ledger for expression delivery/exposure lifecycle events.

create table if not exists public.expression_exposure_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  occurred_at timestamptz not null,
  user_id uuid not null references auth.users(id) on delete cascade,

  event_key text not null unique,
  delivery_attempt_id text not null,
  trace_id text,
  ai_log_id uuid,
  record_id uuid,
  record_type text,
  domain_key text,
  entity_id text,

  candidate_id text not null,
  semantic_key text not null,
  claim_type text not null check (claim_type in (
    'fact', 'comparison', 'trend', 'pattern', 'inference', 'forecast'
  )),
  dimension text,
  surface text not null check (surface in (
    'shortcut_notification',
    'pwa_pending_ai_card',
    'record_detail',
    'weekly_report'
  )),
  lifecycle_state text not null check (lifecycle_state in (
    'returned_to_shortcut',
    'client_rendered',
    'client_acknowledged',
    'user_reviewed'
  )),

  selection_mode text,
  score numeric check (score is null or (score >= 0 and score <= 100)),
  expression_plan_version text not null,
  render_contract_version text not null,
  scoring_version text,

  visible_field_paths text[] not null default '{}',
  expandable_field_paths text[] not null default '{}',
  persisted_only_field_paths text[] not null default '{}',
  rendered_payload jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,

  simulation_only boolean not null default false check (simulation_only = false),
  counts_for_novelty boolean not null default true,

  check (
    counts_for_novelty = false
    or lifecycle_state in ('returned_to_shortcut', 'client_rendered', 'client_acknowledged', 'user_reviewed')
  ),
  check (coalesce(metadata ->> 'source', '') <> 'local_dry_run_preview')
);

comment on table public.expression_exposure_events is
  'Append-only server-written ledger of expression content actually returned or rendered to a user surface.';
comment on column public.expression_exposure_events.event_key is
  'Idempotency key for one candidate lifecycle event within one delivery attempt and surface.';
comment on column public.expression_exposure_events.simulation_only is
  'Production table rejects simulation events; replay previews remain local artifacts.';

create index if not exists idx_expression_exposure_user_semantic_time
  on public.expression_exposure_events (user_id, semantic_key, occurred_at desc);

create index if not exists idx_expression_exposure_user_surface_time
  on public.expression_exposure_events (user_id, surface, occurred_at desc);

create index if not exists idx_expression_exposure_trace
  on public.expression_exposure_events (trace_id)
  where trace_id is not null;

create index if not exists idx_expression_exposure_ai_log
  on public.expression_exposure_events (ai_log_id)
  where ai_log_id is not null;

alter table public.expression_exposure_events enable row level security;

-- Authenticated users may inspect their own exposure history.
drop policy if exists expression_exposure_events_read_own on public.expression_exposure_events;
create policy expression_exposure_events_read_own
  on public.expression_exposure_events
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- No authenticated INSERT/UPDATE/DELETE policies are created.
-- service_role bypasses RLS and is the only writer.
revoke all on table public.expression_exposure_events from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.expression_exposure_events from authenticated;
grant select on table public.expression_exposure_events to authenticated;
grant all on table public.expression_exposure_events to service_role;
