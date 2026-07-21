alter table public.image_cleanup_queue
  add column if not exists cleanup_reason text not null default 'retention',
  add column if not exists source_table text,
  add column if not exists source_id uuid,
  add column if not exists last_attempt_at timestamptz,
  add column if not exists next_retry_at timestamptz,
  add column if not exists deleted_at timestamptz;

alter table public.image_cleanup_queue
  drop constraint if exists image_cleanup_queue_reason_check;

alter table public.image_cleanup_queue
  add constraint image_cleanup_queue_reason_check
  check (cleanup_reason in ('retention', 'manual_cleanup', 'immediate', 'record_delete', 'account_delete'));

drop index if exists public.idx_image_cleanup_queue_work;

create index idx_image_cleanup_queue_work
  on public.image_cleanup_queue (status, next_retry_at, attempts, created_at)
  where status in ('pending', 'failed');

create or replace function public.is_business_image_path_referenced(
  p_user_id uuid,
  p_bucket_path text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1 from public.transactions
      where user_id = p_user_id and image_url = p_bucket_path
    )
    or exists (
      select 1 from public.income_records
      where user_id = p_user_id and image_url = p_bucket_path
    )
    or exists (
      select 1 from public.data_records
      where user_id = p_user_id and source_image_path = p_bucket_path
    )
    or exists (
      select 1 from public.staging_records
      where user_id = p_user_id and image_path = p_bucket_path
    );
$$;

revoke all on function public.is_business_image_path_referenced(uuid, text) from public, anon, authenticated;
grant execute on function public.is_business_image_path_referenced(uuid, text) to service_role;

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
      or not (
        q.bucket_path like q.user_id::text || '/%'
        or q.bucket_path like 'tmp/' || q.user_id::text || '/%'
      )
    );

  perform public.cleanup_expired_images();

  delete from public.image_cleanup_queue q
  where q.cleanup_reason = 'retention'
    and q.status in ('pending', 'failed')
    and not (
      q.bucket_path like q.user_id::text || '/%'
      or q.bucket_path like 'tmp/' || q.user_id::text || '/%'
    );

  select count(*) into pending_count
  from public.image_cleanup_queue
  where status in ('pending', 'failed');

  return pending_count;
end;
$$;

revoke execute on function public.run_verified_image_cleanup_scan() from public, anon, authenticated;
grant execute on function public.run_verified_image_cleanup_scan() to service_role;

create or replace function public.delete_record_with_cleanup(
  p_kind text,
  p_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_bucket_path text;
  v_source_table text;
  v_reference_kind text;
  v_cleanup_queued boolean := false;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  if p_id is null then
    raise exception 'record id is required';
  end if;

  if v_kind in ('expense', 'transaction', 'bill') then
    v_source_table := 'transactions';
    v_reference_kind := 'expense';

    select image_url into v_bucket_path
    from public.transactions
    where id = p_id and user_id = v_user_id
    for update;

    if not found then
      raise exception 'transaction not found or permission denied';
    end if;

    perform public.void_account_entries_for_record('transactions', p_id, 'transaction_deleted');
    delete from public.transactions where id = p_id and user_id = v_user_id;
  elsif v_kind in ('income', 'income_record') then
    v_source_table := 'income_records';
    v_reference_kind := 'income';

    select image_url into v_bucket_path
    from public.income_records
    where id = p_id and user_id = v_user_id
    for update;

    if not found then
      raise exception 'income record not found or permission denied';
    end if;

    perform public.void_account_entries_for_record('income_records', p_id, 'income_deleted');
    delete from public.income_records where id = p_id and user_id = v_user_id;
  elsif v_kind in ('data', 'universal', 'data_record') then
    v_source_table := 'data_records';
    v_reference_kind := 'data';

    select source_image_path into v_bucket_path
    from public.data_records
    where id = p_id and user_id = v_user_id
    for update;

    if not found then
      raise exception 'data record not found or permission denied';
    end if;

    delete from public.data_records where id = p_id and user_id = v_user_id;
  else
    raise exception 'unsupported record kind: %', v_kind;
  end if;

  if v_bucket_path is not null
    and v_bucket_path <> ''
    and v_bucket_path !~* '^https?://'
    and (
      v_bucket_path like v_user_id::text || '/%'
      or v_bucket_path like 'tmp/' || v_user_id::text || '/%'
    )
    and not public.is_business_image_path_referenced(v_user_id, v_bucket_path)
  then
    insert into public.image_cleanup_queue (
      user_id,
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
      updated_at
    ) values (
      v_user_id,
      v_bucket_path,
      'pending',
      0,
      'record_delete',
      v_source_table,
      p_id,
      null,
      null,
      null,
      now(),
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
        updated_at = now();

    v_cleanup_queued := true;
  end if;

  return jsonb_build_object(
    'reference', v_reference_kind || '/' || p_id::text,
    'image_path', v_bucket_path,
    'cleanup_queued', v_cleanup_queued
  );
end;
$$;

revoke all on function public.delete_record_with_cleanup(text, uuid) from public, anon;
grant execute on function public.delete_record_with_cleanup(text, uuid) to authenticated;
