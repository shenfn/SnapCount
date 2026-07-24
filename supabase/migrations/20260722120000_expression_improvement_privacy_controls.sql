-- Explicit opt-in, payload minimization support, and retention for Expression Shadow data.

alter table public.user_configs
  add column if not exists expression_improvement_enabled boolean not null default false,
  add column if not exists expression_improvement_consent_at timestamptz,
  add column if not exists expression_improvement_withdrawn_at timestamptz;

comment on column public.user_configs.expression_improvement_enabled is
  'Explicit opt-in for minimized Expression Planner improvement telemetry. Defaults to false.';
comment on column public.user_configs.expression_improvement_consent_at is
  'Server timestamp of the latest explicit Expression Planner improvement opt-in.';
comment on column public.user_configs.expression_improvement_withdrawn_at is
  'Server timestamp of the latest Expression Planner improvement opt-out.';

create or replace function public.stamp_expression_improvement_consent()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' then
    if new.expression_improvement_enabled then
      new.expression_improvement_consent_at := statement_timestamp();
      new.expression_improvement_withdrawn_at := null;
    else
      new.expression_improvement_consent_at := null;
      new.expression_improvement_withdrawn_at := null;
    end if;
    return new;
  end if;

  if new.expression_improvement_enabled and not old.expression_improvement_enabled then
    new.expression_improvement_consent_at := statement_timestamp();
    new.expression_improvement_withdrawn_at := null;
  elsif not new.expression_improvement_enabled and old.expression_improvement_enabled then
    new.expression_improvement_consent_at := old.expression_improvement_consent_at;
    new.expression_improvement_withdrawn_at := statement_timestamp();
  else
    new.expression_improvement_consent_at := old.expression_improvement_consent_at;
    new.expression_improvement_withdrawn_at := old.expression_improvement_withdrawn_at;
  end if;
  return new;
end;
$$;

revoke all on function public.stamp_expression_improvement_consent()
  from public, anon, authenticated, service_role;

drop trigger if exists tr_stamp_expression_improvement_consent_insert on public.user_configs;
create trigger tr_stamp_expression_improvement_consent_insert
  before insert
  on public.user_configs
  for each row execute function public.stamp_expression_improvement_consent();

drop trigger if exists tr_stamp_expression_improvement_consent_update on public.user_configs;
create trigger tr_stamp_expression_improvement_consent_update
  before update of expression_improvement_enabled,
    expression_improvement_consent_at,
    expression_improvement_withdrawn_at
  on public.user_configs
  for each row execute function public.stamp_expression_improvement_consent();

create or replace function public.purge_user_expression_improvement_data()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.expression_improvement_enabled and not new.expression_improvement_enabled then
    delete from public.expression_shadow_runs
    where user_id = new.user_id;

    delete from public.expression_exposure_events as exposure
    where exposure.user_id = new.user_id
      and (
        exposure.metadata ->> 'source' = 'production_baseline'
        or exposure.selection_mode = 'legacy_voice'
      )
      and not exists (
        select 1
        from public.expression_feedback_events as feedback
        where feedback.exposure_event_id = exposure.id
      )
      and not exists (
        select 1
        from public.expression_preference_signals as signal
        where signal.exposure_event_id = exposure.id
      );
  end if;
  return null;
end;
$$;

revoke all on function public.purge_user_expression_improvement_data()
  from public, anon, authenticated, service_role;

drop trigger if exists tr_purge_user_expression_improvement_data on public.user_configs;
create trigger tr_purge_user_expression_improvement_data
  after update of expression_improvement_enabled on public.user_configs
  for each row execute function public.purge_user_expression_improvement_data();

create or replace function public.cleanup_expression_improvement_retention()
returns table (shadow_deleted bigint, background_exposures_deleted bigint)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  deleted_shadow bigint := 0;
  deleted_exposures bigint := 0;
begin
  delete from public.expression_shadow_runs as shadow
  where shadow.created_at < now() - interval '30 days'
    or not exists (
      select 1
      from public.user_configs as config
      where config.user_id = shadow.user_id
        and config.expression_improvement_enabled is true
    );
  get diagnostics deleted_shadow = row_count;

  delete from public.expression_exposure_events as exposure
  where (
      exposure.metadata ->> 'source' = 'production_baseline'
      or exposure.selection_mode = 'legacy_voice'
    )
    and (
      exposure.created_at < now() - interval '30 days'
      or not exists (
        select 1
        from public.user_configs as config
        where config.user_id = exposure.user_id
          and config.expression_improvement_enabled is true
      )
    )
    and not exists (
      select 1
      from public.expression_feedback_events as feedback
      where feedback.exposure_event_id = exposure.id
    )
    and not exists (
      select 1
      from public.expression_preference_signals as signal
      where signal.exposure_event_id = exposure.id
    );
  get diagnostics deleted_exposures = row_count;

  return query select deleted_shadow, deleted_exposures;
end;
$$;

revoke all on function public.cleanup_expression_improvement_retention()
  from public, anon, authenticated;
grant execute on function public.cleanup_expression_improvement_retention()
  to service_role;

create index if not exists idx_expression_shadow_retention
  on public.expression_shadow_runs (created_at);
create index if not exists idx_expression_background_exposure_retention
  on public.expression_exposure_events (created_at)
  where metadata ->> 'source' = 'production_baseline' or selection_mode = 'legacy_voice';

do $block$
begin
  if to_regnamespace('cron') is not null then
    execute 'select cron.unschedule(jobid) from cron.job where jobname = ''cleanup-expression-improvement-retention''';
    execute 'select cron.schedule(''cleanup-expression-improvement-retention'', ''23 19 * * *'', ''select public.cleanup_expression_improvement_retention();'')';
  end if;
end;
$block$;

-- Existing clients still submit the previous privacy version. Both versions are safe
-- during rollout because Expression improvement remains disabled until explicit opt-in.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  legal_at text := new.raw_user_meta_data ->> 'legal_consent_at';
  sensitive_at text := new.raw_user_meta_data ->> 'sensitive_data_consent_at';
  submitted_terms_version text := new.raw_user_meta_data ->> 'terms_version';
  submitted_privacy_version text := new.raw_user_meta_data ->> 'privacy_version';
  accepted_at timestamptz := now();
begin
  if legal_at is null
    or legal_at !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
    or sensitive_at is null
    or sensitive_at !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
    or submitted_terms_version is distinct from '2026-07-19'
    or submitted_privacy_version is null
    or submitted_privacy_version not in ('2026-07-19', '2026-07-22')
  then
    raise exception 'current terms, privacy, and sensitive data consent are required';
  end if;

  insert into public.user_configs (
    user_id,
    plan,
    monthly_quota,
    daily_quota,
    is_active,
    legal_consent_at,
    sensitive_data_consent_at,
    terms_version,
    privacy_version
  ) values (
    new.id,
    'seed',
    100,
    30,
    true,
    accepted_at,
    accepted_at,
    submitted_terms_version,
    submitted_privacy_version
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Remove historical background telemetry for accounts that never opted in.
select * from public.cleanup_expression_improvement_retention();
