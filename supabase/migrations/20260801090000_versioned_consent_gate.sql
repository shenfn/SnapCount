-- Versioned consent gate for historical accounts.
--
-- This migration is deliberately backwards compatible with older clients:
-- registrations that do not send sensitive_data_version still succeed, but
-- remain blocked from AI processing until the account explicitly accepts the
-- current versions through accept_my_consent().

alter table public.user_configs
  add column if not exists sensitive_data_version text;

comment on column public.user_configs.sensitive_data_version is
  'Version of the sensitive-data/AI processing notice explicitly accepted by the user.';

create table if not exists public.consent_requirements (
  consent_key text primary key
    check (consent_key in ('terms', 'privacy', 'sensitive_data')),
  current_version text not null,
  effective_at timestamptz not null default now(),
  is_active boolean not null default true
);

comment on table public.consent_requirements is
  'Server-owned current versions required before sensitive or AI processing.';

insert into public.consent_requirements (consent_key, current_version)
values
  ('terms', '2026-07-19'),
  ('privacy', '2026-07-22'),
  ('sensitive_data', '2026-07-22')
on conflict (consent_key) do nothing;

alter table public.consent_requirements enable row level security;
drop policy if exists consent_requirements_service_only on public.consent_requirements;
create policy consent_requirements_service_only
  on public.consent_requirements
  for all
  using (false)
  with check (false);
revoke all on table public.consent_requirements from public, anon, authenticated;
grant select on table public.consent_requirements to service_role;

create table if not exists public.user_consent_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  terms_version text not null,
  privacy_version text not null,
  sensitive_data_version text not null,
  accepted_at timestamptz not null default now(),
  source text not null default 'client_rpc',
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_user_consent_events_user_time
  on public.user_consent_events (user_id, accepted_at desc);

alter table public.user_consent_events enable row level security;
drop policy if exists user_consent_events_service_only on public.user_consent_events;
create policy user_consent_events_service_only
  on public.user_consent_events
  for all
  using (false)
  with check (false);
revoke all on table public.user_consent_events from public, anon, authenticated;
grant select, insert on table public.user_consent_events to service_role;

-- Keep consent columns writable only through the SECURITY DEFINER RPC below.
-- Other user-config settings remain writable through the existing RLS policy.
revoke update (
  legal_consent_at,
  sensitive_data_consent_at,
  terms_version,
  privacy_version,
  sensitive_data_version
) on public.user_configs from public, anon, authenticated;

-- The registration trigger owns row creation. Keep INSERT only for legacy
-- clients that implement settings writes as INSERT ... ON CONFLICT UPDATE.
-- The trigger below permits that path only while the caller's config row
-- already exists, so a client cannot recreate a row during account deletion.
revoke insert, delete on public.user_configs from public, anon, authenticated;
grant insert on public.user_configs to authenticated;
revoke update on public.user_configs from public, anon, authenticated;
grant update (
  updated_at,
  notes,
  vision_primary,
  screenshot_vision_primary,
  photo_vision_primary,
  qwen_screenshot_model,
  qwen_photo_model,
  qwen_screenshot_enable_thinking,
  qwen_photo_enable_thinking,
  ai_insight_provider,
  companion_enabled,
  companion_memory_enabled,
  companion_persona,
  companion_memory_strength,
  companion_expression_style,
  companion_custom_note,
  ai_logs_enabled,
  prompt_optimization_enabled,
  expression_improvement_enabled,
  keep_source_images,
  image_retention_days
) on public.user_configs to authenticated;

create or replace function public.reject_client_consent_write()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  request_role text := current_user;
begin
  if request_role in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      if new.user_id is distinct from auth.uid() then
        raise exception 'user configuration rows can only be written by their owner'
          using errcode = 'insufficient_privilege';
      end if;

      -- Lock the existing row so account deletion cannot race this legacy
      -- upsert and leave a newly recreated config behind.
      perform 1
      from public.user_configs
      where user_id = new.user_id
      for key share;

      if not found then
        raise exception 'user configuration rows can only be created by the server'
          using errcode = 'insufficient_privilege';
      end if;
    end if;

    if tg_op = 'UPDATE'
       and (
         new.legal_consent_at is distinct from old.legal_consent_at
         or new.sensitive_data_consent_at is distinct from old.sensitive_data_consent_at
         or new.terms_version is distinct from old.terms_version
         or new.privacy_version is distinct from old.privacy_version
         or new.sensitive_data_version is distinct from old.sensitive_data_version
       )
    then
      raise exception 'consent columns can only be changed through the consent RPC'
        using errcode = 'insufficient_privilege';
    end if;

  end if;
  return new;
end;
$$;

revoke all on function public.reject_client_consent_write() from public, anon, authenticated;
drop trigger if exists tr_reject_client_consent_insert on public.user_configs;
create trigger tr_reject_client_consent_insert
  before insert on public.user_configs
  for each row execute function public.reject_client_consent_write();

drop trigger if exists tr_reject_client_consent_update on public.user_configs;
create trigger tr_reject_client_consent_update
  before update on public.user_configs
  for each row execute function public.reject_client_consent_write();

create or replace function public.get_consent_status_for_user(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  config_exists boolean := false;
  config_is_active boolean;
  config_legal_at timestamptz;
  config_sensitive_at timestamptz;
  config_terms_version text;
  config_privacy_version text;
  config_sensitive_version text;
  required_versions jsonb := '{}'::jsonb;
  accepted_versions jsonb := '{}'::jsonb;
  missing_keys jsonb := '[]'::jsonb;
  missing_count integer := 0;
begin
  if p_user_id is null then
    raise exception 'user id is required';
  end if;

  select uc.is_active,
         uc.legal_consent_at,
         uc.sensitive_data_consent_at,
         uc.terms_version,
         uc.privacy_version,
         uc.sensitive_data_version
  into config_is_active,
       config_legal_at,
       config_sensitive_at,
       config_terms_version,
       config_privacy_version,
       config_sensitive_version
  from public.user_configs uc
  where uc.user_id = p_user_id;
  config_exists := found;

  select coalesce(
    jsonb_object_agg(cr.consent_key, cr.current_version order by cr.consent_key),
    '{}'::jsonb
  )
  into required_versions
  from public.consent_requirements cr
  where cr.is_active = true;

  if (required_versions ? 'terms') is not true
     or (required_versions ? 'privacy') is not true
     or (required_versions ? 'sensitive_data') is not true
  then
    raise exception 'consent requirements are not configured';
  end if;

  accepted_versions := jsonb_build_object(
    'terms', config_terms_version,
    'privacy', config_privacy_version,
    'sensitive_data', config_sensitive_version
  );

  select coalesce(jsonb_agg(key order by key), '[]'::jsonb), count(*)
  into missing_keys, missing_count
  from (
    select cr.consent_key as key
    from public.consent_requirements cr
      where cr.is_active = true
      and (
        not config_exists
        or (cr.consent_key = 'terms' and (
          config_terms_version is distinct from cr.current_version
          or config_legal_at is null
        ))
        or (cr.consent_key = 'privacy' and (
          config_privacy_version is distinct from cr.current_version
          or config_legal_at is null
        ))
        or (cr.consent_key = 'sensitive_data' and (
          config_sensitive_version is distinct from cr.current_version
          or config_sensitive_at is null
        ))
      )
  ) missing;

  return jsonb_build_object(
    'user_id', p_user_id,
    'is_active', coalesce(config_is_active, false),
    'needs_consent', missing_count > 0,
    'missing', missing_keys,
    'required_versions', required_versions,
    'accepted_versions', accepted_versions,
    'legal_consent_at', config_legal_at,
    'sensitive_data_consent_at', config_sensitive_at
  );
end;
$$;

create or replace function public.get_my_consent_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  return public.get_consent_status_for_user(auth.uid());
end;
$$;

create or replace function public.accept_my_consent(
  p_terms_version text,
  p_privacy_version text,
  p_sensitive_data_version text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_user_id uuid := auth.uid();
  expected_terms text;
  expected_privacy text;
  expected_sensitive text;
  accepted_at timestamptz := statement_timestamp();
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select max(current_version) filter (where consent_key = 'terms'),
         max(current_version) filter (where consent_key = 'privacy'),
         max(current_version) filter (where consent_key = 'sensitive_data')
  into expected_terms, expected_privacy, expected_sensitive
  from public.consent_requirements
  where is_active = true;

  if expected_terms is null or expected_privacy is null or expected_sensitive is null then
    raise exception 'consent requirements are not configured';
  end if;

  if p_terms_version is distinct from expected_terms
     or p_privacy_version is distinct from expected_privacy
     or p_sensitive_data_version is distinct from expected_sensitive
  then
    raise exception 'consent versions are outdated' using errcode = 'check_violation';
  end if;

  update public.user_configs
  set legal_consent_at = accepted_at,
      sensitive_data_consent_at = accepted_at,
      terms_version = p_terms_version,
      privacy_version = p_privacy_version,
      sensitive_data_version = p_sensitive_data_version,
      updated_at = accepted_at
  where user_id = current_user_id
    and is_active = true;

  if not found then
    raise exception 'user configuration is missing or inactive';
  end if;

  insert into public.user_consent_events (
    user_id,
    terms_version,
    privacy_version,
    sensitive_data_version,
    accepted_at
  ) values (
    current_user_id,
    p_terms_version,
    p_privacy_version,
    p_sensitive_data_version,
    accepted_at
  );

  return public.get_consent_status_for_user(current_user_id);
end;
$$;

revoke all on function public.get_consent_status_for_user(uuid)
  from public, anon, authenticated;
grant execute on function public.get_consent_status_for_user(uuid) to service_role;

revoke all on function public.get_my_consent_status()
  from public, anon;
grant execute on function public.get_my_consent_status() to authenticated;

revoke all on function public.accept_my_consent(text, text, text)
  from public, anon;
grant execute on function public.accept_my_consent(text, text, text) to authenticated;

-- Preserve the existing registration contract while recording the optional
-- sensitive-data version when a newer client provides it. Older clients are
-- intentionally left with NULL and will be stopped by the gate at AI time.
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
  submitted_sensitive_version text := new.raw_user_meta_data ->> 'sensitive_data_version';
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

  if submitted_sensitive_version is not null
     and submitted_sensitive_version is distinct from '2026-07-22'
  then
    raise exception 'sensitive data consent version is outdated';
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
    privacy_version,
    sensitive_data_version
  ) values (
    new.id,
    'seed',
    100,
    30,
    true,
    accepted_at,
    accepted_at,
    submitted_terms_version,
    submitted_privacy_version,
    submitted_sensitive_version
  )
  on conflict (user_id) do nothing;

  if submitted_sensitive_version is not null then
    insert into public.user_consent_events (
      user_id,
      terms_version,
      privacy_version,
      sensitive_data_version,
      accepted_at,
      source
    ) values (
      new.id,
      submitted_terms_version,
      submitted_privacy_version,
      submitted_sensitive_version,
      accepted_at,
      'registration'
    );
  end if;

  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
