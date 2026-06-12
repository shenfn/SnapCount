create or replace function public.set_repayment_cycle_paid_amount(
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
set search_path = public
as $$
declare
  v_cycle public.account_repayment_cycles%rowtype;
  v_liability public.accounts%rowtype;
  v_debit public.accounts%rowtype;
  v_payment public.liability_payments%rowtype;
  v_paid numeric(14,2);
  v_statement_amount numeric(14,2);
  v_remaining numeric(14,2);
  v_status text;
  v_debit_account_id uuid;
  v_overpayment numeric(14,2) := 0;
  v_effective_liability_payment numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_cycle_id is null then
    raise exception 'cycle_id is required';
  end if;

  if p_paid_amount is null or p_paid_amount < 0 then
    raise exception 'paid_amount must be greater than or equal to 0';
  end if;

  select *
    into v_cycle
  from public.account_repayment_cycles
  where id = p_cycle_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'repayment cycle not found or permission denied';
  end if;

  v_paid := round(p_paid_amount::numeric, 2);
  v_statement_amount := round(coalesce(v_cycle.statement_amount, 0)::numeric, 2);

  if p_status is not null and p_status not in ('partial_paid', 'minimum_paid', 'carried_over', 'paid', 'ignored') then
    raise exception 'unsupported repayment status: %', p_status;
  end if;

  -- Re-confirming a statement replaces older payment attempts. Void them first so
  -- overpayment is calculated against the restored liability balance.
  update public.liability_payments
     set status = 'voided',
         note = coalesce(note, '') || case when note is null or note = '' then '' else '；' end || '重新确认还款时作废',
         updated_at = now()
   where user_id = auth.uid()
     and statement_id = v_cycle.id
     and status <> 'voided';

  update public.account_entries
     set is_voided = true,
         voided_reason = 'repayment_reconfirmed'
   where user_id = auth.uid()
     and source_table in ('account_repayment_cycles', 'liability_payments')
     and (
       source_id = v_cycle.id
       or source_id in (
         select id
         from public.liability_payments
         where user_id = auth.uid()
           and statement_id = v_cycle.id
       )
     )
     and is_voided = false;

  select *
    into v_liability
  from public.accounts
  where id = v_cycle.account_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'liability account not found or permission denied';
  end if;

  v_debit_account_id := coalesce(p_debit_account_id, v_cycle.auto_debit_account_id, v_liability.auto_debit_account_id);

  if v_debit_account_id is not null then
    select *
      into v_debit
    from public.accounts
    where id = v_debit_account_id
      and user_id = auth.uid()
    for update;

    if not found then
      raise exception 'debit account not found or permission denied';
    end if;
  end if;

  if v_paid > coalesce(v_liability.current_balance, 0) then
    v_overpayment := round(v_paid - coalesce(v_liability.current_balance, 0), 2);
  end if;

  v_effective_liability_payment := greatest(v_paid - v_overpayment, 0);
  v_remaining := greatest(v_statement_amount - least(v_paid, v_statement_amount), 0);

  v_status := coalesce(
    p_status,
    case
      when v_paid <= 0 then 'pending'
      when v_remaining <= 0 then 'paid'
      when v_cycle.min_payment_amount is not null and v_paid >= v_cycle.min_payment_amount then 'minimum_paid'
      else 'partial_paid'
    end
  );

  if v_status = 'paid' and v_remaining > 0 then
    v_remaining := 0;
  end if;

  if v_paid > 0 and v_status <> 'ignored' then
    insert into public.liability_payments (
      user_id,
      account_id,
      statement_id,
      debit_account_id,
      amount,
      overpayment_amount,
      paid_at,
      source,
      status,
      note
    )
    values (
      auth.uid(),
      v_cycle.account_id,
      v_cycle.id,
      v_debit_account_id,
      v_paid,
      v_overpayment,
      coalesce(p_paid_at, now()),
      'manual',
      'confirmed',
      coalesce(p_note, '还款确认')
    )
    returning * into v_payment;

    if v_effective_liability_payment > 0 then
      insert into public.account_entries (
        user_id,
        account_id,
        direction,
        amount,
        entry_type,
        source_table,
        source_id,
        occurred_at,
        note
      )
      values (
        auth.uid(),
        v_cycle.account_id,
        'out',
        v_effective_liability_payment,
        'transfer',
        'liability_payments',
        v_payment.id,
        coalesce(p_paid_at, now()),
        coalesce(p_note, '还款确认')
      );
    end if;

    if v_debit_account_id is not null then
      insert into public.account_entries (
        user_id,
        account_id,
        direction,
        amount,
        entry_type,
        source_table,
        source_id,
        occurred_at,
        note
      )
      values (
        auth.uid(),
        v_debit_account_id,
        'out',
        v_paid,
        'transfer',
        'liability_payments',
        v_payment.id,
        coalesce(p_paid_at, now()),
        coalesce(p_note, '还款扣款')
      );
    end if;
  end if;

  update public.account_repayment_cycles
     set paid_amount = v_paid,
         remaining_amount = case when v_status = 'paid' then 0 else v_remaining end,
         carried_over_amount = case when v_status = 'carried_over' then v_remaining else 0 end,
         status = v_status,
         auto_debit_account_id = v_debit_account_id,
         source = case when source = 'system' then 'manual' else source end,
         note = coalesce(p_note, note),
         confirmed_at = case when v_paid > 0 or v_status in ('paid', 'ignored') then coalesce(p_paid_at, now()) else null end,
         updated_at = now()
   where id = v_cycle.id
   returning * into v_cycle;

  return v_cycle;
end;
$$;

revoke all on function public.set_repayment_cycle_paid_amount(uuid, numeric, timestamptz, uuid, text, text) from public;
grant execute on function public.set_repayment_cycle_paid_amount(uuid, numeric, timestamptz, uuid, text, text) to authenticated;
