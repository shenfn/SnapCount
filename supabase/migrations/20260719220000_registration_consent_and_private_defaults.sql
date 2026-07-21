-- 注册同意字段、隐私默认值和 handle_new_user 权限收紧。

alter table public.user_configs
  alter column ai_logs_enabled set default false,
  add column if not exists legal_consent_at timestamptz,
  add column if not exists sensitive_data_consent_at timestamptz,
  add column if not exists terms_version text,
  add column if not exists privacy_version text;

comment on column public.user_configs.legal_consent_at is
  'Time when the user explicitly accepted the service terms and privacy policy.';
comment on column public.user_configs.sensitive_data_consent_at is
  'Time when the user separately accepted sensitive-data processing and the disclosed storage/AI route.';

update public.user_configs
set ai_logs_enabled = false
where ai_logs_enabled is distinct from false;

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
    or submitted_privacy_version is distinct from '2026-07-19'
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
    '2026-07-19',
    '2026-07-19'
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
