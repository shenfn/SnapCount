create or replace function public.confirm_staging_repayment(
  p_staging_id uuid,
  p_cycle_id uuid,
  p_paid_amount numeric,
  p_paid_at timestamptz default now(),
  p_debit_account_id uuid default null,
  p_status text default 'paid',
  p_note text default null
)
returns public.account_repayment_cycles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staging public.staging_records%rowtype;
  v_cycle public.account_repayment_cycles%rowtype;
begin
  if auth.uid() is null then
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

  select *
    into v_staging
  from public.staging_records
  where id = p_staging_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'staging record not found or permission denied';
  end if;

  if v_staging.status = 'archived' then
    if v_staging.target_record_id = p_cycle_id
       and v_staging.resolved_action = 'liability_repayment_confirmed' then
      select *
        into v_cycle
      from public.account_repayment_cycles
      where id = p_cycle_id
        and user_id = auth.uid();

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

  select *
    into v_cycle
  from public.set_repayment_cycle_paid_amount(
    p_cycle_id,
    round(p_paid_amount::numeric, 2),
    coalesce(p_paid_at, now()),
    p_debit_account_id,
    coalesce(p_status, 'paid'),
    coalesce(p_note, '根据还款截图确认已还清')
  );

  update public.liability_payments
     set source = 'screenshot',
         updated_at = now()
   where user_id = auth.uid()
     and statement_id = v_cycle.id
     and status <> 'voided';

  update public.account_repayment_cycles
     set source = 'screenshot',
         updated_at = now()
   where id = v_cycle.id
     and user_id = auth.uid()
   returning * into v_cycle;

  update public.staging_records
     set status = 'archived',
         resolved_action = 'liability_repayment_confirmed',
         resolved_at = now(),
         target_record_id = v_cycle.id,
         updated_at = now()
   where id = v_staging.id
     and user_id = auth.uid();

  return v_cycle;
end;
$$;

revoke all on function public.confirm_staging_repayment(uuid, uuid, numeric, timestamptz, uuid, text, text) from public;
grant execute on function public.confirm_staging_repayment(uuid, uuid, numeric, timestamptz, uuid, text, text) to authenticated;
