-- Stable, user-safe metadata for the asynchronous account deletion contract.

alter table public.account_deletion_requests
  add column if not exists estimated_completion_at timestamptz,
  add column if not exists support_reference text,
  add column if not exists lease_token uuid,
  add column if not exists lease_expires_at timestamptz;

comment on column public.account_deletion_requests.estimated_completion_at is
  'A non-SLA estimate shown to the user; calculated from server receipt time.';
comment on column public.account_deletion_requests.support_reference is
  'Short opaque reference for support; never contains the user id or email.';

update public.account_deletion_requests
set estimated_completion_at = coalesce(
      estimated_completion_at,
      requested_at + interval '24 hours'
    ),
    support_reference = coalesce(
      support_reference,
      'DEL-' || upper(substr(md5(id::text), 1, 12))
    )
where estimated_completion_at is null
   or support_reference is null;

alter table public.account_deletion_requests
  alter column estimated_completion_at set not null,
  alter column support_reference set not null;

create unique index if not exists uq_account_deletion_support_reference
  on public.account_deletion_requests (support_reference)
  where support_reference is not null;

create or replace function public.set_account_deletion_metadata()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.estimated_completion_at is null then
    new.estimated_completion_at := coalesce(new.requested_at, statement_timestamp()) + interval '24 hours';
  end if;
  if new.support_reference is null then
    new.support_reference := 'DEL-' || upper(substr(md5(new.id::text), 1, 12));
  end if;
  return new;
end;
$$;

revoke all on function public.set_account_deletion_metadata() from public, anon, authenticated, service_role;

drop trigger if exists tr_set_account_deletion_metadata on public.account_deletion_requests;
create trigger tr_set_account_deletion_metadata
  before insert on public.account_deletion_requests
  for each row execute function public.set_account_deletion_metadata();

create index if not exists idx_account_deletion_requests_lease
  on public.account_deletion_requests (lease_expires_at)
  where status in ('requested', 'cleaning', 'deleting', 'failed');

create or replace function public.claim_account_deletion_request()
returns table (
  id uuid,
  user_id uuid,
  status text,
  requested_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz,
  estimated_completion_at timestamptz,
  support_reference text,
  total_images integer,
  deleted_images integer,
  remaining_images integer,
  skipped_external integer,
  last_error text,
  lease_token uuid,
  lease_expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  return query
  with candidate as (
    select request.id
    from public.account_deletion_requests request
    where request.status in ('requested', 'cleaning', 'deleting', 'failed')
      and (request.next_retry_at is null or request.next_retry_at <= statement_timestamp())
      and (request.lease_expires_at is null or request.lease_expires_at <= statement_timestamp())
    order by request.requested_at asc
    for update skip locked
    limit 1
  ), claimed as (
    update public.account_deletion_requests request
    set lease_token = gen_random_uuid(),
        lease_expires_at = statement_timestamp() + interval '10 minutes',
        updated_at = statement_timestamp()
    from candidate
    where request.id = candidate.id
    returning request.*
  )
  select claimed.id,
         claimed.user_id,
         claimed.status,
         claimed.requested_at,
         claimed.updated_at,
         claimed.completed_at,
         claimed.estimated_completion_at,
         claimed.support_reference,
         claimed.total_images,
         claimed.deleted_images,
         claimed.remaining_images,
         claimed.skipped_external,
         claimed.last_error,
         claimed.lease_token,
         claimed.lease_expires_at
  from claimed;
end;
$$;

revoke all on function public.claim_account_deletion_request()
  from public, anon, authenticated;
grant execute on function public.claim_account_deletion_request() to service_role;

create or replace function public.purge_completed_account_deletion_receipts()
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  deleted_count bigint;
begin
  delete from public.account_deletion_requests
  where status = 'completed'
    and completed_at < statement_timestamp() - interval '30 days';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.purge_completed_account_deletion_receipts()
  from public, anon, authenticated;
grant execute on function public.purge_completed_account_deletion_receipts() to service_role;

do $block$
begin
  if to_regnamespace('cron') is not null then
    execute 'select cron.unschedule(jobid) from cron.job where jobname = ''purge-completed-account-deletion-receipts''';
    execute 'select cron.schedule(''purge-completed-account-deletion-receipts'', ''17 19 * * *'', ''select public.purge_completed_account_deletion_receipts();'')';
  end if;
end;
$block$;
