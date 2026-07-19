create or replace function public.is_legacy_storage_path(p_bucket_path text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_bucket_path ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}/[A-Za-z0-9][A-Za-z0-9._-]*$', false);
$$;

create or replace function public.is_supported_image_cleanup_path(
  p_user_id uuid,
  p_bucket_path text
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_user_id is not null
    and p_bucket_path is not null
    and (
      p_bucket_path like p_user_id::text || '/%'
      or p_bucket_path like 'tmp/' || p_user_id::text || '/%'
      or public.is_legacy_storage_path(p_bucket_path)
    );
$$;

revoke all on function public.is_legacy_storage_path(text) from public, anon, authenticated;
revoke all on function public.is_supported_image_cleanup_path(uuid, text) from public, anon, authenticated;
grant execute on function public.is_legacy_storage_path(text) to service_role;
grant execute on function public.is_supported_image_cleanup_path(uuid, text) to service_role;

create or replace function public.run_verified_image_cleanup_scan()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  pending_count integer := 0;
begin
  delete from public.image_cleanup_queue q
  using public.user_configs c
  where q.user_id = c.user_id
    and q.cleanup_reason = 'retention'
    and q.status in ('pending', 'failed')
    and (
      c.is_active is not true
      or (c.keep_source_images is true and c.image_retention_days < 0)
      or not public.is_supported_image_cleanup_path(q.user_id, q.bucket_path)
    );

  perform public.cleanup_expired_images();

  delete from public.image_cleanup_queue q
  where q.cleanup_reason = 'retention'
    and q.status in ('pending', 'failed')
    and not public.is_supported_image_cleanup_path(q.user_id, q.bucket_path);

  select count(*) into pending_count
  from public.image_cleanup_queue
  where status in ('pending', 'failed');

  return pending_count;
end;
$$;

revoke execute on function public.run_verified_image_cleanup_scan() from public, anon, authenticated;
grant execute on function public.run_verified_image_cleanup_scan() to service_role;

create or replace function public.prevent_reference_during_image_cleanup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_path text;
  v_user_id uuid;
begin
  v_path := to_jsonb(new) ->> tg_argv[0];
  v_user_id := nullif(to_jsonb(new) ->> 'user_id', '')::uuid;

  if v_path is null or v_path = '' or v_user_id is null then
    return new;
  end if;

  if exists (
    select 1
    from public.image_cleanup_queue q
    where q.bucket_name = 'receipt-images'
      and q.bucket_path = v_path
      and q.status = 'processing'
  ) then
    raise exception 'image cleanup is in progress for this path';
  end if;

  return new;
end;
$$;

create or replace function public.queue_legacy_image_after_record_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_path text := to_jsonb(old) ->> tg_argv[0];
  v_user_id uuid := nullif(to_jsonb(old) ->> 'user_id', '')::uuid;
begin
  if v_user_id is null
    or not public.is_legacy_storage_path(v_path)
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
