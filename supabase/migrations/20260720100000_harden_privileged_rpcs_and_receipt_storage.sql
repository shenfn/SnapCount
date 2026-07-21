-- Close privileged RPC grants and replace bucket-wide receipt image access with
-- reference-based ownership checks that remain compatible with legacy paths.

create or replace function public.normalize_receipt_image_path(p_value text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select nullif(
    case
      when btrim(coalesce(p_value, '')) ~* '^https?://' then
        regexp_replace(
          split_part(split_part(btrim(p_value), '?', 1), '#', 1),
          '^https?://[^/]+/storage/v1/object/(sign|authenticated|public)/receipt-images/',
          '',
          'i'
        )
      else split_part(split_part(btrim(coalesce(p_value, '')), '?', 1), '#', 1)
    end,
    ''
  );
$$;

revoke all on function public.normalize_receipt_image_path(text) from public, anon, authenticated;
grant execute on function public.normalize_receipt_image_path(text) to authenticated, service_role;

create table if not exists public.receipt_image_owners (
  bucket_name text not null default 'receipt-images',
  bucket_path text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  ownership_source text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (bucket_name, bucket_path)
);

create index if not exists idx_receipt_image_owners_user
  on public.receipt_image_owners (user_id, bucket_path);

alter table public.receipt_image_owners enable row level security;
revoke all on table public.receipt_image_owners from public, anon, authenticated;
grant all on table public.receipt_image_owners to service_role;

-- Older trace rows were sometimes written before user_id was attached. When the
-- same Storage object has exactly one known owner, restore that association before
-- enforcing the one-owner invariant. Truly multi-user paths still fail below.
with owned_image_references as (
  select user_id, public.normalize_receipt_image_path(image_url) as bucket_path
  from public.transactions where user_id is not null and image_url is not null and image_url <> ''
  union all
  select user_id, public.normalize_receipt_image_path(image_url)
  from public.income_records where user_id is not null and image_url is not null and image_url <> ''
  union all
  select user_id, public.normalize_receipt_image_path(source_image_path)
  from public.data_records where user_id is not null and source_image_path is not null and source_image_path <> ''
  union all
  select user_id, public.normalize_receipt_image_path(image_path)
  from public.staging_records where user_id is not null and image_path is not null and image_path <> ''
  union all
  select user_id, public.normalize_receipt_image_path(image_url)
  from public.ai_recognition_logs where user_id is not null and image_url is not null and image_url <> ''
), unambiguous_owners as (
  select min(user_id::text)::uuid as user_id, bucket_path
  from owned_image_references
  where bucket_path is not null and bucket_path !~* '^https?://'
  group by bucket_path
  having count(distinct user_id) = 1
)
update public.ai_recognition_logs as log
set user_id = owner.user_id
from unambiguous_owners as owner
where log.user_id is null
  and public.normalize_receipt_image_path(log.image_url) = owner.bucket_path;

do $$
begin
  if exists (
    with image_references as (
      select user_id, public.normalize_receipt_image_path(image_url) as bucket_path
      from public.transactions where image_url is not null and image_url <> ''
      union all
      select user_id, public.normalize_receipt_image_path(image_url)
      from public.income_records where image_url is not null and image_url <> ''
      union all
      select user_id, public.normalize_receipt_image_path(source_image_path)
      from public.data_records where source_image_path is not null and source_image_path <> ''
      union all
      select user_id, public.normalize_receipt_image_path(image_path)
      from public.staging_records where image_path is not null and image_path <> ''
      union all
      select user_id, public.normalize_receipt_image_path(image_url)
      from public.ai_recognition_logs where image_url is not null and image_url <> ''
    )
    select 1
    from image_references
    where bucket_path is not null and bucket_path !~* '^https?://'
    group by bucket_path
    having count(distinct user_id) filter (where user_id is not null) > 1
      or (
        count(*) filter (where user_id is null) > 0
        and count(*) filter (where user_id is not null) > 0
      )
  ) then
    raise exception 'receipt image ownership backfill contains ambiguous paths';
  end if;
end;
$$;

with image_references as (
  select user_id, public.normalize_receipt_image_path(image_url) as bucket_path
  from public.transactions where user_id is not null and image_url is not null and image_url <> ''
  union all
  select user_id, public.normalize_receipt_image_path(image_url)
  from public.income_records where user_id is not null and image_url is not null and image_url <> ''
  union all
  select user_id, public.normalize_receipt_image_path(source_image_path)
  from public.data_records where user_id is not null and source_image_path is not null and source_image_path <> ''
  union all
  select user_id, public.normalize_receipt_image_path(image_path)
  from public.staging_records where user_id is not null and image_path is not null and image_path <> ''
  union all
  select user_id, public.normalize_receipt_image_path(image_url)
  from public.ai_recognition_logs where user_id is not null and image_url is not null and image_url <> ''
), unambiguous as (
  select min(user_id::text)::uuid as user_id, bucket_path
  from image_references
  where bucket_path is not null and bucket_path !~* '^https?://'
  group by bucket_path
  having count(distinct user_id) = 1
)
insert into public.receipt_image_owners (
  bucket_name,
  bucket_path,
  user_id,
  ownership_source
)
select 'receipt-images', u.bucket_path, u.user_id, 'migration_backfill'
from unambiguous u
on conflict (bucket_name, bucket_path) do update
set user_id = excluded.user_id,
    ownership_source = excluded.ownership_source,
    updated_at = now();

create table if not exists public.receipt_image_migration_jobs (
  id uuid primary key default gen_random_uuid(),
  bucket_name text not null default 'receipt-images',
  user_id uuid not null references auth.users(id) on delete cascade,
  old_path text not null,
  new_path text not null,
  status text not null default 'pending'
    check (status in ('pending', 'copied', 'references_updated', 'done')),
  old_sha256 text,
  new_sha256 text,
  reference_count integer not null default 0,
  attempts integer not null default 0,
  last_error text,
  copied_at timestamptz,
  references_updated_at timestamptz,
  old_object_deleted_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (bucket_name, old_path),
  unique (bucket_name, new_path)
);

alter table public.receipt_image_migration_jobs
  add column if not exists lease_token uuid,
  add column if not exists lease_expires_at timestamptz;

create index if not exists idx_receipt_image_migration_jobs_status
  on public.receipt_image_migration_jobs (status, updated_at)
  where status <> 'done';

alter table public.receipt_image_migration_jobs enable row level security;
revoke all on table public.receipt_image_migration_jobs from public, anon, authenticated, service_role;
grant select on table public.receipt_image_migration_jobs to service_role;

create or replace function public.enforce_receipt_image_reference_ownership()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_raw_path text := to_jsonb(new) ->> tg_argv[0];
  v_bucket_path text := public.normalize_receipt_image_path(v_raw_path);
  v_user_id uuid := nullif(to_jsonb(new) ->> 'user_id', '')::uuid;
  v_owner_id uuid;
  v_is_own_scoped_path boolean;
  v_is_any_scoped_path boolean;
  v_is_legacy_path boolean;
begin
  if v_user_id is null then
    return new;
  end if;

  if exists (
    select 1
    from public.account_deletion_requests
    where user_id = v_user_id
      and status in ('requested', 'cleaning', 'deleting', 'failed')
  ) and not (auth.role() = 'service_role' and v_bucket_path is null) then
    raise exception 'account deletion is in progress';
  end if;

  if v_bucket_path is null or v_bucket_path ~* '^https?://' then
    return new;
  end if;

  if exists (
    select 1
    from public.receipt_image_migration_jobs
    where bucket_name = 'receipt-images'
      and old_path = v_bucket_path
      and status <> 'done'
  ) then
    raise exception 'receipt image path migration is in progress';
  end if;

  select user_id into v_owner_id
  from public.receipt_image_owners
  where bucket_name = 'receipt-images' and bucket_path = v_bucket_path;

  if found then
    if v_owner_id <> v_user_id then
      raise exception 'receipt image path belongs to another user';
    end if;
    return new;
  end if;

  v_is_own_scoped_path := v_bucket_path like v_user_id::text || '/%'
    or v_bucket_path like 'tmp/' || v_user_id::text || '/%';
  v_is_any_scoped_path := v_bucket_path ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/'
    or v_bucket_path ~* '^tmp/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/';
  v_is_legacy_path := v_bucket_path ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}/[A-Za-z0-9][A-Za-z0-9._-]*$';

  if v_is_any_scoped_path and not v_is_own_scoped_path then
    raise exception 'receipt image path belongs to another user';
  end if;

  if not v_is_own_scoped_path
    and not (v_is_legacy_path and auth.role() = 'service_role')
  then
    raise exception 'receipt image path ownership is not registered';
  end if;

  insert into public.receipt_image_owners (
    bucket_name,
    bucket_path,
    user_id,
    ownership_source
  ) values (
    'receipt-images',
    v_bucket_path,
    v_user_id,
    case when v_is_legacy_path then 'service_legacy_reference' else 'user_scoped_reference' end
  )
  on conflict (bucket_name, bucket_path) do nothing;

  select user_id into v_owner_id
  from public.receipt_image_owners
  where bucket_name = 'receipt-images' and bucket_path = v_bucket_path;

  if v_owner_id is distinct from v_user_id then
    raise exception 'receipt image path belongs to another user';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_receipt_image_reference_ownership() from public, anon, authenticated;

drop trigger if exists tr_transactions_receipt_image_owner on public.transactions;
create trigger tr_transactions_receipt_image_owner
  before insert or update of image_url, user_id on public.transactions
  for each row execute function public.enforce_receipt_image_reference_ownership('image_url');

drop trigger if exists tr_income_receipt_image_owner on public.income_records;
create trigger tr_income_receipt_image_owner
  before insert or update of image_url, user_id on public.income_records
  for each row execute function public.enforce_receipt_image_reference_ownership('image_url');

drop trigger if exists tr_data_receipt_image_owner on public.data_records;
create trigger tr_data_receipt_image_owner
  before insert or update of source_image_path, user_id on public.data_records
  for each row execute function public.enforce_receipt_image_reference_ownership('source_image_path');

drop trigger if exists tr_staging_receipt_image_owner on public.staging_records;
create trigger tr_staging_receipt_image_owner
  before insert or update of image_path, user_id on public.staging_records
  for each row execute function public.enforce_receipt_image_reference_ownership('image_path');

drop trigger if exists tr_ai_logs_receipt_image_owner on public.ai_recognition_logs;
create trigger tr_ai_logs_receipt_image_owner
  before insert or update of image_url, user_id on public.ai_recognition_logs
  for each row execute function public.enforce_receipt_image_reference_ownership('image_url');

create index if not exists idx_transactions_user_receipt_image_path
  on public.transactions (user_id, public.normalize_receipt_image_path(image_url))
  where image_url is not null and image_url <> '';

create index if not exists idx_income_user_receipt_image_path
  on public.income_records (user_id, public.normalize_receipt_image_path(image_url))
  where image_url is not null and image_url <> '';

create index if not exists idx_data_user_receipt_image_path
  on public.data_records (user_id, public.normalize_receipt_image_path(source_image_path))
  where source_image_path is not null and source_image_path <> '';

create index if not exists idx_staging_user_receipt_image_path
  on public.staging_records (user_id, public.normalize_receipt_image_path(image_path))
  where image_path is not null and image_path <> '';

create or replace function public.can_access_receipt_image(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  with requested as (
    select public.normalize_receipt_image_path(p_object_name) as bucket_path
  )
  select auth.uid() is not null
    and requested.bucket_path is not null
    and exists (
      select 1
      from public.receipt_image_owners
      where bucket_name = 'receipt-images'
        and bucket_path = requested.bucket_path
        and user_id = auth.uid()
    )
    and (
      exists (
        select 1
        from public.transactions
        where user_id = auth.uid()
          and public.normalize_receipt_image_path(image_url) = requested.bucket_path
      )
      or exists (
        select 1
        from public.income_records
        where user_id = auth.uid()
          and public.normalize_receipt_image_path(image_url) = requested.bucket_path
      )
      or exists (
        select 1
        from public.data_records
        where user_id = auth.uid()
          and public.normalize_receipt_image_path(source_image_path) = requested.bucket_path
      )
      or exists (
        select 1
        from public.staging_records
        where user_id = auth.uid()
          and public.normalize_receipt_image_path(image_path) = requested.bucket_path
      )
    )
  from requested;
$$;

revoke all on function public.can_access_receipt_image(text) from public, anon, authenticated;
grant execute on function public.can_access_receipt_image(text) to authenticated, service_role;

drop policy if exists allow_anon_select_receipt_images on storage.objects;
drop policy if exists allow_anon_delete_receipt_images on storage.objects;
drop policy if exists allow_auth_select_receipt_images on storage.objects;
drop policy if exists allow_auth_delete_receipt_images on storage.objects;
drop policy if exists receipt_images_authenticated_select_own on storage.objects;

create policy receipt_images_authenticated_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'receipt-images'
    and public.can_access_receipt_image(name)
  );

create or replace function public.is_business_image_path_referenced(
  p_user_id uuid,
  p_bucket_path text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with requested as (
    select public.normalize_receipt_image_path(p_bucket_path) as bucket_path
  )
  select requested.bucket_path is not null
    and (
      exists (
        select 1 from public.transactions
        where user_id = p_user_id
          and public.normalize_receipt_image_path(image_url) = requested.bucket_path
      )
      or exists (
        select 1 from public.income_records
        where user_id = p_user_id
          and public.normalize_receipt_image_path(image_url) = requested.bucket_path
      )
      or exists (
        select 1 from public.data_records
        where user_id = p_user_id
          and public.normalize_receipt_image_path(source_image_path) = requested.bucket_path
      )
      or exists (
        select 1 from public.staging_records
        where user_id = p_user_id
          and public.normalize_receipt_image_path(image_path) = requested.bucket_path
      )
    )
  from requested;
$$;

revoke all on function public.is_business_image_path_referenced(uuid, text) from public, anon, authenticated;
grant execute on function public.is_business_image_path_referenced(uuid, text) to service_role;

create or replace function public.prevent_reference_during_image_cleanup()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_path text := public.normalize_receipt_image_path(to_jsonb(new) ->> tg_argv[0]);
begin
  if v_path is null then
    return new;
  end if;

  if exists (
    select 1
    from public.image_cleanup_queue q
    where q.bucket_name = 'receipt-images'
      and public.normalize_receipt_image_path(q.bucket_path) = v_path
      and q.status = 'processing'
  ) then
    raise exception 'image cleanup is in progress for this path';
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_reference_during_image_cleanup() from public, anon, authenticated;

drop trigger if exists tr_transactions_image_cleanup_guard on public.transactions;
create trigger tr_transactions_image_cleanup_guard
  before insert or update of image_url, user_id on public.transactions
  for each row execute function public.prevent_reference_during_image_cleanup('image_url');

drop trigger if exists tr_income_image_cleanup_guard on public.income_records;
create trigger tr_income_image_cleanup_guard
  before insert or update of image_url, user_id on public.income_records
  for each row execute function public.prevent_reference_during_image_cleanup('image_url');

drop trigger if exists tr_data_image_cleanup_guard on public.data_records;
create trigger tr_data_image_cleanup_guard
  before insert or update of source_image_path, user_id on public.data_records
  for each row execute function public.prevent_reference_during_image_cleanup('source_image_path');

drop trigger if exists tr_staging_image_cleanup_guard on public.staging_records;
create trigger tr_staging_image_cleanup_guard
  before insert or update of image_path, user_id on public.staging_records
  for each row execute function public.prevent_reference_during_image_cleanup('image_path');

create or replace function public.queue_legacy_image_after_record_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_path text := public.normalize_receipt_image_path(to_jsonb(old) ->> tg_argv[0]);
  v_user_id uuid := nullif(to_jsonb(old) ->> 'user_id', '')::uuid;
begin
  if v_user_id is null
    or v_path is null
    or v_path ~* '^https?://'
    or not exists (
      select 1
      from public.receipt_image_owners
      where bucket_name = 'receipt-images'
        and bucket_path = v_path
        and user_id = v_user_id
    )
    or public.is_business_image_path_referenced(v_user_id, v_path)
  then
    return old;
  end if;

  insert into public.image_cleanup_queue (
    user_id,
    bucket_name,
    bucket_path,
    status,
    attempts,
    cleanup_reason,
    source_table,
    source_id,
    last_error,
    processed_at,
    last_attempt_at,
    next_retry_at,
    deleted_at,
    storage_deleted_at,
    references_cleared_at,
    updated_at
  ) values (
    v_user_id,
    'receipt-images',
    v_path,
    'pending',
    0,
    'record_delete',
    tg_table_name,
    old.id,
    null,
    null,
    null,
    now(),
    null,
    null,
    null,
    now()
  )
  on conflict (user_id, bucket_path) do update
  set status = 'pending',
      attempts = 0,
      cleanup_reason = 'record_delete',
      source_table = excluded.source_table,
      source_id = excluded.source_id,
      last_error = null,
      processed_at = null,
      last_attempt_at = null,
      next_retry_at = now(),
      deleted_at = null,
      storage_deleted_at = null,
      references_cleared_at = null,
      updated_at = now();

  return old;
end;
$$;

revoke all on function public.queue_legacy_image_after_record_delete() from public, anon, authenticated;

drop trigger if exists tr_transactions_legacy_image_delete on public.transactions;
create trigger tr_transactions_legacy_image_delete
  after delete on public.transactions
  for each row execute function public.queue_legacy_image_after_record_delete('image_url');

drop trigger if exists tr_income_legacy_image_delete on public.income_records;
create trigger tr_income_legacy_image_delete
  after delete on public.income_records
  for each row execute function public.queue_legacy_image_after_record_delete('image_url');

drop trigger if exists tr_data_legacy_image_delete on public.data_records;
create trigger tr_data_legacy_image_delete
  after delete on public.data_records
  for each row execute function public.queue_legacy_image_after_record_delete('source_image_path');

drop trigger if exists tr_staging_legacy_image_delete on public.staging_records;
create trigger tr_staging_legacy_image_delete
  after delete on public.staging_records
  for each row execute function public.queue_legacy_image_after_record_delete('image_path');

create or replace function public.delete_user_account_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_user_id is null then
    raise exception 'user id is required';
  end if;

  delete from public.expression_preference_signals where user_id = p_user_id;
  delete from public.expression_feedback_events where user_id = p_user_id;
  delete from public.expression_exposure_events where user_id = p_user_id;
  delete from public.expression_preference_snapshots where user_id = p_user_id;
  delete from public.expression_shadow_runs where user_id = p_user_id;
  delete from public.user_routing_feedback where user_id = p_user_id;
  delete from public.ai_recognition_logs where user_id = p_user_id;
  delete from public.ai_insights where user_id = p_user_id;
  delete from public.user_companion_memories where user_id = p_user_id;
  delete from public.user_domain_profiles where user_id = p_user_id;
  delete from public.liability_payments where user_id = p_user_id;
  delete from public.account_repayment_cycles where user_id = p_user_id;
  delete from public.account_entries where user_id = p_user_id;
  delete from public.data_records where user_id = p_user_id;
  delete from public.staging_records where user_id = p_user_id;
  delete from public.transactions where user_id = p_user_id;
  delete from public.income_records where user_id = p_user_id;
  delete from public.budgets where user_id = p_user_id;
  if to_regclass('public.user_finance_vocabulary') is not null then
    execute 'delete from public.user_finance_vocabulary where user_id = $1' using p_user_id;
  end if;
  delete from public.accounts where user_id = p_user_id;
  delete from public.data_domains where user_id = p_user_id;
  delete from public.user_configs where user_id = p_user_id;
end;
$$;

revoke all on function public.delete_user_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_user_account_data(uuid) to service_role;

-- These helpers are only called by Edge Functions with the service role.
revoke all on function public.rebuild_expense_profile(uuid) from public, anon, authenticated;
revoke all on function public.rebuild_sleep_profile(uuid) from public, anon, authenticated;
revoke all on function public.rebuild_sport_profile(uuid) from public, anon, authenticated;
revoke all on function public.rebuild_food_profile(uuid) from public, anon, authenticated;
revoke all on function public.rebuild_reading_profile(uuid) from public, anon, authenticated;
revoke all on function public.rebuild_wallet_profile(uuid) from public, anon, authenticated;
revoke all on function public.refresh_domain_profile(uuid, text) from public, anon, authenticated;

grant execute on function public.rebuild_expense_profile(uuid) to service_role;
grant execute on function public.rebuild_sleep_profile(uuid) to service_role;
grant execute on function public.rebuild_sport_profile(uuid) to service_role;
grant execute on function public.rebuild_food_profile(uuid) to service_role;
grant execute on function public.rebuild_reading_profile(uuid) to service_role;
grant execute on function public.rebuild_wallet_profile(uuid) to service_role;
grant execute on function public.refresh_domain_profile(uuid, text) to service_role;

-- Balance repair is an administrative operation, not a client RPC.
revoke all on function public.recalculate_account_balance(uuid) from public, anon, authenticated;
grant execute on function public.recalculate_account_balance(uuid) to service_role;

-- Trigger functions do not need direct API execution privileges.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.maintain_account_balance() from public, anon, authenticated;
revoke all on function public.reset_image_cleanup_phase_on_requeue() from public, anon, authenticated;
revoke all on function public.prevent_reference_during_image_cleanup() from public, anon, authenticated;
revoke all on function public.queue_legacy_image_after_record_delete() from public, anon, authenticated;
revoke execute on function public.confirm_staging_repayment(uuid, uuid, numeric, timestamptz, uuid, text, text) from anon;

alter function public.reset_image_cleanup_phase_on_requeue() set search_path = public;

create or replace function public.prepare_receipt_image_migration(
  p_user_id uuid,
  p_old_path text,
  p_new_path text
)
returns public.receipt_image_migration_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, storage
as $$
declare
  v_old_path text := public.normalize_receipt_image_path(p_old_path);
  v_new_path text := public.normalize_receipt_image_path(p_new_path);
  v_owner_id uuid;
  v_job public.receipt_image_migration_jobs%rowtype;
begin
  if p_user_id is null or v_old_path is null or v_new_path is null then
    raise exception 'user id and non-empty image paths are required';
  end if;

  if v_old_path ~* '^https?://' or v_new_path ~* '^https?://' then
    raise exception 'storage-relative paths are required';
  end if;

  if v_old_path = v_new_path then
    raise exception 'old and new image paths must differ';
  end if;

  if v_new_path not like p_user_id::text || '/%' then
    raise exception 'new image path must be scoped to the user';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('receipt-images/' || v_old_path, 0));
  lock table public.image_cleanup_queue in share row exclusive mode;
  lock table public.transactions,
    public.income_records,
    public.data_records,
    public.staging_records,
    public.ai_recognition_logs in share row exclusive mode;

  select user_id into v_owner_id
  from public.receipt_image_owners
  where bucket_name = 'receipt-images' and bucket_path = v_old_path;

  if v_owner_id is distinct from p_user_id then
    raise exception 'legacy image ownership is not registered for the user';
  end if;

  if not exists (
    select 1 from storage.objects
    where bucket_id = 'receipt-images' and name = v_old_path
  ) then
    raise exception 'legacy Storage object does not exist';
  end if;

  if exists (
    select 1 from public.image_cleanup_queue
    where user_id = p_user_id
      and bucket_name = 'receipt-images'
      and public.normalize_receipt_image_path(bucket_path) = v_old_path
      and status in ('pending', 'failed', 'processing', 'dead_letter')
  ) then
    raise exception 'legacy image already has an active cleanup task';
  end if;

  if exists (
    select 1 from public.transactions
    where public.normalize_receipt_image_path(image_url) = v_old_path
      and user_id is distinct from p_user_id
  ) or exists (
    select 1 from public.income_records
    where public.normalize_receipt_image_path(image_url) = v_old_path
      and user_id is distinct from p_user_id
  ) or exists (
    select 1 from public.data_records
    where public.normalize_receipt_image_path(source_image_path) = v_old_path
      and user_id is distinct from p_user_id
  ) or exists (
    select 1 from public.staging_records
    where public.normalize_receipt_image_path(image_path) = v_old_path
      and user_id is distinct from p_user_id
  ) or exists (
    select 1 from public.ai_recognition_logs
    where public.normalize_receipt_image_path(image_url) = v_old_path
      and user_id is distinct from p_user_id
  ) then
    raise exception 'image path is referenced by another or unowned record';
  end if;

  if not (
    exists (
      select 1 from public.transactions
      where user_id = p_user_id
        and image_url ~* '^https://'
        and public.normalize_receipt_image_path(image_url) = v_old_path
    ) or exists (
      select 1 from public.income_records
      where user_id = p_user_id
        and image_url ~* '^https://'
        and public.normalize_receipt_image_path(image_url) = v_old_path
    ) or exists (
      select 1 from public.data_records
      where user_id = p_user_id
        and source_image_path ~* '^https://'
        and public.normalize_receipt_image_path(source_image_path) = v_old_path
    ) or exists (
      select 1 from public.staging_records
      where user_id = p_user_id
        and image_path ~* '^https://'
        and public.normalize_receipt_image_path(image_path) = v_old_path
    ) or exists (
      select 1 from public.ai_recognition_logs
      where user_id = p_user_id
        and image_url ~* '^https://'
        and public.normalize_receipt_image_path(image_url) = v_old_path
    )
  ) then
    raise exception 'no legacy signed URL reference matches the requested path';
  end if;

  insert into public.receipt_image_migration_jobs (
    bucket_name,
    user_id,
    old_path,
    new_path
  ) values (
    'receipt-images',
    p_user_id,
    v_old_path,
    v_new_path
  )
  on conflict (bucket_name, old_path) do nothing
  returning * into v_job;

  if not found then
    select * into v_job
    from public.receipt_image_migration_jobs
    where bucket_name = 'receipt-images' and old_path = v_old_path
    for update;

    if v_job.user_id <> p_user_id or v_job.new_path <> v_new_path then
      raise exception 'existing migration job does not match the requested owner or destination';
    end if;
  end if;

  return v_job;
end;
$$;

revoke all on function public.prepare_receipt_image_migration(uuid, text, text) from public, anon, authenticated;
grant execute on function public.prepare_receipt_image_migration(uuid, text, text) to service_role;

create or replace function public.claim_receipt_image_migration_job(
  p_job_id uuid,
  p_lease_token uuid,
  p_lease_seconds integer default 900
)
returns public.receipt_image_migration_jobs
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_job public.receipt_image_migration_jobs%rowtype;
  v_seconds integer := least(greatest(coalesce(p_lease_seconds, 900), 30), 3600);
begin
  if p_job_id is null or p_lease_token is null then
    raise exception 'migration job id and lease token are required';
  end if;

  select * into v_job
  from public.receipt_image_migration_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'receipt image migration job not found';
  end if;

  if v_job.status = 'done' then
    return v_job;
  end if;

  if v_job.lease_token is not null
    and v_job.lease_expires_at > now()
    and v_job.lease_token <> p_lease_token
  then
    raise exception 'receipt image migration job is leased by another worker';
  end if;

  update public.receipt_image_migration_jobs
  set lease_token = p_lease_token,
      lease_expires_at = now() + make_interval(secs => v_seconds),
      updated_at = now()
  where id = v_job.id
  returning * into v_job;

  return v_job;
end;
$$;

revoke all on function public.claim_receipt_image_migration_job(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_receipt_image_migration_job(uuid, uuid, integer) to service_role;

create or replace function public.mark_receipt_image_migration_copied(
  p_job_id uuid,
  p_lease_token uuid,
  p_old_sha256 text,
  p_new_sha256 text
)
returns public.receipt_image_migration_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, storage
as $$
declare
  v_job public.receipt_image_migration_jobs%rowtype;
begin
  select * into v_job
  from public.receipt_image_migration_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'receipt image migration job not found';
  end if;

  if v_job.status in ('copied', 'references_updated', 'done') then
    if v_job.old_sha256 is distinct from p_old_sha256
      or v_job.new_sha256 is distinct from p_new_sha256
    then
      raise exception 'copy hash does not match the recorded migration';
    end if;
    return v_job;
  end if;

  if v_job.status <> 'pending' then
    raise exception 'receipt image migration job is not pending';
  end if;
  if v_job.lease_token is distinct from p_lease_token
    or v_job.lease_expires_at is null
    or v_job.lease_expires_at <= now()
  then
    raise exception 'receipt image migration job lease is missing or expired';
  end if;
  if p_old_sha256 is null or p_new_sha256 is null
    or p_old_sha256 !~ '^[0-9a-f]{64}$'
    or p_new_sha256 !~ '^[0-9a-f]{64}$'
    or p_old_sha256 <> p_new_sha256
  then
    raise exception 'copy hashes are missing or do not match';
  end if;
  if not exists (
    select 1 from storage.objects
    where bucket_id = v_job.bucket_name and name = v_job.old_path
  ) or not exists (
    select 1 from storage.objects
    where bucket_id = v_job.bucket_name and name = v_job.new_path
  ) then
    raise exception 'source or destination Storage object is missing';
  end if;

  update public.receipt_image_migration_jobs
  set status = 'copied',
      old_sha256 = p_old_sha256,
      new_sha256 = p_new_sha256,
      copied_at = coalesce(copied_at, now()),
      last_error = null,
      lease_expires_at = now() + interval '15 minutes',
      updated_at = now()
  where id = v_job.id
    and status = 'pending'
    and lease_token = p_lease_token
    and lease_expires_at > now()
  returning * into v_job;

  if not found then
    raise exception 'receipt image migration job changed before copy commit';
  end if;
  return v_job;
end;
$$;

revoke all on function public.mark_receipt_image_migration_copied(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.mark_receipt_image_migration_copied(uuid, uuid, text, text) to service_role;

create or replace function public.record_receipt_image_migration_error(
  p_job_id uuid,
  p_lease_token uuid,
  p_expected_status text,
  p_error text
)
returns public.receipt_image_migration_jobs
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_job public.receipt_image_migration_jobs%rowtype;
begin
  select * into v_job
  from public.receipt_image_migration_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'receipt image migration job not found';
  end if;

  if v_job.status = 'done'
    or v_job.status is distinct from p_expected_status
    or v_job.lease_token is distinct from p_lease_token
  then
    return v_job;
  end if;

  update public.receipt_image_migration_jobs
  set attempts = attempts + 1,
      last_error = left(coalesce(p_error, 'migration worker failed'), 2000),
      lease_token = null,
      lease_expires_at = null,
      updated_at = now()
  where id = v_job.id
    and status = p_expected_status
    and lease_token = p_lease_token
  returning * into v_job;

  return v_job;
end;
$$;

revoke all on function public.record_receipt_image_migration_error(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.record_receipt_image_migration_error(uuid, uuid, text, text) to service_role;

create or replace function public.advance_receipt_image_migration_references(
  p_job_id uuid,
  p_lease_token uuid
)
returns public.receipt_image_migration_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, storage
as $$
declare
  v_job public.receipt_image_migration_jobs%rowtype;
  v_transactions integer := 0;
  v_income integer := 0;
  v_data integer := 0;
  v_staging integer := 0;
  v_logs integer := 0;
begin
  select * into v_job
  from public.receipt_image_migration_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'receipt image migration job not found';
  end if;

  if v_job.status = 'done' then
    return v_job;
  end if;

  if v_job.lease_token is distinct from p_lease_token
    or v_job.lease_expires_at is null
    or v_job.lease_expires_at <= now()
  then
    raise exception 'receipt image migration job lease is missing or expired';
  end if;

  if v_job.status = 'references_updated' then
    return v_job;
  end if;

  if v_job.status <> 'copied' then
    raise exception 'receipt image migration job has not completed copy verification';
  end if;

  if v_job.old_sha256 is null
    or v_job.new_sha256 is null
    or v_job.old_sha256 !~ '^[0-9a-f]{64}$'
    or v_job.old_sha256 <> v_job.new_sha256
  then
    raise exception 'receipt image copy hashes are missing or do not match';
  end if;

  if not exists (
    select 1 from storage.objects
    where bucket_id = v_job.bucket_name and name = v_job.old_path
  ) or not exists (
    select 1 from storage.objects
    where bucket_id = v_job.bucket_name and name = v_job.new_path
  ) then
    raise exception 'source or destination Storage object is missing';
  end if;

  if exists (
    select 1 from public.transactions
    where public.normalize_receipt_image_path(image_url) = v_job.old_path
      and user_id is distinct from v_job.user_id
  ) or exists (
    select 1 from public.income_records
    where public.normalize_receipt_image_path(image_url) = v_job.old_path
      and user_id is distinct from v_job.user_id
  ) or exists (
    select 1 from public.data_records
    where public.normalize_receipt_image_path(source_image_path) = v_job.old_path
      and user_id is distinct from v_job.user_id
  ) or exists (
    select 1 from public.staging_records
    where public.normalize_receipt_image_path(image_path) = v_job.old_path
      and user_id is distinct from v_job.user_id
  ) or exists (
    select 1 from public.ai_recognition_logs
    where public.normalize_receipt_image_path(image_url) = v_job.old_path
      and user_id is distinct from v_job.user_id
  ) then
    raise exception 'image path is referenced by another or unowned record';
  end if;

  update public.transactions
  set image_url = v_job.new_path
  where user_id = v_job.user_id
    and public.normalize_receipt_image_path(image_url) = v_job.old_path;
  get diagnostics v_transactions = row_count;

  update public.income_records
  set image_url = v_job.new_path
  where user_id = v_job.user_id
    and public.normalize_receipt_image_path(image_url) = v_job.old_path;
  get diagnostics v_income = row_count;

  update public.data_records
  set source_image_path = v_job.new_path
  where user_id = v_job.user_id
    and public.normalize_receipt_image_path(source_image_path) = v_job.old_path;
  get diagnostics v_data = row_count;

  update public.staging_records
  set image_path = v_job.new_path
  where user_id = v_job.user_id
    and public.normalize_receipt_image_path(image_path) = v_job.old_path;
  get diagnostics v_staging = row_count;

  update public.ai_recognition_logs
  set image_url = v_job.new_path
  where user_id = v_job.user_id
    and public.normalize_receipt_image_path(image_url) = v_job.old_path;
  get diagnostics v_logs = row_count;

  if v_transactions + v_income + v_data + v_staging + v_logs = 0 then
    raise exception 'no references matched the requested image path';
  end if;

  update public.receipt_image_migration_jobs
  set status = 'references_updated',
      reference_count = v_transactions + v_income + v_data + v_staging + v_logs,
      references_updated_at = now(),
      last_error = null,
      lease_expires_at = now() + interval '15 minutes',
      updated_at = now()
  where id = v_job.id
    and status = 'copied'
    and lease_token = p_lease_token
    and lease_expires_at > now()
  returning * into v_job;

  if not found then
    raise exception 'receipt image migration job changed before reference commit';
  end if;

  return v_job;
end;
$$;

revoke all on function public.advance_receipt_image_migration_references(uuid, uuid) from public, anon, authenticated;
grant execute on function public.advance_receipt_image_migration_references(uuid, uuid) to service_role;

create or replace function public.finalize_receipt_image_migration(
  p_job_id uuid,
  p_lease_token uuid
)
returns public.receipt_image_migration_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, storage
as $$
declare
  v_job public.receipt_image_migration_jobs%rowtype;
begin
  select * into v_job
  from public.receipt_image_migration_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'receipt image migration job not found';
  end if;

  if v_job.status = 'done' then
    return v_job;
  end if;

  if v_job.lease_token is distinct from p_lease_token
    or v_job.lease_expires_at is null
    or v_job.lease_expires_at <= now()
  then
    raise exception 'receipt image migration job lease is missing or expired';
  end if;

  if v_job.status <> 'references_updated' then
    raise exception 'receipt image references have not been migrated';
  end if;

  if exists (
    select 1 from storage.objects
    where bucket_id = v_job.bucket_name and name = v_job.old_path
  ) then
    raise exception 'legacy Storage object still exists';
  end if;

  if not exists (
    select 1 from storage.objects
    where bucket_id = v_job.bucket_name and name = v_job.new_path
  ) then
    raise exception 'migrated Storage object is missing';
  end if;

  if exists (
    select 1 from public.transactions
    where public.normalize_receipt_image_path(image_url) = v_job.old_path
  ) or exists (
    select 1 from public.income_records
    where public.normalize_receipt_image_path(image_url) = v_job.old_path
  ) or exists (
    select 1 from public.data_records
    where public.normalize_receipt_image_path(source_image_path) = v_job.old_path
  ) or exists (
    select 1 from public.staging_records
    where public.normalize_receipt_image_path(image_path) = v_job.old_path
  ) or exists (
    select 1 from public.ai_recognition_logs
    where public.normalize_receipt_image_path(image_url) = v_job.old_path
  ) then
    raise exception 'legacy image references still exist';
  end if;

  delete from public.receipt_image_owners
  where bucket_name = v_job.bucket_name
    and bucket_path = v_job.old_path
    and user_id = v_job.user_id;

  update public.receipt_image_migration_jobs
  set status = 'done',
      old_object_deleted_at = coalesce(old_object_deleted_at, now()),
      completed_at = now(),
      last_error = null,
      lease_token = null,
      lease_expires_at = null,
      updated_at = now()
  where id = v_job.id
    and status = 'references_updated'
    and lease_token = p_lease_token
  returning * into v_job;

  if not found then
    raise exception 'receipt image migration job changed before finalization';
  end if;

  return v_job;
end;
$$;

revoke all on function public.finalize_receipt_image_migration(uuid, uuid) from public, anon, authenticated;
grant execute on function public.finalize_receipt_image_migration(uuid, uuid) to service_role;

create or replace function public.prevent_cleanup_during_receipt_image_migration()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.status = 'processing' and exists (
    select 1
    from public.receipt_image_migration_jobs
    where bucket_name = new.bucket_name
      and old_path = public.normalize_receipt_image_path(new.bucket_path)
      and status <> 'done'
  ) then
    raise exception 'receipt image path migration is in progress';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_cleanup_during_receipt_image_migration() from public, anon, authenticated;

drop trigger if exists tr_image_cleanup_migration_guard on public.image_cleanup_queue;
create trigger tr_image_cleanup_migration_guard
  before insert or update of status on public.image_cleanup_queue
  for each row execute function public.prevent_cleanup_during_receipt_image_migration();
