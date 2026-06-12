create or replace function public.revoke_liability_payment(
  p_payment_id uuid,
  p_reason text default 'payment_revoked'
)
returns public.account_repayment_cycles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.liability_payments%rowtype;
  v_cycle public.account_repayment_cycles%rowtype;
  v_statement_amount numeric(14,2);
  v_paid numeric(14,2);
  v_remaining numeric(14,2);
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_payment_id is null then
    raise exception 'payment_id is required';
  end if;

  select *
    into v_payment
  from public.liability_payments
  where id = p_payment_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'payment not found or permission denied';
  end if;

  if v_payment.status = 'voided' then
    if v_payment.statement_id is null then
      return null;
    end if;

    select *
      into v_cycle
    from public.account_repayment_cycles
    where id = v_payment.statement_id
      and user_id = auth.uid();
    return v_cycle;
  end if;

  update public.liability_payments
     set status = 'voided',
         note = coalesce(note, '') || case when note is null or note = '' then '' else '；' end || coalesce(p_reason, '还款已撤销'),
         updated_at = now()
   where id = v_payment.id;

  update public.account_entries
     set is_voided = true,
         voided_reason = coalesce(p_reason, 'payment_revoked')
   where user_id = auth.uid()
     and source_table = 'liability_payments'
     and source_id = v_payment.id
     and is_voided = false;

  if v_payment.statement_id is null then
    return null;
  end if;

  select *
    into v_cycle
  from public.account_repayment_cycles
  where id = v_payment.statement_id
    and user_id = auth.uid()
  for update;

  if not found then
    return null;
  end if;

  select coalesce(sum(amount), 0)::numeric(14,2)
    into v_paid
  from public.liability_payments
  where user_id = auth.uid()
    and statement_id = v_cycle.id
    and status = 'confirmed';

  v_statement_amount := coalesce(v_cycle.statement_amount, 0);
  v_remaining := greatest(v_statement_amount - least(v_paid, v_statement_amount), 0);

  v_status := case
    when v_paid <= 0 then
      case
        when v_cycle.due_date is not null and v_cycle.due_date < current_date then 'overdue_unconfirmed'
        when v_cycle.due_date is not null and v_cycle.due_date = current_date then 'due_today'
        else 'pending'
      end
    when v_remaining <= 0 then 'paid'
    when v_cycle.min_payment_amount is not null and v_paid >= v_cycle.min_payment_amount then 'minimum_paid'
    else 'partial_paid'
  end;

  update public.account_repayment_cycles
     set paid_amount = v_paid,
         remaining_amount = v_remaining,
         carried_over_amount = case when v_status = 'carried_over' then v_remaining else 0 end,
         status = v_status,
         confirmed_at = case when v_paid > 0 then confirmed_at else null end,
         updated_at = now()
   where id = v_cycle.id
   returning * into v_cycle;

  return v_cycle;
end;
$$;

revoke all on function public.revoke_liability_payment(uuid, text) from public;
grant execute on function public.revoke_liability_payment(uuid, text) to authenticated;
