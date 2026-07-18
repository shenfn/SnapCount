alter table public.image_cleanup_queue
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists processed_at timestamptz,
  add column if not exists last_error text;

delete from public.image_cleanup_queue
where user_id is null;

delete from public.image_cleanup_queue older
using public.image_cleanup_queue newer
where older.user_id = newer.user_id
  and older.bucket_path = newer.bucket_path
  and (older.created_at, older.id) < (newer.created_at, newer.id);

alter table public.image_cleanup_queue
  alter column user_id set not null;

alter table public.image_cleanup_queue
  drop constraint if exists image_cleanup_queue_status_check;

alter table public.image_cleanup_queue
  add constraint image_cleanup_queue_status_check
  check (status in ('pending', 'processing', 'done', 'failed'));

create unique index if not exists idx_image_cleanup_queue_user_path
  on public.image_cleanup_queue (user_id, bucket_path);

create index if not exists idx_image_cleanup_queue_work
  on public.image_cleanup_queue (status, attempts, created_at)
  where status in ('pending', 'failed');

create or replace function public.cleanup_expired_images()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  queued_count integer := 0;
begin
  with candidates as (
    select t.user_id, t.image_url as bucket_path
    from public.transactions t
    join public.user_configs c on c.user_id = t.user_id
    where c.is_active = true
      and c.image_retention_days > 0
      and t.image_url is not null
      and (
        (t.image_url like 'tmp/%' and t.created_at < now() - interval '1 hour')
        or
        (t.image_url not like 'tmp/%' and t.created_at < now() - make_interval(days => c.image_retention_days))
      )

    union

    select i.user_id, i.image_url
    from public.income_records i
    join public.user_configs c on c.user_id = i.user_id
    where c.is_active = true
      and c.image_retention_days > 0
      and i.image_url is not null
      and (
        (i.image_url like 'tmp/%' and i.created_at < now() - interval '1 hour')
        or
        (i.image_url not like 'tmp/%' and i.created_at < now() - make_interval(days => c.image_retention_days))
      )

    union

    select d.user_id, d.source_image_path
    from public.data_records d
    join public.user_configs c on c.user_id = d.user_id
    where c.is_active = true
      and c.image_retention_days > 0
      and d.source_image_path is not null
      and (
        (d.source_image_path like 'tmp/%' and d.created_at < now() - interval '1 hour')
        or
        (d.source_image_path not like 'tmp/%' and d.created_at < now() - make_interval(days => c.image_retention_days))
      )

    union

    select s.user_id, s.image_path
    from public.staging_records s
    join public.user_configs c on c.user_id = s.user_id
    where c.is_active = true
      and c.image_retention_days > 0
      and s.image_path is not null
      and (
        (s.image_path like 'tmp/%' and s.created_at < now() - interval '1 hour')
        or
        (s.image_path not like 'tmp/%' and s.created_at < now() - make_interval(days => c.image_retention_days))
      )

    union

    select l.user_id, l.image_url
    from public.ai_recognition_logs l
    join public.user_configs c on c.user_id = l.user_id
    where c.is_active = true
      and c.image_retention_days > 0
      and l.image_url is not null
      and (
        (l.image_url like 'tmp/%' and l.created_at < now() - interval '1 hour')
        or
        (l.image_url not like 'tmp/%' and l.created_at < now() - make_interval(days => c.image_retention_days))
      )
  )
  insert into public.image_cleanup_queue (user_id, bucket_path, status, attempts)
  select user_id, bucket_path, 'pending', 0
  from candidates
  where user_id is not null and bucket_path is not null
  on conflict (user_id, bucket_path) do nothing;

  get diagnostics queued_count = row_count;
  return queued_count;
end;
$$;

revoke execute on function public.cleanup_expired_images() from public, anon, authenticated;
grant execute on function public.cleanup_expired_images() to service_role;

create extension if not exists pg_net with schema extensions;

create or replace function public.invoke_image_cleanup_worker()
returns boolean
language plpgsql
security definer
set search_path = public, extensions, net
as $$
declare
  project_url text;
  service_role_key text;
begin
  if to_regclass('vault.decrypted_secrets') is null then
    raise warning 'image cleanup worker skipped: Supabase Vault is unavailable';
    return false;
  end if;

  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1'
    into project_url
    using 'project_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1'
    into service_role_key
    using 'service_role_key';

  if nullif(project_url, '') is null or nullif(service_role_key, '') is null then
    raise warning 'image cleanup worker skipped: project_url/service_role_key Vault secrets are missing';
    return false;
  end if;

  perform net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/ingest-receipt',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_role_key
    ),
    body := jsonb_build_object('action', 'process_image_cleanup_queue')
  );
  return true;
exception
  when others then
    raise warning 'image cleanup worker invocation failed: %', sqlerrm;
    return false;
end;
$$;

revoke execute on function public.invoke_image_cleanup_worker() from public, anon, authenticated;
grant execute on function public.invoke_image_cleanup_worker() to service_role;

do $$
begin
  perform cron.unschedule('process-image-cleanup-queue');
exception
  when others then
    null;
end
$$;

select cron.schedule(
  'process-image-cleanup-queue',
  '*/15 * * * *',
  $$select public.invoke_image_cleanup_worker();$$
);
