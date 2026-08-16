alter table public.staging_records
  drop constraint if exists staging_records_target_kind_check;

alter table public.staging_records
  add constraint staging_records_target_kind_check
  check (target_kind is null or target_kind in ('expense', 'income', 'data', 'repayment_cycle'));

update public.staging_records as staging
   set target_kind = 'repayment_cycle',
       resolved_domain_key = 'wallet',
       updated_at = now()
 where staging.status = 'archived'
   and staging.resolved_action = 'liability_repayment_confirmed'
   and staging.target_record_id is not null
   and (staging.target_kind is null or staging.resolved_domain_key is null)
   and exists (
     select 1
     from public.account_repayment_cycles as cycle
     where cycle.id = staging.target_record_id
       and cycle.user_id = staging.user_id
   );

create or replace function public.confirm_staging_repayment(
  p_staging_id uuid,
  p_cycle_id uuid,
  p_paid_amount numeric,
  p_paid_at timestamptz default now(),
  p_debit_account_id uuid default null,
  p_status text default null,
  p_note text default null
)
returns public.account_repayment_cycles
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_staging public.staging_records%rowtype;
  v_cycle public.account_repayment_cycles%rowtype;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;
  if p_staging_id is null then
    raise exception 'staging_id is required';
  end if;
  if p_cycle_id is null then
    raise exception 'cycle_id is required';
  end if;
  if p_paid_amount is null or p_paid_amount <= 0 then
    raise exception 'paid_amount must be greater than 0';
  end if;

  select * into v_staging
  from public.staging_records
  where id = p_staging_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'staging record not found or permission denied';
  end if;

  if v_staging.status = 'archived' then
    if v_staging.target_record_id = p_cycle_id
       and v_staging.resolved_action = 'liability_repayment_confirmed' then
      select * into v_cycle
      from public.account_repayment_cycles
      where id = p_cycle_id
        and user_id = v_user_id;
      if not found then
        raise exception 'repayment cycle not found or permission denied';
      end if;
      return v_cycle;
    end if;
    raise exception 'staging record has already been archived';
  end if;

  if v_staging.status = 'discarded' then
    raise exception 'discarded staging record cannot confirm repayment';
  end if;

  select * into v_cycle
  from public.set_repayment_cycle_paid_amount(
    p_cycle_id => p_cycle_id,
    p_paid_amount => round(p_paid_amount::numeric, 2),
    p_paid_at => coalesce(p_paid_at, now()),
    p_debit_account_id => p_debit_account_id,
    p_status => null,
    p_note => coalesce(p_note, '根据还款截图确认')
  );

  update public.liability_payments
     set source = 'screenshot',
         updated_at = now()
   where user_id = v_user_id
     and statement_id = v_cycle.id
     and status <> 'voided';

  update public.account_repayment_cycles
     set source = 'screenshot',
         updated_at = now()
   where id = v_cycle.id
     and user_id = v_user_id
   returning * into v_cycle;

  update public.staging_records
     set status = 'archived',
         resolved_action = 'liability_repayment_confirmed',
         resolved_at = now(),
         target_record_id = v_cycle.id,
         target_kind = 'repayment_cycle',
         resolved_domain_key = 'wallet',
         updated_at = now()
   where id = v_staging.id
     and user_id = v_user_id;

  return v_cycle;
end;
$$;

revoke all on function public.confirm_staging_repayment(uuid, uuid, numeric, timestamptz, uuid, text, text) from public, anon;
grant execute on function public.confirm_staging_repayment(uuid, uuid, numeric, timestamptz, uuid, text, text) to authenticated;
