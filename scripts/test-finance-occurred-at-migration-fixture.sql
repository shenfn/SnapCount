\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end;
$$;

create schema auth;
grant usage on schema auth, public to anon, authenticated;

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table auth.users (
  id uuid primary key
);

create type public.account_type as enum (
  'cash',
  'wallet_balance',
  'debit_card',
  'credit_card',
  'credit_line',
  'other'
);

create type public.account_entry_direction as enum ('in', 'out');
create type public.account_entry_type as enum (
  'opening_balance',
  'snapshot_initialization',
  'expense',
  'income',
  'transfer',
  'adjustment'
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  type public.account_type not null default 'other'
);

create table public.staging_records (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id),
  status text not null default 'pending_review',
  image_path text,
  image_hash text,
  detected_domain_key text,
  confidence numeric,
  occurred_at timestamptz,
  order_finished_at timestamptz,
  extracted_json jsonb not null default '{}'::jsonb,
  companion_message text,
  target_domain_id uuid,
  target_record_id uuid,
  resolved_action text,
  resolved_at timestamptz
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  type text not null default 'expense',
  amount numeric not null default 1,
  merchant_name text,
  platform text,
  category text,
  payment_method text,
  status text not null default 'done',
  transaction_date date not null default current_date,
  transaction_time time,
  source text not null default 'ai_scan',
  image_url text,
  image_hash text,
  companion_message text,
  note text,
  is_large_transport boolean not null default false,
  transport_type text,
  user_id uuid not null references auth.users(id),
  account_id uuid references public.accounts(id),
  staging_record_id uuid references public.staging_records(id)
);

create table public.income_records (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  category text,
  source_name text,
  amount numeric not null default 1,
  income_date date not null default current_date,
  note text,
  source text not null default 'ai_scan',
  image_url text,
  image_hash text,
  companion_message text,
  user_id uuid not null references auth.users(id),
  account_id uuid references public.accounts(id),
  source_pending_transaction_id uuid,
  staging_record_id uuid references public.staging_records(id)
);

create table public.account_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  account_id uuid not null references public.accounts(id),
  direction public.account_entry_direction not null,
  amount numeric not null check (amount > 0),
  entry_type public.account_entry_type not null,
  source_table text,
  source_id uuid,
  occurred_at timestamptz,
  note text,
  is_voided boolean not null default false,
  voided_reason text,
  created_at timestamptz not null default now()
);

create table public.ai_recognition_logs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id),
  target_table text,
  target_id uuid,
  occurred_at timestamptz,
  ai_response jsonb
);

create table public.data_domains (
  id uuid primary key default gen_random_uuid(),
  key text not null,
  name text not null,
  status text not null default 'active',
  is_system boolean not null default false,
  version text,
  user_id uuid references auth.users(id)
);

create table public.data_records (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  domain_id uuid not null references public.data_domains(id),
  domain_key text not null,
  domain_version text not null default '1.0',
  occurred_at timestamptz,
  title text,
  summary text,
  payload_jsonb jsonb not null default '{}'::jsonb,
  source text not null default 'staging',
  source_image_path text,
  source_image_hash text,
  staging_record_id uuid references public.staging_records(id),
  user_id uuid not null references auth.users(id),
  linked_account_id uuid references public.accounts(id),
  account_snapshot_kind text,
  snapshot_balance numeric(14,2),
  snapshot_at timestamptz
);

create table public.user_routing_feedback (
  id uuid primary key default gen_random_uuid(),
  staging_record_id uuid,
  image_hash text,
  original_domain_key text,
  corrected_domain_key text,
  action text,
  confidence numeric,
  payload_jsonb jsonb,
  user_id uuid not null references auth.users(id)
);

create or replace function public.resolve_account_entry_direction(
  p_account_id uuid,
  p_entry_type text,
  p_fallback_direction text
)
returns public.account_entry_direction
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_type public.account_type;
begin
  select type into v_type
  from public.accounts
  where id = p_account_id
    and user_id = auth.uid();

  if p_entry_type = 'expense' and v_type in ('credit_card', 'credit_line') then
    return 'in'::public.account_entry_direction;
  end if;

  return p_fallback_direction::public.account_entry_direction;
end;
$$;

create or replace function public.create_account_entry_for_record(
  p_account_id uuid,
  p_direction text,
  p_amount numeric,
  p_entry_type text,
  p_source_table text default null,
  p_source_id uuid default null,
  p_occurred_at timestamptz default now(),
  p_note text default null
)
returns public.account_entries
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_entry public.account_entries%rowtype;
begin
  insert into public.account_entries (
    user_id, account_id, direction, amount, entry_type,
    source_table, source_id, occurred_at, note
  ) values (
    auth.uid(), p_account_id, p_direction::public.account_entry_direction,
    p_amount, p_entry_type::public.account_entry_type, p_source_table,
    p_source_id, coalesce(p_occurred_at, now()), p_note
  ) returning * into v_entry;
  return v_entry;
end;
$$;

create or replace function public.void_account_entries_for_record(
  p_source_table text,
  p_source_id uuid,
  p_reason text default 'source_deleted'
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_count integer;
begin
  update public.account_entries
     set is_voided = true,
         voided_reason = coalesce(p_reason, 'source_deleted')
   where user_id = auth.uid()
     and source_table = p_source_table
     and source_id = p_source_id
     and is_voided = false;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.save_transaction_with_account(
  p_id uuid default null,
  p_amount numeric default null,
  p_merchant_name text default null,
  p_platform text default null,
  p_category text default null,
  p_payment_method text default null,
  p_transaction_date date default current_date,
  p_transaction_time time default null,
  p_note text default null,
  p_is_large_transport boolean default false,
  p_transport_type text default null,
  p_source text default 'manual',
  p_image_url text default null,
  p_image_hash text default null,
  p_companion_message text default null,
  p_account_id uuid default null
)
returns public.transactions
language plpgsql
security definer
as $$
begin
  return null;
end;
$$;

create or replace function public.save_income_with_account(
  p_id uuid default null,
  p_category text default null,
  p_source_name text default null,
  p_amount numeric default null,
  p_income_date date default current_date,
  p_note text default null,
  p_source text default 'manual',
  p_image_url text default null,
  p_image_hash text default null,
  p_companion_message text default null,
  p_account_id uuid default null
)
returns public.income_records
language plpgsql
security definer
as $$
begin
  return null;
end;
$$;

grant execute on function public.save_transaction_with_account(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid) to public, anon, authenticated;
grant execute on function public.save_income_with_account(uuid, text, text, numeric, date, text, text, text, text, text, uuid) to public, anon, authenticated;

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into public.accounts (id, user_id, name, type) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', '11111111-1111-4111-8111-111111111111', 'Owner cash', 'cash'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', '22222222-2222-4222-8222-222222222222', 'Other cash', 'cash');

insert into public.staging_records (
  id, user_id, occurred_at, extracted_json
) values
  (
    '10000000-0000-4000-8000-000000000001',
    '11111111-1111-4111-8111-111111111111',
    '2026-08-07T22:41:00Z',
    '{"occurred_at":"2026-08-07T22:41:00Z"}'::jsonb
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    '11111111-1111-4111-8111-111111111111',
    '2026-08-07T22:42:00Z',
    '{}'::jsonb
  ),
  (
    '10000000-0000-4000-8000-000000000003',
    '11111111-1111-4111-8111-111111111111',
    '2026-08-07T22:43:00Z',
    '{"occurred_at":"2026-08-08"}'::jsonb
  ),
  (
    '10000000-0000-4000-8000-000000000004',
    '11111111-1111-4111-8111-111111111111',
    '2026-08-07T22:44:00Z',
    '{"time_context":{"event_time_source":"fallback","event_time":"2026-08-07T22:44:00Z"}}'::jsonb
  ),
  (
    '10000000-0000-4000-8000-000000000005',
    '11111111-1111-4111-8111-111111111111',
    '2026-08-07T22:45:00Z',
    '{"time_context":{"event_time_source":"ai_order_finished_at","event_time":"2026-08-07T22:45:00Z"}}'::jsonb
  ),
  (
    '10000000-0000-4000-8000-000000000006',
    '22222222-2222-4222-8222-222222222222',
    '2026-08-07T22:46:00Z',
    '{"occurred_at":"2026-08-07T22:46:00Z"}'::jsonb
  );

insert into public.transactions (
  id, user_id, staging_record_id, transaction_date, transaction_time
) values
  ('20000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000001', '2026-01-01', '01:01:00'),
  ('20000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000002', '2026-01-01', '01:02:00'),
  ('20000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000003', '2026-01-01', '01:03:00'),
  ('20000000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000004', '2026-01-01', '01:04:00'),
  ('20000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000006', '2026-01-01', '01:05:00'),
  ('20000000-0000-4000-8000-000000000006', '11111111-1111-4111-8111-111111111111', null, '2026-01-01', '01:06:00'),
  ('20000000-0000-4000-8000-000000000007', '11111111-1111-4111-8111-111111111111', null, '2026-01-01', '01:07:00');

insert into public.income_records (
  id, user_id, staging_record_id, income_date
) values
  ('30000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000005', '2026-01-01'),
  ('30000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', null, '2026-01-01');

insert into public.ai_recognition_logs (
  id, created_at, user_id, target_table, target_id, occurred_at, ai_response
) values
  (
    '40000000-0000-4000-8000-000000000001',
    '2026-08-08T00:00:00Z',
    '11111111-1111-4111-8111-111111111111',
    'transactions',
    '20000000-0000-4000-8000-000000000006',
    '2026-08-07T22:47:00Z',
    '{"order_finished_at":"2026-08-07T22:47:00Z"}'::jsonb
  ),
  (
    '40000000-0000-4000-8000-000000000002',
    '2026-08-08T00:01:00Z',
    '11111111-1111-4111-8111-111111111111',
    'transactions',
    '20000000-0000-4000-8000-000000000007',
    '2026-08-07T22:48:00Z',
    '{"occurred_at":"2026-08-08"}'::jsonb
  ),
  (
    '40000000-0000-4000-8000-000000000003',
    '2026-08-08T00:02:00Z',
    '11111111-1111-4111-8111-111111111111',
    'income_records',
    '30000000-0000-4000-8000-000000000002',
    '2026-08-07T22:49:00Z',
    '{"occurred_at":"2026-99-99T22:49:00Z"}'::jsonb
  );

insert into public.account_entries (
  id, user_id, account_id, direction, amount, entry_type,
  source_table, source_id, occurred_at
) values
  (
    '50000000-0000-4000-8000-000000000001',
    '11111111-1111-4111-8111-111111111111',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    'out', 1, 'expense', 'transactions',
    '20000000-0000-4000-8000-000000000001',
    '2020-01-01T00:00:00Z'
  ),
  (
    '50000000-0000-4000-8000-000000000002',
    '22222222-2222-4222-8222-222222222222',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    'out', 1, 'expense', 'transactions',
    '20000000-0000-4000-8000-000000000001',
    '2020-01-02T00:00:00Z'
  ),
  (
    '50000000-0000-4000-8000-000000000003',
    '11111111-1111-4111-8111-111111111111',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    'in', 1, 'income', 'income_records',
    '30000000-0000-4000-8000-000000000001',
    '2020-01-03T00:00:00Z'
  );
