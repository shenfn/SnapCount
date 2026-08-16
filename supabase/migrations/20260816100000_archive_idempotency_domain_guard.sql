-- Preserve the already deployed archive implementation and add an explicit
-- target-domain check before accepting an idempotent retry.

do $$
begin
  if to_regprocedure(
    'public.archive_staging_record(uuid,text,numeric,text,text,text,text,text,date,time without time zone,timestamp with time zone,text,jsonb,uuid)'
  ) is not null
  and to_regprocedure(
    'public.archive_staging_record_legacy(uuid,text,numeric,text,text,text,text,text,date,time without time zone,timestamp with time zone,text,jsonb,uuid)'
  ) is null then
    alter function public.archive_staging_record(
      uuid, text, numeric, text, text, text, text, text,
      date, time, timestamptz, text, jsonb, uuid
    ) rename to archive_staging_record_legacy;
  end if;
end;
$$;

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
  v_existing_domain_key text;
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
    if exists (
      select 1 from public.transactions
      where id = v_staging.target_record_id
        and user_id = v_user_id
        and staging_record_id = v_staging.id
    ) then
      if p_domain_key <> 'expense' then
        raise exception 'archived staging record domain mismatch';
      end if;
      return jsonb_build_object(
        'target_record_id', v_staging.target_record_id,
        'target_reference', 'expense/' || v_staging.target_record_id::text,
        'idempotent_retry', true
      );
    end if;

    if exists (
      select 1 from public.income_records
      where id = v_staging.target_record_id
        and user_id = v_user_id
        and staging_record_id = v_staging.id
    ) then
      if p_domain_key <> 'income' then
        raise exception 'archived staging record domain mismatch';
      end if;
      return jsonb_build_object(
        'target_record_id', v_staging.target_record_id,
        'target_reference', 'income/' || v_staging.target_record_id::text,
        'idempotent_retry', true
      );
    end if;

    select domain_key into v_existing_domain_key
    from public.data_records
    where id = v_staging.target_record_id
      and user_id = v_user_id
      and staging_record_id = v_staging.id;

    if found then
      if v_existing_domain_key <> p_domain_key then
        raise exception 'archived staging record domain mismatch';
      end if;
      return jsonb_build_object(
        'target_record_id', v_staging.target_record_id,
        'target_reference', 'data/' || v_staging.target_record_id::text,
        'idempotent_retry', true
      );
    end if;

    raise exception 'archived staging target not found';
  end if;

  return public.archive_staging_record_legacy(
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
end;
$$;

revoke all on function public.archive_staging_record_legacy(
  uuid, text, numeric, text, text, text, text, text,
  date, time, timestamptz, text, jsonb, uuid
) from public, anon, authenticated;
revoke all on function public.archive_staging_record(
  uuid, text, numeric, text, text, text, text, text,
  date, time, timestamptz, text, jsonb, uuid
) from public, anon;
grant execute on function public.archive_staging_record(
  uuid, text, numeric, text, text, text, text, text,
  date, time, timestamptz, text, jsonb, uuid
) to authenticated;
