do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'project_url'
  ) or not exists (
    select 1 from vault.secrets where name = 'image_cleanup_worker_token'
  ) then
    raise exception 'image cleanup Vault secrets are missing';
  end if;
end
$$;

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
  where q.status in ('pending', 'failed')
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

create or replace function public.invoke_image_cleanup_worker()
returns boolean
language plpgsql
security definer
set search_path = public, extensions, net
as $$
declare
  project_url text;
  worker_token text;
begin
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1'
    into project_url
    using 'project_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1'
    into worker_token
    using 'image_cleanup_worker_token';

  if nullif(project_url, '') is null or nullif(worker_token, '') is null then
    raise warning 'image cleanup worker skipped: project URL or worker token is missing';
    return false;
  end if;

  perform net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/ingest-receipt',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Image-Cleanup-Token', worker_token
    ),
    body := jsonb_build_object('action', 'process_image_cleanup_queue'),
    timeout_milliseconds := 120000
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
  perform cron.unschedule('cleanup-expired-images');
exception
  when others then
    null;
end
$$;

do $$
begin
  perform cron.unschedule('process-image-cleanup-queue');
exception
  when others then
    null;
end
$$;

select cron.schedule(
  'cleanup-expired-images',
  '5 * * * *',
  $$select public.run_verified_image_cleanup_scan();$$
);

select cron.schedule(
  'process-image-cleanup-queue',
  '*/15 * * * *',
  $$select public.invoke_image_cleanup_worker();$$
);

comment on function public.run_verified_image_cleanup_scan() is
  'Queues expired images only after pruning paths that cannot be proven to belong to their user.';

comment on function public.cleanup_expired_images() is
  'Builds retention candidates. Production cron calls run_verified_image_cleanup_scan for ownership pruning.';

comment on function public.invoke_image_cleanup_worker() is
  'Invokes the user-scoped Edge Function worker every 15 minutes using Vault credentials.';
