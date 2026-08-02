-- DRAFT ONLY: do not apply automatically.
-- User feedback linked to one real expression exposure.

create table if not exists public.expression_feedback_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  occurred_at timestamptz not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  feedback_key text not null unique,
  exposure_event_id uuid not null references public.expression_exposure_events(id) on delete restrict,
  candidate_id text,
  semantic_key text,
  surface text check (surface is null or surface in ('shortcut_notification', 'pwa_pending_ai_card', 'record_detail', 'weekly_report')),
  visible_field_paths text[] not null default '{}',
  primary_choice text not null check (primary_choice in ('incorrect', 'not_helpful', 'repetitive', 'style_dislike', 'other')),
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

alter table public.expression_feedback_events enable row level security;
drop policy if exists expression_feedback_events_read_own on public.expression_feedback_events;
create policy expression_feedback_events_read_own on public.expression_feedback_events for select to authenticated using ((select auth.uid()) = user_id);
revoke all on table public.expression_feedback_events from anon;
revoke insert, update, delete, truncate, references, trigger on table public.expression_feedback_events from authenticated;
grant select on table public.expression_feedback_events to authenticated;
grant all on table public.expression_feedback_events to service_role;

-- Historical review-v1 files without exposure_event_id remain local/import staging data.
-- They must not be inserted until an exposure is resolved.
