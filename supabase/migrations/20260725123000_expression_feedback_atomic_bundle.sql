-- Make delivered-expression exposure and feedback writes atomic and retry-safe.
--
-- Existing duplicate reviews are converged while the legacy write tables are
-- locked. The final unique constraint then makes one current review per
-- exposure a database invariant.

begin;

lock table public.expression_shadow_runs in share row exclusive mode;
lock table public.expression_exposure_events in share row exclusive mode;
lock table public.expression_feedback_events in share row exclusive mode;
lock table public.expression_preference_signals in share row exclusive mode;
lock table public.expression_preference_snapshots in share row exclusive mode;

-- Remove feedback rows whose user does not own the referenced exposure before
-- adding the composite ownership foreign key.
delete from public.expression_preference_signals as signal
using public.expression_feedback_events as feedback
where signal.user_id = feedback.user_id
  and signal.feedback_key = feedback.feedback_key
  and not exists (
    select 1
    from public.expression_exposure_events as exposure
    where exposure.id = feedback.exposure_event_id
      and exposure.user_id = feedback.user_id
  );

delete from public.expression_feedback_events as feedback
where not exists (
  select 1
  from public.expression_exposure_events as exposure
  where exposure.id = feedback.exposure_event_id
    and exposure.user_id = feedback.user_id
);

create temporary table expression_feedback_dedupe on commit drop as
select
  id,
  user_id,
  exposure_event_id,
  feedback_key as old_feedback_key,
  'feedback:' || user_id::text || ':' || exposure_event_id::text as new_feedback_key,
  row_number() over (
    partition by user_id, exposure_event_id
    order by occurred_at desc, created_at desc, id desc
  ) as keep_rank
from public.expression_feedback_events;

delete from public.expression_preference_signals as signal
using expression_feedback_dedupe as duplicate
where duplicate.keep_rank > 1
  and signal.user_id = duplicate.user_id
  and signal.feedback_key = duplicate.old_feedback_key;

delete from public.expression_feedback_events as feedback
using expression_feedback_dedupe as duplicate
where duplicate.keep_rank > 1
  and feedback.id = duplicate.id;

-- Preference signals have no feedback-key foreign key in the legacy schema.
-- Remove orphaned rows so every remaining key can be migrated in two phases.
delete from public.expression_preference_signals as signal
where not exists (
  select 1
  from public.expression_feedback_events as feedback
  where feedback.user_id = signal.user_id
    and feedback.feedback_key = signal.feedback_key
);

create temporary table expression_signal_dedupe on commit drop as
select
  signal.id,
  row_number() over (
    partition by feedback.id, signal.issue_code
    order by signal.occurred_at desc, signal.created_at desc, signal.id desc
  ) as keep_rank
from public.expression_preference_signals as signal
join expression_feedback_dedupe as kept
  on kept.keep_rank = 1
 and kept.user_id = signal.user_id
 and kept.old_feedback_key = signal.feedback_key
join public.expression_feedback_events as feedback
  on feedback.id = kept.id;

delete from public.expression_preference_signals as signal
using expression_signal_dedupe as duplicate
where duplicate.keep_rank > 1
  and signal.id = duplicate.id;

-- First move all surviving keys into an ID-scoped namespace. This frees every
-- canonical key before any row is assigned its final value.
update public.expression_preference_signals as signal
set
  feedback_key = 'feedback-migration:' || kept.id::text,
  signal_key = 'signal-migration:' || signal.id::text
from expression_feedback_dedupe as kept
where kept.keep_rank = 1
  and signal.user_id = kept.user_id
  and signal.feedback_key = kept.old_feedback_key;

update public.expression_feedback_events as feedback
set feedback_key = 'feedback-migration:' || feedback.id::text
where exists (
  select 1
  from expression_feedback_dedupe as kept
  where kept.keep_rank = 1 and kept.id = feedback.id
);

update public.expression_feedback_events as feedback
set feedback_key = kept.new_feedback_key
from expression_feedback_dedupe as kept
where kept.keep_rank = 1
  and feedback.id = kept.id;

update public.expression_preference_signals as signal
set
  feedback_key = kept.new_feedback_key,
  signal_key = kept.new_feedback_key || ':' || signal.issue_code
from expression_feedback_dedupe as kept
where kept.keep_rank = 1
  and signal.feedback_key = 'feedback-migration:' || kept.id::text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.expression_exposure_events'::regclass
      and conname = 'expression_exposure_events_id_user_key'
  ) then
    alter table public.expression_exposure_events
      add constraint expression_exposure_events_id_user_key unique (id, user_id);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.expression_feedback_events'::regclass
      and conname = 'expression_feedback_events_exposure_event_key'
  ) then
    alter table public.expression_feedback_events
      add constraint expression_feedback_events_exposure_event_key
      unique (exposure_event_id);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.expression_feedback_events'::regclass
      and conname = 'expression_feedback_events_exposure_user_fkey'
  ) then
    alter table public.expression_feedback_events
      add constraint expression_feedback_events_exposure_user_fkey
      foreign key (exposure_event_id, user_id)
      references public.expression_exposure_events (id, user_id)
      on delete restrict;
  end if;
end;
$$;

alter table public.expression_feedback_events
  add column if not exists semantic_hash text;

create table if not exists public.expression_preference_revisions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0 check (revision >= 0),
  updated_at timestamptz not null default now()
);

alter table public.expression_preference_snapshots
  add column if not exists source_revision bigint not null default 0 check (source_revision >= 0);

alter table public.expression_shadow_runs
  add column if not exists source_record_ids uuid[] not null default '{}'::uuid[];

update public.expression_shadow_runs
set source_record_ids = array[record_id]
where record_id is not null and cardinality(source_record_ids) = 0;

create index if not exists idx_expression_shadow_source_records
  on public.expression_shadow_runs using gin (source_record_ids);

-- Existing snapshots predate source revisions. Leave them at revision zero so
-- they are detected as stale and lazily rebuilt from the canonical source.
insert into public.expression_preference_revisions (user_id, revision, updated_at)
select source.user_id, 1, now()
from (
  select user_id from public.expression_feedback_events
  union
  select user_id from public.expression_preference_signals
  union
  select user_id from public.expression_preference_snapshots
) as source
on conflict (user_id) do nothing;

alter table public.expression_preference_revisions enable row level security;
revoke all on table public.expression_preference_revisions from public, anon, authenticated;
grant all on table public.expression_preference_revisions to service_role;

create table if not exists public.expression_delivery_snapshots (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 hour'),
  user_id uuid not null references auth.users(id) on delete cascade,
  shadow_run_id uuid references public.expression_shadow_runs(id) on delete set null,
  record_id uuid not null,
  record_kind text not null check (record_kind in ('expense', 'income', 'data')),
  domain_key text not null check (domain_key <> ''),
  surface text not null check (surface = 'record_detail'),
  candidate_id text not null check (candidate_id <> ''),
  content_fingerprint text not null check (content_fingerprint <> ''),
  delivery_plan jsonb not null check (jsonb_typeof(delivery_plan) = 'object'),
  constraint expression_delivery_snapshots_expiry_check check (expires_at > created_at)
);

create index if not exists idx_expression_delivery_snapshots_record
  on public.expression_delivery_snapshots (user_id, record_id, created_at desc);
create index if not exists idx_expression_delivery_snapshots_expiry
  on public.expression_delivery_snapshots (expires_at);

alter table public.expression_delivery_snapshots enable row level security;
revoke all on table public.expression_delivery_snapshots from public, anon, authenticated;
revoke all on table public.expression_delivery_snapshots from service_role;
grant select, insert, delete on table public.expression_delivery_snapshots to service_role;

create or replace function public.cleanup_expression_delivery_snapshots()
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  deleted_count bigint := 0;
begin
  delete from public.expression_delivery_snapshots where expires_at <= now();
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.cleanup_expression_delivery_snapshots()
  from public, anon, authenticated;
grant execute on function public.cleanup_expression_delivery_snapshots()
  to service_role;

do $block$
begin
  if to_regnamespace('cron') is not null then
    execute 'select cron.unschedule(jobid) from cron.job where jobname = ''cleanup-expression-delivery-snapshots''';
    execute 'select cron.schedule(''cleanup-expression-delivery-snapshots'', ''*/15 * * * *'', ''select public.cleanup_expression_delivery_snapshots();'')';
  end if;
end;
$block$;

create table if not exists public.expression_exposure_source_records (
  exposure_event_id uuid not null,
  user_id uuid not null,
  source_table text not null check (source_table in ('transactions', 'income_records', 'data_records')),
  source_record_id uuid not null,
  source_fingerprint text not null check (source_fingerprint <> ''),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (exposure_event_id, source_table, source_record_id),
  constraint expression_exposure_sources_owner_fkey
    foreign key (exposure_event_id, user_id)
    references public.expression_exposure_events (id, user_id)
    on delete cascade
);

create index if not exists idx_expression_exposure_sources_record
  on public.expression_exposure_source_records (user_id, source_table, source_record_id);

insert into public.expression_exposure_source_records (
  exposure_event_id,
  user_id,
  source_table,
  source_record_id,
  source_fingerprint,
  is_primary
)
select
  exposure.id,
  exposure.user_id,
  case
    when exposure.record_type = 'expense' then 'transactions'
    when exposure.record_type = 'income' then 'income_records'
    else 'data_records'
  end,
  exposure.record_id,
  'legacy-record:' || coalesce(exposure.record_type, 'unknown') || ':' || exposure.record_id::text,
  true
from public.expression_exposure_events as exposure
where exposure.record_id is not null
on conflict (exposure_event_id, source_table, source_record_id) do nothing;

alter table public.expression_exposure_source_records enable row level security;
revoke all on table public.expression_exposure_source_records from public, anon, authenticated;
grant all on table public.expression_exposure_source_records to service_role;

create or replace function public.persist_expression_exposure_with_sources(
  p_user_id uuid,
  p_event_key text,
  p_exposure jsonb,
  p_sources jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_requested public.expression_exposure_events%rowtype;
  v_exposure public.expression_exposure_events%rowtype;
  v_requested_payload jsonb;
  v_existing_payload jsonb;
  v_requested_sources jsonb;
  v_existing_sources jsonb;
  v_inserted boolean := false;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if p_user_id is null or coalesce(btrim(p_event_key), '') = '' then
    raise exception 'user and event key are required';
  end if;
  if jsonb_typeof(coalesce(p_exposure, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_sources, '[]'::jsonb)) <> 'array' then
    raise exception 'invalid exposure bundle';
  end if;
  if coalesce(p_exposure ->> 'user_id', p_user_id::text) <> p_user_id::text
     or coalesce(p_exposure ->> 'event_key', p_event_key) <> p_event_key then
    raise exception 'exposure identity does not match request';
  end if;
  if jsonb_array_length(coalesce(p_sources, '[]'::jsonb)) = 0 then
    raise exception 'at least one exposure source is required';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_sources, '[]'::jsonb)) as source(value)
    where jsonb_typeof(source.value) <> 'object'
       or coalesce(source.value ->> 'source_table', '') not in ('transactions', 'income_records', 'data_records')
       or coalesce(source.value ->> 'source_record_id', '') = ''
       or coalesce(source.value ->> 'source_fingerprint', '') = ''
  ) then
    raise exception 'invalid exposure source';
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(coalesce(p_sources, '[]'::jsonb)) as source(value)
    where coalesce((source.value ->> 'is_primary')::boolean, false)
  ) then
    raise exception 'a primary exposure source is required';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_sources, '[]'::jsonb)) as source(value)
    group by source.value ->> 'source_table', source.value ->> 'source_record_id'
    having count(distinct source.value ->> 'source_fingerprint') > 1
       or count(distinct coalesce(source.value ->> 'is_primary', 'false')) > 1
  ) then
    raise exception 'conflicting exposure source definitions';
  end if;

  select coalesce(jsonb_agg(normalized.value order by normalized.sort_key), '[]'::jsonb)
    into v_requested_sources
  from (
    select distinct
      jsonb_build_object(
        'source_table', source.value ->> 'source_table',
        'source_record_id', (source.value ->> 'source_record_id')::uuid,
        'source_fingerprint', source.value ->> 'source_fingerprint',
        'is_primary', coalesce((source.value ->> 'is_primary')::boolean, false)
      ) as value,
      concat_ws(':', source.value ->> 'source_table', source.value ->> 'source_record_id') as sort_key
    from jsonb_array_elements(coalesce(p_sources, '[]'::jsonb)) as source(value)
  ) as normalized;

  v_requested := jsonb_populate_record(
    null::public.expression_exposure_events,
    p_exposure || jsonb_build_object('user_id', p_user_id, 'event_key', p_event_key)
  );
  v_requested.id := null;
  v_requested.created_at := null;
  v_requested.user_id := p_user_id;
  v_requested.event_key := p_event_key;
  v_requested.visible_field_paths := coalesce(v_requested.visible_field_paths, '{}'::text[]);
  v_requested.expandable_field_paths := coalesce(v_requested.expandable_field_paths, '{}'::text[]);
  v_requested.persisted_only_field_paths := coalesce(v_requested.persisted_only_field_paths, '{}'::text[]);
  v_requested.rendered_payload := coalesce(v_requested.rendered_payload, '{}'::jsonb);
  v_requested.metadata := coalesce(v_requested.metadata, '{}'::jsonb);
  v_requested.simulation_only := coalesce(v_requested.simulation_only, false);
  v_requested.counts_for_novelty := coalesce(v_requested.counts_for_novelty, true);

  if v_requested.occurred_at is null
     or coalesce(v_requested.delivery_attempt_id, '') = ''
     or coalesce(v_requested.candidate_id, '') = ''
     or coalesce(v_requested.semantic_key, '') = ''
     or coalesce(v_requested.claim_type, '') = ''
     or coalesce(v_requested.surface, '') = ''
     or coalesce(v_requested.lifecycle_state, '') = ''
     or coalesce(v_requested.expression_plan_version, '') = ''
     or coalesce(v_requested.render_contract_version, '') = '' then
    raise exception 'exposure is missing required delivery fields';
  end if;
  if v_requested.simulation_only or not v_requested.counts_for_novelty then
    raise exception 'only real novelty-counting exposures can be persisted';
  end if;

  v_requested_payload := to_jsonb(v_requested) - 'id' - 'created_at' - 'occurred_at' - 'lifecycle_state';

  insert into public.expression_exposure_events (
    occurred_at,
    user_id,
    event_key,
    delivery_attempt_id,
    trace_id,
    ai_log_id,
    record_id,
    record_type,
    domain_key,
    entity_id,
    candidate_id,
    semantic_key,
    claim_type,
    dimension,
    surface,
    lifecycle_state,
    selection_mode,
    score,
    expression_plan_version,
    render_contract_version,
    scoring_version,
    visible_field_paths,
    expandable_field_paths,
    persisted_only_field_paths,
    rendered_payload,
    metadata,
    simulation_only,
    counts_for_novelty
  ) values (
    v_requested.occurred_at,
    v_requested.user_id,
    v_requested.event_key,
    v_requested.delivery_attempt_id,
    v_requested.trace_id,
    v_requested.ai_log_id,
    v_requested.record_id,
    v_requested.record_type,
    v_requested.domain_key,
    v_requested.entity_id,
    v_requested.candidate_id,
    v_requested.semantic_key,
    v_requested.claim_type,
    v_requested.dimension,
    v_requested.surface,
    v_requested.lifecycle_state,
    v_requested.selection_mode,
    v_requested.score,
    v_requested.expression_plan_version,
    v_requested.render_contract_version,
    v_requested.scoring_version,
    v_requested.visible_field_paths,
    v_requested.expandable_field_paths,
    v_requested.persisted_only_field_paths,
    v_requested.rendered_payload,
    v_requested.metadata,
    v_requested.simulation_only,
    v_requested.counts_for_novelty
  )
  on conflict (event_key) do nothing
  returning * into v_exposure;
  v_inserted := found;

  if not v_inserted then
    select * into v_exposure
    from public.expression_exposure_events
    where event_key = p_event_key
    for update;
    if not found then
      raise exception 'exposure conflict could not be resolved';
    end if;
    v_existing_payload := to_jsonb(v_exposure) - 'id' - 'created_at' - 'occurred_at' - 'lifecycle_state';
    if v_existing_payload is distinct from v_requested_payload then
      raise exception 'event key already exists with different exposure content';
    end if;
  end if;

  if v_inserted then
    insert into public.expression_exposure_source_records (
      exposure_event_id,
      user_id,
      source_table,
      source_record_id,
      source_fingerprint,
      is_primary
    )
    select
      v_exposure.id,
      p_user_id,
      source.value ->> 'source_table',
      (source.value ->> 'source_record_id')::uuid,
      source.value ->> 'source_fingerprint',
      coalesce((source.value ->> 'is_primary')::boolean, false)
    from jsonb_array_elements(v_requested_sources) as source(value);
  else
    select coalesce(jsonb_agg(normalized.value order by normalized.sort_key), '[]'::jsonb)
      into v_existing_sources
    from (
      select
        jsonb_build_object(
          'source_table', source.source_table,
          'source_record_id', source.source_record_id,
          'source_fingerprint', source.source_fingerprint,
          'is_primary', source.is_primary
        ) as value,
        concat_ws(':', source.source_table, source.source_record_id::text) as sort_key
      from public.expression_exposure_source_records as source
      where source.exposure_event_id = v_exposure.id
        and source.user_id = p_user_id
    ) as normalized;
    if v_existing_sources is distinct from v_requested_sources then
      raise exception 'event key already exists with different exposure sources';
    end if;
  end if;

  return jsonb_build_object(
    'exposure', to_jsonb(v_exposure),
    'created', v_inserted
  );
end;
$$;

create or replace function public.replace_expression_feedback_bundle(
  p_user_id uuid,
  p_exposure_event_id uuid,
  p_feedback jsonb,
  p_signals jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_exposure public.expression_exposure_events%rowtype;
  v_feedback public.expression_feedback_events%rowtype;
  v_feedback_count integer := 0;
  v_feedback_key text;
  v_requested_annotations jsonb;
  v_requested_signals jsonb;
  v_existing_signals jsonb;
  v_requested_bundle jsonb;
  v_existing_bundle jsonb;
  v_requested_hash text;
  v_revision bigint;
  v_occurred_at timestamptz;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if p_user_id is null or p_exposure_event_id is null then
    raise exception 'user and exposure are required';
  end if;
  if jsonb_typeof(coalesce(p_feedback, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_signals, '[]'::jsonb)) <> 'array' then
    raise exception 'invalid feedback bundle';
  end if;
  if coalesce(p_feedback ->> 'primary_choice', '') = '' then
    raise exception 'primary choice is required';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_signals, '[]'::jsonb)) as signal(value)
    where jsonb_typeof(signal.value) <> 'object'
       or coalesce(signal.value ->> 'issue_code', '') = ''
       or coalesce(signal.value ->> 'preference_dimension', '') = ''
       or coalesce(signal.value ->> 'direction', '') not in ('increase', 'decrease')
       or coalesce(signal.value ->> 'strength', '') = ''
       or (signal.value ->> 'strength')::numeric < 0
       or (signal.value ->> 'strength')::numeric > 1
  ) then
    raise exception 'invalid preference signal';
  end if;
  if (
    select count(*) <> count(distinct signal.value ->> 'issue_code')
    from jsonb_array_elements(coalesce(p_signals, '[]'::jsonb)) as signal(value)
  ) then
    raise exception 'duplicate preference issue code';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('expression-feedback:' || p_user_id::text, 0));

  select * into v_exposure
  from public.expression_exposure_events
  where id = p_exposure_event_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'exposure does not belong to user';
  end if;
  if v_exposure.surface <> 'record_detail'
     or v_exposure.simulation_only
     or not v_exposure.counts_for_novelty
     or v_exposure.lifecycle_state not in ('client_rendered', 'client_acknowledged', 'user_reviewed') then
    raise exception 'exposure was not rendered in record detail';
  end if;

  v_feedback_key := 'feedback:' || p_user_id::text || ':' || p_exposure_event_id::text;

  select coalesce(jsonb_agg(annotation.value order by annotation.value::text), '[]'::jsonb)
    into v_requested_annotations
  from jsonb_array_elements(coalesce(p_feedback -> 'issue_annotations', '[]'::jsonb)) as annotation(value);

  select coalesce(jsonb_agg(normalized.value order by normalized.sort_key), '[]'::jsonb)
    into v_requested_signals
  from (
    select
      jsonb_build_object(
        'issue_code', signal.value ->> 'issue_code',
        'preference_dimension', signal.value ->> 'preference_dimension',
        'direction', signal.value ->> 'direction',
        'strength', (signal.value ->> 'strength')::numeric,
        'aggregation_policy', coalesce(signal.value ->> 'aggregation_policy', 'decay_and_repeat_required'),
        'metadata', coalesce(signal.value -> 'metadata', jsonb_build_object('source', 'record_feedback_deriver'))
      ) as value,
      concat_ws(':', signal.value ->> 'issue_code', signal.value ->> 'preference_dimension', signal.value ->> 'direction') as sort_key
    from jsonb_array_elements(coalesce(p_signals, '[]'::jsonb)) as signal(value)
  ) as normalized;

  v_requested_bundle := jsonb_build_object(
    'primary_choice', p_feedback ->> 'primary_choice',
    'issue_annotations', v_requested_annotations,
    'free_text', coalesce(p_feedback ->> 'free_text', ''),
    'suggested_action', coalesce(p_feedback ->> 'suggested_action', ''),
    'signals', v_requested_signals
  );
  v_requested_hash := md5(v_requested_bundle::text);

  select count(*) into v_feedback_count
  from public.expression_feedback_events
  where user_id = p_user_id and exposure_event_id = p_exposure_event_id;

  select * into v_feedback
  from public.expression_feedback_events
  where user_id = p_user_id and exposure_event_id = p_exposure_event_id
  order by occurred_at desc, created_at desc, id desc
  limit 1
  for update;

  if v_feedback_count = 1 then
    select coalesce(jsonb_agg(normalized.value order by normalized.sort_key), '[]'::jsonb)
      into v_existing_signals
    from (
      select
        jsonb_build_object(
          'issue_code', signal.issue_code,
          'preference_dimension', signal.preference_dimension,
          'direction', signal.direction,
          'strength', signal.strength,
          'aggregation_policy', signal.aggregation_policy,
          'metadata', signal.metadata
        ) as value,
        concat_ws(':', signal.issue_code, signal.preference_dimension, signal.direction) as sort_key
      from public.expression_preference_signals as signal
      where signal.user_id = p_user_id
        and (
          signal.exposure_event_id = p_exposure_event_id
          or signal.feedback_key = v_feedback.feedback_key
        )
    ) as normalized;

    select jsonb_build_object(
      'primary_choice', v_feedback.primary_choice,
      'issue_annotations', coalesce(jsonb_agg(annotation.value order by annotation.value::text), '[]'::jsonb),
      'free_text', coalesce(v_feedback.free_text, ''),
      'suggested_action', coalesce(v_feedback.suggested_action, ''),
      'signals', v_existing_signals
    ) into v_existing_bundle
    from jsonb_array_elements(coalesce(v_feedback.issue_annotations, '[]'::jsonb)) as annotation(value);

    if v_feedback.feedback_key = v_feedback_key
       and v_feedback.source_review_schema = 'record-feedback-v2'
       and v_feedback.semantic_hash = v_requested_hash
       and v_existing_bundle = v_requested_bundle then
      update public.expression_exposure_events
      set lifecycle_state = 'user_reviewed'
      where id = p_exposure_event_id and user_id = p_user_id;

      select revision into v_revision
      from public.expression_preference_revisions
      where user_id = p_user_id;

      return jsonb_build_object(
        'feedback', to_jsonb(v_feedback),
        'source_revision', coalesce(v_revision, 0),
        'changed', false
      );
    end if;
  end if;

  -- Real changes also converge any duplicate rows left by an overlapping old
  -- Edge deployment. Signals are replaced as one semantic bundle.
  delete from public.expression_preference_signals as signal
  where signal.user_id = p_user_id
    and (
      signal.exposure_event_id = p_exposure_event_id
      or exists (
        select 1
        from public.expression_feedback_events as feedback
        where feedback.user_id = p_user_id
          and feedback.exposure_event_id = p_exposure_event_id
          and feedback.feedback_key = signal.feedback_key
      )
    );

  update public.expression_feedback_events
  set feedback_key = 'feedback-converge:' || id::text
  where user_id = p_user_id and exposure_event_id = p_exposure_event_id;

  if v_feedback_count > 0 then
    delete from public.expression_feedback_events
    where user_id = p_user_id
      and exposure_event_id = p_exposure_event_id
      and id <> v_feedback.id;
  end if;

  v_occurred_at := clock_timestamp();
  if v_feedback_count = 0 then
    insert into public.expression_feedback_events (
      occurred_at,
      user_id,
      feedback_key,
      exposure_event_id,
      candidate_id,
      semantic_key,
      surface,
      visible_field_paths,
      primary_choice,
      issue_annotations,
      free_text,
      suggested_action,
      source_review_schema,
      source_review_key,
      semantic_hash,
      metadata
    ) values (
      v_occurred_at,
      p_user_id,
      v_feedback_key,
      p_exposure_event_id,
      v_exposure.candidate_id,
      v_exposure.semantic_key,
      v_exposure.surface,
      v_exposure.visible_field_paths,
      p_feedback ->> 'primary_choice',
      v_requested_annotations,
      coalesce(p_feedback ->> 'free_text', ''),
      coalesce(p_feedback ->> 'suggested_action', ''),
      'record-feedback-v2',
      'record:' || coalesce(v_exposure.record_id::text, v_exposure.id::text),
      v_requested_hash,
      jsonb_build_object(
        'source', 'native_or_pwa_record_detail',
        'record_id', v_exposure.record_id,
        'semantic_bundle', v_requested_bundle,
        'decision_id', nullif(v_exposure.metadata ->> 'decision_id', ''),
        'policy_name', nullif(v_exposure.metadata ->> 'policy_name', ''),
        'policy_version', nullif(v_exposure.metadata ->> 'policy_version', ''),
        'selection_probability', case
          when jsonb_typeof(v_exposure.metadata -> 'selection_probability') = 'number'
            then v_exposure.metadata -> 'selection_probability'
          else null
        end
      )
    )
    returning * into v_feedback;
  else
    update public.expression_feedback_events
    set
      occurred_at = v_occurred_at,
      feedback_key = v_feedback_key,
      candidate_id = v_exposure.candidate_id,
      semantic_key = v_exposure.semantic_key,
      surface = v_exposure.surface,
      visible_field_paths = v_exposure.visible_field_paths,
      primary_choice = p_feedback ->> 'primary_choice',
      issue_annotations = v_requested_annotations,
      free_text = coalesce(p_feedback ->> 'free_text', ''),
      suggested_action = coalesce(p_feedback ->> 'suggested_action', ''),
      source_review_schema = 'record-feedback-v2',
      source_review_key = 'record:' || coalesce(v_exposure.record_id::text, v_exposure.id::text),
      semantic_hash = v_requested_hash,
      metadata = jsonb_build_object(
        'source', 'native_or_pwa_record_detail',
        'record_id', v_exposure.record_id,
        'semantic_bundle', v_requested_bundle,
        'decision_id', nullif(v_exposure.metadata ->> 'decision_id', ''),
        'policy_name', nullif(v_exposure.metadata ->> 'policy_name', ''),
        'policy_version', nullif(v_exposure.metadata ->> 'policy_version', ''),
        'selection_probability', case
          when jsonb_typeof(v_exposure.metadata -> 'selection_probability') = 'number'
            then v_exposure.metadata -> 'selection_probability'
          else null
        end
      )
    where id = v_feedback.id
    returning * into v_feedback;
  end if;

  insert into public.expression_preference_signals (
    occurred_at,
    user_id,
    signal_key,
    feedback_key,
    exposure_event_id,
    semantic_key,
    surface,
    issue_code,
    preference_dimension,
    direction,
    strength,
    aggregation_policy,
    metadata
  )
  select
    v_occurred_at,
    p_user_id,
    v_feedback_key || ':' || signal.value ->> 'issue_code',
    v_feedback_key,
    p_exposure_event_id,
    v_exposure.semantic_key,
    v_exposure.surface,
    signal.value ->> 'issue_code',
    signal.value ->> 'preference_dimension',
    signal.value ->> 'direction',
    (signal.value ->> 'strength')::numeric,
    signal.value ->> 'aggregation_policy',
    signal.value -> 'metadata'
  from jsonb_array_elements(v_requested_signals) as signal(value);

  update public.expression_exposure_events
  set lifecycle_state = 'user_reviewed'
  where id = p_exposure_event_id and user_id = p_user_id;

  insert into public.expression_preference_revisions (user_id, revision, updated_at)
  values (p_user_id, 1, now())
  on conflict (user_id) do update set
    revision = public.expression_preference_revisions.revision + 1,
    updated_at = now()
  returning revision into v_revision;

  return jsonb_build_object(
    'feedback', to_jsonb(v_feedback),
    'source_revision', v_revision,
    'changed', true
  );
end;
$$;

create or replace function public.get_expression_preference_source(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_revision bigint;
  v_feedback_rows jsonb;
  v_signal_rows jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if p_user_id is null then raise exception 'user is required'; end if;

  perform pg_advisory_xact_lock(hashtextextended('expression-feedback:' || p_user_id::text, 0));
  select revision into v_revision
  from public.expression_preference_revisions
  where user_id = p_user_id;

  select coalesce(jsonb_agg(to_jsonb(feedback)), '[]'::jsonb) into v_feedback_rows
  from (
    select feedback_key, occurred_at, primary_choice
    from public.expression_feedback_events
    where user_id = p_user_id
    order by occurred_at desc, created_at desc
    limit 2000
  ) as feedback;

  select coalesce(jsonb_agg(to_jsonb(signal)), '[]'::jsonb) into v_signal_rows
  from (
    select signal_key, occurred_at, semantic_key, surface,
      preference_dimension, direction, strength
    from public.expression_preference_signals
    where user_id = p_user_id
    order by occurred_at desc, created_at desc
    limit 2000
  ) as signal;

  return jsonb_build_object(
    'source_revision', coalesce(v_revision, 0),
    'feedback_rows', v_feedback_rows,
    'signal_rows', v_signal_rows
  );
end;
$$;

create or replace function public.upsert_expression_preference_snapshot_if_newer(
  p_user_id uuid,
  p_source_revision bigint,
  p_source_as_of timestamptz,
  p_snapshot_version text,
  p_source_feedback_count integer,
  p_source_signal_count integer,
  p_snapshot jsonb,
  p_scoring_profile jsonb
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_current_revision bigint;
  v_rows integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if p_user_id is null or p_source_revision is null then
    raise exception 'user and source revision are required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('expression-feedback:' || p_user_id::text, 0));
  select revision into v_current_revision
  from public.expression_preference_revisions
  where user_id = p_user_id;
  if coalesce(v_current_revision, 0) <> p_source_revision then return false; end if;

  insert into public.expression_preference_snapshots (
    user_id,
    updated_at,
    snapshot_version,
    source_feedback_count,
    source_signal_count,
    source_revision,
    snapshot,
    scoring_profile
  ) values (
    p_user_id,
    now(),
    p_snapshot_version,
    p_source_feedback_count,
    p_source_signal_count,
    p_source_revision,
    coalesce(p_snapshot, '{}'::jsonb),
    coalesce(p_scoring_profile, '{}'::jsonb)
  )
  on conflict (user_id) do update set
    updated_at = excluded.updated_at,
    snapshot_version = excluded.snapshot_version,
    source_feedback_count = excluded.source_feedback_count,
    source_signal_count = excluded.source_signal_count,
    source_revision = excluded.source_revision,
    snapshot = excluded.snapshot,
    scoring_profile = excluded.scoring_profile
  where public.expression_preference_snapshots.source_revision < excluded.source_revision;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

revoke all on function public.persist_expression_exposure_with_sources(uuid, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.replace_expression_feedback_bundle(uuid, uuid, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.get_expression_preference_source(uuid) from public, anon, authenticated;
revoke all on function public.upsert_expression_preference_snapshot_if_newer(uuid, bigint, timestamptz, text, integer, integer, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.persist_expression_exposure_with_sources(uuid, text, jsonb, jsonb) to service_role;
grant execute on function public.replace_expression_feedback_bundle(uuid, uuid, jsonb, jsonb) to service_role;
grant execute on function public.get_expression_preference_source(uuid) to service_role;
grant execute on function public.upsert_expression_preference_snapshot_if_newer(uuid, bigint, timestamptz, text, integer, integer, jsonb, jsonb) to service_role;

commit;
