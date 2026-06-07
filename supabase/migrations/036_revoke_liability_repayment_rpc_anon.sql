revoke execute on function public.ensure_liability_repayment_cycles(text) from anon;
revoke execute on function public.set_repayment_cycle_paid_amount(uuid, numeric, timestamptz, uuid, text, text) from anon;

grant execute on function public.ensure_liability_repayment_cycles(text) to authenticated;
grant execute on function public.set_repayment_cycle_paid_amount(uuid, numeric, timestamptz, uuid, text, text) to authenticated;
