-- ════════════════════════════════════════════════════════════════════
-- 065: 修复 cleanup_expired_images 函数中 transactions/income_records 字段名
-- bug: 064 中使用了 image_path，实际字段名是 image_url
-- ════════════════════════════════════════════════════════════════════

create or replace function public.cleanup_expired_images()
returns integer as $$
declare
  cleaned_count integer := 0;
  rec record;
  cutoff timestamptz;
begin
  for rec in
    select user_id, image_retention_days
    from public.user_configs
    where image_retention_days > 0
      and is_active = true
  loop
    cutoff := now() - (rec.image_retention_days || ' days')::interval;

    -- transactions (字段名: image_url)
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_url, user_id from public.transactions
    where user_id = rec.user_id
      and image_url is not null
      and image_url not like 'tmp/%'
      and created_at < cutoff
      and image_url not in (
        select bucket_path from public.image_cleanup_queue
        where user_id = rec.user_id and status in ('pending', 'done')
      );

    update public.transactions set image_url = null
    where user_id = rec.user_id
      and image_url is not null
      and created_at < cutoff;

    -- income_records (字段名: image_url)
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_url, user_id from public.income_records
    where user_id = rec.user_id
      and image_url is not null
      and image_url not like 'tmp/%'
      and created_at < cutoff
      and image_url not in (
        select bucket_path from public.image_cleanup_queue
        where user_id = rec.user_id and status in ('pending', 'done')
      );

    update public.income_records set image_url = null
    where user_id = rec.user_id
      and image_url is not null
      and created_at < cutoff;

    -- data_records (字段名: source_image_path)
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select source_image_path, user_id from public.data_records
    where user_id = rec.user_id
      and source_image_path is not null
      and source_image_path not like 'tmp/%'
      and created_at < cutoff
      and source_image_path not in (
        select bucket_path from public.image_cleanup_queue
        where user_id = rec.user_id and status in ('pending', 'done')
      );

    update public.data_records set source_image_path = null
    where user_id = rec.user_id
      and source_image_path is not null
      and created_at < cutoff;

    -- staging_records (字段名: image_path)
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_path, user_id from public.staging_records
    where user_id = rec.user_id
      and image_path is not null
      and image_path not like 'tmp/%'
      and created_at < cutoff
      and image_path not in (
        select bucket_path from public.image_cleanup_queue
        where user_id = rec.user_id and status in ('pending', 'done')
      );

    update public.staging_records set image_path = null
    where user_id = rec.user_id
      and image_path is not null
      and created_at < cutoff;

    -- ai_recognition_logs (字段名: image_url)
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_url, user_id from public.ai_recognition_logs
    where user_id = rec.user_id
      and image_url is not null
      and image_url not like 'tmp/%'
      and created_at < cutoff
      and image_url not in (
        select bucket_path from public.image_cleanup_queue
        where user_id = rec.user_id and status in ('pending', 'done')
      );

    update public.ai_recognition_logs set image_url = null
    where user_id = rec.user_id
      and image_url is not null
      and created_at < cutoff;

    -- tmp/ 前缀的临时图片
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_url, user_id from public.transactions
    where user_id = rec.user_id
      and image_url like 'tmp/%'
      and created_at < now() - interval '1 hour'
    on conflict do nothing;

    update public.transactions set image_url = null
    where user_id = rec.user_id
      and image_url like 'tmp/%'
      and created_at < now() - interval '1 hour';

    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_path, user_id from public.staging_records
    where user_id = rec.user_id
      and image_path like 'tmp/%'
      and created_at < now() - interval '1 hour'
    on conflict do nothing;

    update public.staging_records set image_path = null
    where user_id = rec.user_id
      and image_path like 'tmp/%'
      and created_at < now() - interval '1 hour';

  end loop;

  select count(*) into cleaned_count from public.image_cleanup_queue where status = 'pending';
  return cleaned_count;
end;
$$ language plpgsql security definer
set search_path = public;

revoke execute on function public.cleanup_expired_images() from anon;
revoke execute on function public.cleanup_expired_images() from authenticated;
