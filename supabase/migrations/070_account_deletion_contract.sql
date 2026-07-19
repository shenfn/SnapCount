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
