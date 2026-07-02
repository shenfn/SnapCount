-- ════════════════════════════════════════════════════════════════════
-- 064: 隐私保护与数据留存策略
-- 目的：
--   1. 新增 prompt_optimization_enabled 开关（默认关闭）
--   2. 新增 image_retention_days 图片留存期限（默认永久 -1）
--   3. 为长期使用账号设置全部开启 + 永久保留
--   4. 创建 pg_cron 定时任务清理过期图片
-- ════════════════════════════════════════════════════════════════════

-- 1. 新增隐私配置字段
alter table public.user_configs
  add column if not exists prompt_optimization_enabled
    boolean not null default false,
  add column if not exists image_retention_days
    integer not null default -1;

comment on column public.user_configs.prompt_optimization_enabled is
  '是否允许将模型原始输出用于 Prompt 优化分析（默认关闭，保护用户隐私）';
comment on column public.user_configs.image_retention_days is
  '截图原图留存天数：-1=永久, 7=7天, 30=30天';

-- 2. 为长期使用账号（test2@test.com）设置全部开启 + 永久保留
update public.user_configs
  set ai_logs_enabled = true,
      prompt_optimization_enabled = true,
      keep_source_images = true,
      image_retention_days = -1,
      updated_at = now()
  where user_id = 'fd5e026e-715c-4341-b60c-49179a0b3a43';

-- 3. 启用 pg_cron 扩展（Supabase 默认已安装，此处确保启用）
create extension if not exists pg_cron;

-- 4. 创建图片过期标记清理函数
-- 逻辑：找出 image_retention_days > 0 的用户，将其超过留存期的图片路径
-- 从 transactions/income_records/data_records/staging_records/ai_recognition_logs
-- 中清空 image_url/image_path 引用，并记录到 cleanup_queue 供 Edge Function 删除文件
create table if not exists public.image_cleanup_queue (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  bucket_path text not null,
  user_id     uuid,
  status      text not null default 'pending'
                  check (status in ('pending', 'done', 'failed')),
  attempts    integer not null default 0
);

-- RLS：仅服务端（service_role）可访问，用户不可直接操作
alter table public.image_cleanup_queue enable row level security;
create policy "image_cleanup_queue_service_only" on public.image_cleanup_queue
  for all using (false) with check (false);

create or replace function public.cleanup_expired_images()
returns integer as $$
declare
  cleaned_count integer := 0;
  rec record;
  cutoff timestamptz;
begin
  -- 遍历有留存期限的用户
  for rec in
    select user_id, image_retention_days
    from public.user_configs
    where image_retention_days > 0
      and is_active = true
  loop
    cutoff := now() - (rec.image_retention_days || ' days')::interval;

    -- transactions
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_path, user_id from public.transactions
    where user_id = rec.user_id
      and image_path is not null
      and image_path not like 'tmp/%'
      and created_at < cutoff
      and image_path not in (
        select bucket_path from public.image_cleanup_queue
        where user_id = rec.user_id and status in ('pending', 'done')
      );

    update public.transactions set image_path = null
    where user_id = rec.user_id
      and image_path is not null
      and created_at < cutoff;

    -- income_records
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_path, user_id from public.income_records
    where user_id = rec.user_id
      and image_path is not null
      and image_path not like 'tmp/%'
      and created_at < cutoff
      and image_path not in (
        select bucket_path from public.image_cleanup_queue
        where user_id = rec.user_id and status in ('pending', 'done')
      );

    update public.income_records set image_path = null
    where user_id = rec.user_id
      and image_path is not null
      and created_at < cutoff;

    -- data_records
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

    -- staging_records
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

    -- ai_recognition_logs
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

    -- tmp/ 前缀的临时图片（keep_source_images=false 的用户）
    insert into public.image_cleanup_queue (bucket_path, user_id)
    select image_path, user_id from public.transactions
    where user_id = rec.user_id
      and image_path like 'tmp/%'
      and created_at < now() - interval '1 hour'
    on conflict do nothing;

    update public.transactions set image_path = null
    where user_id = rec.user_id
      and image_path like 'tmp/%'
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

-- 5. 注册 pg_cron 定时任务（每天凌晨 3:00 北京时间 = UTC 19:00 前一天）
--    Supabase pg_cron 使用 UTC 时区
--    用 DO 块包裹 unschedule，避免 job 不存在时抛异常
do $$
begin
  perform cron.unschedule('cleanup-expired-images');
exception
  when others then
    null;
end
$$;

select cron.schedule(
  'cleanup-expired-images',
  '0 19 * * *',
  $$select public.cleanup_expired_images();$$
);
