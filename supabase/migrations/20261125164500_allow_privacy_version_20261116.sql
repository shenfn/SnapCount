-- Enforce valid YYYY-MM-DD date format and minimum legal consent version
-- floor (>= 2026-07-19) instead of hardcoding a fixed enum list, so future
-- privacy/terms version bumps cannot break new user registration.
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
    or submitted_terms_version is null
    or submitted_terms_version !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or submitted_terms_version < '2026-07-19'
    or submitted_privacy_version is null
    or submitted_privacy_version !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or submitted_privacy_version < '2026-07-19'
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
