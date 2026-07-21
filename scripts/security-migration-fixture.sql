do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$$;

alter role service_role bypassrls;

create schema auth;
create schema storage;

grant usage on schema auth, storage, public to anon, authenticated, service_role;

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create function auth.role()
returns text
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.role', true), '');
$$;

create table auth.users (
  id uuid primary key,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

create table public.user_configs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null default 'seed',
  monthly_quota integer not null default 100,
  daily_quota integer not null default 30,
  is_active boolean not null default true,
  ai_logs_enabled boolean not null default true
);

create table public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique,
  status text not null default 'requested'
    check (status in ('requested', 'cleaning', 'deleting', 'completed', 'failed')),
  updated_at timestamptz not null default now()
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid references auth.users(id) on delete cascade,
  image_url text
);

create table public.income_records (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid references auth.users(id) on delete cascade,
  image_url text
);

create table public.data_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  source_image_path text
);

create table public.staging_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  image_path text,
  perceptual_hash text
);

alter table public.transactions
  add column staging_record_id uuid references public.staging_records(id) on delete set null;

alter table public.income_records
  add column staging_record_id uuid references public.staging_records(id) on delete set null;

create table public.ai_recognition_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  image_url text
);

create table public.expression_exposure_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade
);

create table public.expression_feedback_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exposure_event_id uuid not null references public.expression_exposure_events(id) on delete restrict
);

create table public.expression_preference_signals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exposure_event_id uuid references public.expression_exposure_events(id) on delete restrict
);

create table public.expression_preference_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table public.expression_shadow_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade
);

create table public.user_routing_feedback (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.ai_insights (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.user_companion_memories (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.user_domain_profiles (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.liability_payments (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.account_repayment_cycles (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.account_entries (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.budgets (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.accounts (id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.data_domains (id uuid primary key default gen_random_uuid(), user_id uuid);

create table public.image_cleanup_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket_name text not null default 'receipt-images',
  bucket_path text not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  cleanup_reason text not null default 'manual_cleanup',
  source_table text,
  source_id uuid,
  last_error text,
  processed_at timestamptz,
  last_attempt_at timestamptz,
  next_retry_at timestamptz,
  deleted_at timestamptz,
  storage_deleted_at timestamptz,
  references_cleared_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (user_id, bucket_path)
);

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null,
  name text not null,
  unique (bucket_id, name)
);

alter table public.transactions enable row level security;
alter table public.income_records enable row level security;
alter table public.data_records enable row level security;
alter table public.staging_records enable row level security;
alter table storage.objects enable row level security;

create policy tx_user_access on public.transactions
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy income_user_access on public.income_records
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy data_user_access on public.data_records
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy staging_user_access on public.staging_records
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy allow_anon_select_receipt_images on storage.objects
  for select to anon using (bucket_id = 'receipt-images');
create policy allow_anon_delete_receipt_images on storage.objects
  for delete to anon using (bucket_id = 'receipt-images');
create policy allow_auth_select_receipt_images on storage.objects
  for select to authenticated using (bucket_id = 'receipt-images');
create policy allow_auth_delete_receipt_images on storage.objects
  for delete to authenticated using (bucket_id = 'receipt-images');

grant select, insert, update, delete on public.transactions, public.income_records, public.data_records, public.staging_records to authenticated;
grant select, delete on storage.objects to anon, authenticated;
grant all on all tables in schema public, storage, auth to service_role;

create function public.rebuild_expense_profile(uuid) returns jsonb language sql stable security definer as $$ select '{}'::jsonb $$;
create function public.rebuild_sleep_profile(uuid) returns jsonb language sql stable security definer as $$ select '{}'::jsonb $$;
create function public.rebuild_sport_profile(uuid) returns jsonb language sql stable security definer as $$ select '{}'::jsonb $$;
create function public.rebuild_food_profile(uuid) returns jsonb language sql stable security definer as $$ select '{}'::jsonb $$;
create function public.rebuild_reading_profile(uuid) returns jsonb language sql stable security definer as $$ select '{}'::jsonb $$;
create function public.rebuild_wallet_profile(uuid) returns jsonb language sql stable security definer as $$ select '{}'::jsonb $$;
create function public.refresh_domain_profile(uuid, text) returns void language sql security definer as $$ select $$;
create function public.recalculate_account_balance(uuid) returns numeric language sql security definer as $$ select 0::numeric $$;

create function public.handle_new_user() returns trigger language plpgsql security definer as $$ begin return new; end $$;
create function public.maintain_account_balance() returns trigger language plpgsql security definer as $$ begin return new; end $$;
create function public.reset_image_cleanup_phase_on_requeue() returns trigger language plpgsql as $$ begin return new; end $$;
create function public.prevent_reference_during_image_cleanup() returns trigger language plpgsql security definer as $$ begin return new; end $$;
create function public.queue_legacy_image_after_record_delete() returns trigger language plpgsql security definer as $$ begin return old; end $$;
create function public.confirm_staging_repayment(uuid, uuid, numeric, timestamptz, uuid, text, text)
returns void language sql security definer as $$ select $$;

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into public.user_configs (user_id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into storage.objects (bucket_id, name) values
  ('receipt-images', '2026-01-01/victim.jpg'),
  ('receipt-images', '2026-01-02/owner.jpg'),
  ('receipt-images', '2026-01-05/log-only.jpg'),
  ('receipt-images', '11111111-1111-4111-8111-111111111111/new.jpg');

insert into public.transactions (user_id, image_url) values
  ('11111111-1111-4111-8111-111111111111', 'https://fixture.supabase.co/storage/v1/object/sign/receipt-images/2026-01-02/owner.jpg?token=legacy'),
  ('22222222-2222-4222-8222-222222222222', '2026-01-01/victim.jpg');

insert into public.staging_records (user_id, image_path) values (
  '11111111-1111-4111-8111-111111111111',
  '2026-01-03/missing-object.jpg'
);

insert into public.ai_recognition_logs (user_id, image_url) values (
  '11111111-1111-4111-8111-111111111111',
  'https://fixture.supabase.co/storage/v1/object/sign/receipt-images/2026-01-05/log-only.jpg?token=legacy'
);
