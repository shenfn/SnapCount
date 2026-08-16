-- Make the physical archive target explicit without replacing the legacy
-- detected-domain field. The archive wrapper remains the write authority.

alter table public.staging_records
  add column if not exists target_kind text,
  add column if not exists resolved_domain_key text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.staging_records'::regclass
      and conname = 'staging_records_target_kind_check'
  ) then
    alter table public.staging_records
      add constraint staging_records_target_kind_check
      check (target_kind is null or target_kind in ('expense', 'income', 'data'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.staging_records'::regclass
      and conname = 'staging_records_resolved_domain_key_check'
  ) then
    alter table public.staging_records
      add constraint staging_records_resolved_domain_key_check
      check (resolved_domain_key is null or btrim(resolved_domain_key) <> '');
  end if;
end;
$$;

create index if not exists idx_staging_target_kind
  on public.staging_records (user_id, status, target_kind);

comment on column public.staging_records.target_kind is
  'Physical archive target: expense, income, or data. Null means the target is unknown.';

comment on column public.staging_records.resolved_domain_key is
  'Final archive domain. detected_domain_key remains the recognition result.';

-- Conservative historical recovery. A row is backfilled only when the same
-- user/staging/target relationship resolves to exactly one physical table.
with target_matches as (
  select
    staging.id as staging_id,
    staging.user_id,
    'expense'::text as target_kind,
    'expense'::text as resolved_domain_key
  from public.staging_records as staging
  join public.transactions as target
    on target.id = staging.target_record_id
   and target.staging_record_id = staging.id
   and target.user_id = staging.user_id
  where staging.status = 'archived'

  union all

  select
    staging.id,
    staging.user_id,
    'income'::text,
    'income'::text
  from public.staging_records as staging
  join public.income_records as target
    on target.id = staging.target_record_id
   and target.staging_record_id = staging.id
   and target.user_id = staging.user_id
  where staging.status = 'archived'

  union all

  select
    staging.id,
    staging.user_id,
    'data'::text,
    target.domain_key
  from public.staging_records as staging
  join public.data_records as target
    on target.id = staging.target_record_id
   and target.staging_record_id = staging.id
   and target.user_id = staging.user_id
  where staging.status = 'archived'
), unique_matches as (
  select
    staging_id,
    user_id,
    min(target_kind) as target_kind,
    min(resolved_domain_key) as resolved_domain_key,
    count(*) as match_count
  from target_matches
  group by staging_id, user_id
)
update public.staging_records as staging
   set target_kind = matches.target_kind,
       resolved_domain_key = matches.resolved_domain_key,
       updated_at = now()
  from unique_matches as matches
 where staging.id = matches.staging_id
   and staging.user_id = matches.user_id
   and staging.status = 'archived'
   and matches.match_count = 1
   and matches.target_kind is not null
   and matches.resolved_domain_key is not null;

create or replace function public.archive_staging_record(
  p_staging_id uuid,
  p_domain_key text,
  p_amount numeric default null,
  p_title text default null,
  p_platform text default null,
  p_category text default null,
  p_payment_method text default null,
  p_income_category text default null,
  p_record_date date default null,
  p_record_time time default null,
  p_occurred_at timestamptz default null,
  p_summary text default null,
  p_payload jsonb default '{}'::jsonb,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_staging public.staging_records%rowtype;
  v_result jsonb;
  v_target_id uuid;
  v_match_count integer;
  v_actual_kind text;
  v_actual_domain_key text;
  v_idempotent_retry boolean := false;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  if p_staging_id is null or nullif(trim(p_domain_key), '') is null then
    raise exception 'staging id and domain key are required';
  end if;

  select * into v_staging
  from public.staging_records
  where id = p_staging_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'staging record not found or permission denied';
  end if;

  if v_staging.status = 'archived' and v_staging.target_record_id is not null then
    v_target_id := v_staging.target_record_id;
    v_idempotent_retry := true;
  else
    -- The legacy function owns target creation, account effects, feedback and
    -- terminal status. This wrapper adds only explicit target metadata in the
    -- same transaction.
    v_result := public.archive_staging_record_legacy(
      p_staging_id => p_staging_id,
      p_domain_key => p_domain_key,
      p_amount => p_amount,
      p_title => p_title,
      p_platform => p_platform,
      p_category => p_category,
      p_payment_method => p_payment_method,
      p_income_category => p_income_category,
      p_record_date => p_record_date,
      p_record_time => p_record_time,
      p_occurred_at => p_occurred_at,
      p_summary => p_summary,
      p_payload => p_payload,
      p_account_id => p_account_id
    );

    v_target_id := nullif(v_result->>'target_record_id', '')::uuid;
    if v_target_id is null then
      raise exception 'archive did not return a target record';
    end if;
  end if;

  -- Resolve the actual target, never from detected_domain_key or caller input.
  -- A collision across physical tables is intentionally rejected.
  select count(*)::integer, min(target_kind), min(resolved_domain_key)
    into v_match_count, v_actual_kind, v_actual_domain_key
  from (
    select 'expense'::text as target_kind, 'expense'::text as resolved_domain_key
    where exists (
      select 1 from public.transactions as target
      where target.id = v_target_id
        and target.staging_record_id = p_staging_id
        and target.user_id = v_user_id
    )
    union all
    select 'income'::text, 'income'::text
    where exists (
      select 1 from public.income_records as target
      where target.id = v_target_id
        and target.staging_record_id = p_staging_id
        and target.user_id = v_user_id
    )
    union all
    select 'data'::text, target.domain_key
    from public.data_records as target
    where target.id = v_target_id
      and target.staging_record_id = p_staging_id
      and target.user_id = v_user_id
  ) as matches;

  if v_match_count = 0 then
    raise exception 'archived staging target not found';
  end if;
  if v_match_count <> 1 then
    raise exception 'archived staging target is ambiguous';
  end if;
  if v_actual_domain_key <> p_domain_key then
    raise exception 'archived staging record domain mismatch';
  end if;

  update public.staging_records
     set target_kind = v_actual_kind,
         resolved_domain_key = v_actual_domain_key,
         updated_at = now()
   where id = p_staging_id
     and user_id = v_user_id;

  if v_idempotent_retry then
    return jsonb_build_object(
      'target_record_id', v_target_id,
      'target_kind', v_actual_kind,
      'resolved_domain_key', v_actual_domain_key,
      'target_reference', v_actual_kind || '/' || v_target_id::text,
      'idempotent_retry', true
    );
  end if;

  return v_result || jsonb_build_object(
    'target_kind', v_actual_kind,
    'resolved_domain_key', v_actual_domain_key
  );
end;
$$;

revoke all on function public.archive_staging_record(
  uuid, text, numeric, text, text, text, text, text,
  date, time, timestamptz, text, jsonb, uuid
) from public, anon;
grant execute on function public.archive_staging_record(
  uuid, text, numeric, text, text, text, text, text,
  date, time, timestamptz, text, jsonb, uuid
) to authenticated;
