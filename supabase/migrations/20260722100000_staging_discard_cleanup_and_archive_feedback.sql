alter table public.image_cleanup_queue
  drop constraint if exists image_cleanup_queue_status_check;

alter table public.image_cleanup_queue
  add constraint image_cleanup_queue_status_check
  check (status in ('pending', 'processing', 'done', 'failed', 'dead_letter', 'skipped_external', 'skipped_shared'));

create or replace function public.discard_staging_record(
  p_staging_id uuid,
  p_reason text default 'user_discarded'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_staging public.staging_records%rowtype;
  v_raw_path text;
  v_bucket_path text;
  v_existing_id uuid;
  v_existing_status text;
  v_storage_deleted_at timestamptz;
  v_cleanup_status text := 'no_image';
  v_reason text := left(coalesce(nullif(btrim(p_reason), ''), 'user_discarded'), 120);
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  select *
    into v_staging
  from public.staging_records
  where id = p_staging_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'staging record not found or permission denied';
  end if;

  if v_staging.status = 'archived' then
    raise exception 'archived staging records cannot be discarded';
  end if;

  v_raw_path := nullif(btrim(v_staging.image_path), '');
  if v_raw_path is not null
    and v_raw_path !~* '^(https?://|data:)'
  then
    v_bucket_path := public.normalize_receipt_image_path(v_raw_path);
  elsif v_raw_path is not null
    and v_raw_path ~* '^https?://'
  then
    v_bucket_path := public.normalize_receipt_image_path(v_raw_path);
    if v_bucket_path is not null and v_bucket_path ~* '^https?://' then
      v_bucket_path := null;
    end if;
  end if;

  if v_raw_path is not null and v_bucket_path is null then
    v_cleanup_status := 'skipped_external';
  end if;

  if v_bucket_path is not null then
    if not (
      v_bucket_path like v_user_id::text || '/%'
      or v_bucket_path like 'tmp/' || v_user_id::text || '/%'
      or exists (
        select 1
        from public.receipt_image_owners
        where bucket_name = 'receipt-images'
          and bucket_path = v_bucket_path
          and user_id = v_user_id
      )
    ) then
      raise exception 'receipt image path ownership cannot be verified';
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
      v_bucket_path,
      'pending',
      0,
      'record_delete',
      'staging_records',
      v_staging.id,
      null,
      null,
      null,
      now(),
      null,
      null,
      null,
      now()
    )
    on conflict (user_id, bucket_path) do nothing;

    select id, status, storage_deleted_at
      into v_existing_id, v_existing_status, v_storage_deleted_at
    from public.image_cleanup_queue
    where user_id = v_user_id
      and bucket_path = v_bucket_path
    for update;

    if v_existing_status = 'done' and v_storage_deleted_at is not null then
      v_cleanup_status := 'already_deleted';
      v_bucket_path := null;
    elsif v_existing_status = 'processing' then
      raise exception 'image cleanup is already in progress; retry shortly';
    else
      update public.image_cleanup_queue
         set status = 'pending',
             attempts = 0,
             cleanup_reason = 'record_delete',
             source_table = 'staging_records',
             source_id = v_staging.id,
             last_error = null,
             processed_at = null,
             last_attempt_at = null,
             next_retry_at = now(),
             deleted_at = null,
             storage_deleted_at = null,
             references_cleared_at = null,
             updated_at = now()
       where id = v_existing_id;
      v_cleanup_status := 'pending';
    end if;
  end if;

  update public.staging_records
     set status = 'discarded',
         discard_reason = v_reason,
         resolved_action = 'discarded',
         resolved_at = now(),
         image_path = case when v_bucket_path is null then null else image_path end,
         updated_at = now()
   where id = v_staging.id
     and user_id = v_user_id;

  return jsonb_build_object(
    'staging_id', v_staging.id,
    'status', 'discarded',
    'cleanup_status', v_cleanup_status,
    'cleanup_queued', v_cleanup_status in ('pending', 'processing'),
    'bucket_path', v_bucket_path
  );
end;
$$;

revoke all on function public.discard_staging_record(uuid, text) from public, anon, authenticated;
grant execute on function public.discard_staging_record(uuid, text) to authenticated;

create or replace function public.sync_staging_archive_metadata()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_feedback jsonb;
  v_companion text;
  v_updated integer := 0;
begin
  if new.status <> 'archived'
    or new.target_record_id is null
    or new.user_id is null
  then
    return new;
  end if;

  v_feedback := case
    when jsonb_typeof(coalesce(new.extracted_json, '{}'::jsonb)->'ai_feedback') = 'object'
      then coalesce(new.extracted_json, '{}'::jsonb)->'ai_feedback'
    when jsonb_typeof(coalesce(new.extracted_json, '{}'::jsonb)->'payload_jsonb'->'ai_feedback') = 'object'
      then coalesce(new.extracted_json, '{}'::jsonb)->'payload_jsonb'->'ai_feedback'
    else null
  end;
  if v_feedback = '{}'::jsonb then
    v_feedback := null;
  end if;

  v_companion := coalesce(
    nullif(btrim(new.companion_message), ''),
    nullif(btrim(coalesce(new.extracted_json, '{}'::jsonb)->>'companion_message'), ''),
    nullif(btrim(coalesce(new.extracted_json, '{}'::jsonb)->'payload_jsonb'->>'companion_message'), '')
  );

  update public.transactions
     set ai_feedback = coalesce(ai_feedback, v_feedback),
         companion_message = coalesce(companion_message, v_companion),
         staging_record_id = coalesce(staging_record_id, new.id)
   where id = new.target_record_id
     and user_id = new.user_id;
  get diagnostics v_updated = row_count;
  if v_updated > 0 then
    return new;
  end if;

  update public.income_records
     set ai_feedback = coalesce(ai_feedback, v_feedback),
         companion_message = coalesce(companion_message, v_companion),
         staging_record_id = coalesce(staging_record_id, new.id)
   where id = new.target_record_id
     and user_id = new.user_id;
  get diagnostics v_updated = row_count;
  if v_updated > 0 then
    return new;
  end if;

  update public.data_records
     set payload_jsonb = coalesce(payload_jsonb, '{}'::jsonb)
       || case
         when v_feedback is null or coalesce(payload_jsonb, '{}'::jsonb)->'ai_feedback' is not null
           then '{}'::jsonb
         else jsonb_build_object('ai_feedback', v_feedback)
       end
       || case
         when v_companion is null or nullif(btrim(coalesce(payload_jsonb, '{}'::jsonb)->>'companion_message'), '') is not null
           then '{}'::jsonb
         else jsonb_build_object('companion_message', v_companion)
       end,
          staging_record_id = coalesce(staging_record_id, new.id)
   where id = new.target_record_id
     and user_id = new.user_id;

  return new;
end;
$$;

revoke all on function public.sync_staging_archive_metadata() from public, anon, authenticated;

drop trigger if exists tr_sync_staging_archive_metadata on public.staging_records;
create trigger tr_sync_staging_archive_metadata
  after update of status, target_record_id, extracted_json, companion_message
  on public.staging_records
  for each row execute function public.sync_staging_archive_metadata();

update public.staging_records
set extracted_json = extracted_json
where status = 'archived'
  and target_record_id is not null;

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
