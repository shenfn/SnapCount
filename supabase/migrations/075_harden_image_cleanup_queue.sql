alter table public.image_cleanup_queue
  add column if not exists bucket_name text not null default 'receipt-images',
  add column if not exists storage_deleted_at timestamptz,
  add column if not exists references_cleared_at timestamptz;

alter table public.image_cleanup_queue
  drop constraint if exists image_cleanup_queue_status_check;

alter table public.image_cleanup_queue
  add constraint image_cleanup_queue_status_check
  check (status in ('pending', 'processing', 'done', 'failed', 'dead_letter', 'skipped_external'));

alter table public.image_cleanup_queue
  drop constraint if exists image_cleanup_queue_reason_check;

alter table public.image_cleanup_queue
  add constraint image_cleanup_queue_reason_check
  check (cleanup_reason in (
    'retention',
    'manual_cleanup',
    'immediate',
    'record_delete',
    'account_delete',
    'upload_rollback'
  ));

create table if not exists public.image_cleanup_worker_runs (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'running'
    check (status in ('running', 'succeeded', 'failed')),
  invocation_source text not null default 'scheduled',
  processed integer not null default 0,
  failed integer not null default 0,
  remaining integer not null default 0,
  error_message text
);

create index if not exists idx_image_cleanup_worker_runs_started
  on public.image_cleanup_worker_runs (started_at desc);

alter table public.image_cleanup_worker_runs enable row level security;

drop policy if exists image_cleanup_worker_runs_service_only
  on public.image_cleanup_worker_runs;
create policy image_cleanup_worker_runs_service_only
  on public.image_cleanup_worker_runs
  for all
  using (false)
  with check (false);

revoke all on table public.image_cleanup_worker_runs from public, anon, authenticated;
grant all on table public.image_cleanup_worker_runs to service_role;

create or replace function public.reset_image_cleanup_phase_on_requeue()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'pending' and tg_op = 'INSERT' then
    new.storage_deleted_at := null;
    new.references_cleared_at := null;
    new.deleted_at := null;
  elsif new.status = 'pending' and (old.status is distinct from 'pending' or new.attempts = 0) then
    new.storage_deleted_at := null;
    new.references_cleared_at := null;
    new.deleted_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists tr_image_cleanup_reset_phase on public.image_cleanup_queue;
create trigger tr_image_cleanup_reset_phase
  before insert or update on public.image_cleanup_queue
  for each row execute function public.reset_image_cleanup_phase_on_requeue();

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
    'last_success_at', (select max(completed_at) from public.image_cleanup_worker_runs where status = 'succeeded'),
    'last_failure_at', (select max(completed_at) from public.image_cleanup_worker_runs where status = 'failed'),
    'last_started_at', (select max(started_at) from public.image_cleanup_worker_runs)
  );
$$;

revoke all on function public.get_image_cleanup_health() from public, anon, authenticated;
grant execute on function public.get_image_cleanup_health() to service_role;

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
    where q.user_id = v_user_id
      and q.bucket_name = 'receipt-images'
      and q.bucket_path = v_path
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

create or replace function public.delete_user_account_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
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
  delete from public.accounts where user_id = p_user_id;
  delete from public.data_domains where user_id = p_user_id;
  delete from public.image_cleanup_queue where user_id = p_user_id;
  delete from public.user_configs where user_id = p_user_id;
end;
$$;

revoke execute on function public.delete_user_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_user_account_data(uuid) to service_role;
