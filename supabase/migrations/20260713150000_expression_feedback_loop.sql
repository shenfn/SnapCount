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
  claim_type text not null check (claim_type in ('fact','comparison','trend','pattern','inference','forecast')),
  dimension text,
  surface text not null check (surface in ('shortcut_notification','pwa_pending_ai_card','record_detail','weekly_report')),
  lifecycle_state text not null check (lifecycle_state in ('returned_to_shortcut','client_rendered','client_acknowledged','user_reviewed')),
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
  check (coalesce(metadata ->> 'source', '') <> 'local_dry_run_preview')
);

create index if not exists idx_expression_exposure_user_semantic_time on public.expression_exposure_events (user_id, semantic_key, occurred_at desc);
create index if not exists idx_expression_exposure_user_surface_time on public.expression_exposure_events (user_id, surface, occurred_at desc);
create index if not exists idx_expression_exposure_record on public.expression_exposure_events (user_id, record_id, occurred_at desc) where record_id is not null;

create table if not exists public.expression_feedback_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  occurred_at timestamptz not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  feedback_key text not null unique,
  exposure_event_id uuid not null references public.expression_exposure_events(id) on delete restrict,
  candidate_id text,
  semantic_key text,
  surface text check (surface is null or surface in ('shortcut_notification','pwa_pending_ai_card','record_detail','weekly_report')),
  visible_field_paths text[] not null default '{}',
  primary_choice text not null check (primary_choice in ('incorrect','not_helpful','repetitive','style_dislike','other')),
  issue_annotations jsonb not null default '[]'::jsonb,
  free_text text not null default '',
  suggested_action text not null default '',
  source_review_schema text,
  source_review_key text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_expression_feedback_user_time on public.expression_feedback_events (user_id, occurred_at desc);
create index if not exists idx_expression_feedback_exposure on public.expression_feedback_events (exposure_event_id);
create index if not exists idx_expression_feedback_semantic on public.expression_feedback_events (user_id, semantic_key, occurred_at desc) where semantic_key is not null;

create table if not exists public.expression_preference_signals (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  occurred_at timestamptz not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  signal_key text not null unique,
  feedback_key text not null,
  exposure_event_id uuid references public.expression_exposure_events(id) on delete restrict,
  semantic_key text,
  surface text,
  issue_code text not null,
  preference_dimension text not null,
  direction text not null check (direction in ('increase','decrease')),
  strength numeric not null check (strength >= 0 and strength <= 1),
  aggregation_policy text not null,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_expression_signal_user_time on public.expression_preference_signals (user_id, occurred_at desc);
create index if not exists idx_expression_signal_user_semantic on public.expression_preference_signals (user_id, semantic_key, occurred_at desc) where semantic_key is not null;

create table if not exists public.expression_preference_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now(),
  snapshot_version text not null,
  source_feedback_count int not null default 0,
  source_signal_count int not null default 0,
  snapshot jsonb not null default '{}'::jsonb,
  scoring_profile jsonb not null default '{}'::jsonb
);

alter table public.expression_exposure_events enable row level security;
alter table public.expression_feedback_events enable row level security;
alter table public.expression_preference_signals enable row level security;
alter table public.expression_preference_snapshots enable row level security;

drop policy if exists expression_exposure_events_read_own on public.expression_exposure_events;
create policy expression_exposure_events_read_own on public.expression_exposure_events for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists expression_feedback_events_read_own on public.expression_feedback_events;
create policy expression_feedback_events_read_own on public.expression_feedback_events for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists expression_preference_signals_read_own on public.expression_preference_signals;
create policy expression_preference_signals_read_own on public.expression_preference_signals for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists expression_preference_snapshots_read_own on public.expression_preference_snapshots;
create policy expression_preference_snapshots_read_own on public.expression_preference_snapshots for select to authenticated using ((select auth.uid()) = user_id);

revoke all on table public.expression_exposure_events, public.expression_feedback_events, public.expression_preference_signals, public.expression_preference_snapshots from anon;
revoke insert, update, delete, truncate, references, trigger on table public.expression_exposure_events, public.expression_feedback_events, public.expression_preference_signals, public.expression_preference_snapshots from authenticated;
grant select on table public.expression_exposure_events, public.expression_feedback_events, public.expression_preference_signals, public.expression_preference_snapshots to authenticated;
grant all on table public.expression_exposure_events, public.expression_feedback_events, public.expression_preference_signals, public.expression_preference_snapshots to service_role;
