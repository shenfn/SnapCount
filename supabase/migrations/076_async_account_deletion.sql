create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique,
  status text not null default 'requested'
    check (status in ('requested', 'cleaning', 'deleting', 'completed', 'failed')),
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  attempts integer not null default 0,
  next_retry_at timestamptz,
  total_images integer not null default 0,
  deleted_images integer not null default 0,
  remaining_images integer not null default 0,
  skipped_external integer not null default 0,
  last_error text
);

create index if not exists idx_account_deletion_requests_work
  on public.account_deletion_requests (status, next_retry_at, requested_at)
  where status in ('requested', 'cleaning', 'failed');

alter table public.account_deletion_requests enable row level security;

drop policy if exists account_deletion_requests_service_only
  on public.account_deletion_requests;
create policy account_deletion_requests_service_only
  on public.account_deletion_requests
  for all
  using (false)
  with check (false);

revoke all on table public.account_deletion_requests from public, anon, authenticated;
grant all on table public.account_deletion_requests to service_role;

create or replace function public.get_image_cleanup_health()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'pending', (select count(*) from public.image_cleanup_queue where status in ('pending', 'failed', 'processing')),
    'dead_letter', (select count(*) from public.image_cleanup_queue where status = 'dead_letter'),
    'account_deletions_pending', (
      select count(*) from public.account_deletion_requests
      where status in ('requested', 'cleaning', 'deleting', 'failed')
    ),
    'last_success_at', (select max(completed_at) from public.image_cleanup_worker_runs where status = 'succeeded'),
    'last_failure_at', (select max(completed_at) from public.image_cleanup_worker_runs where status = 'failed'),
    'last_started_at', (select max(started_at) from public.image_cleanup_worker_runs)
  );
$$;

revoke all on function public.get_image_cleanup_health() from public, anon, authenticated;
grant execute on function public.get_image_cleanup_health() to service_role;

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
  '*/5 * * * *',
  $$select public.invoke_image_cleanup_worker();$$
);
