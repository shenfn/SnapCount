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

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  legal_at text := new.raw_user_meta_data ->> 'legal_consent_at';
  sensitive_at text := new.raw_user_meta_data ->> 'sensitive_data_consent_at';
begin
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
    case when legal_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' then legal_at::timestamptz else null end,
    case when sensitive_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' then sensitive_at::timestamptz else null end,
    nullif(new.raw_user_meta_data ->> 'terms_version', ''),
    nullif(new.raw_user_meta_data ->> 'privacy_version', '')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from anon;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
