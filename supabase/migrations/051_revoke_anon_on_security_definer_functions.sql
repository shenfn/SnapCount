-- Revoke anon execute on all SECURITY DEFINER RPCs that should require authentication
revoke execute on function public.confirm_pending_transaction_with_account(uuid, text, numeric, text, text, text, text, text, uuid) from anon;
revoke execute on function public.create_account_entry_for_record(uuid, text, numeric, text, text, uuid, timestamptz, text) from anon;
revoke execute on function public.delete_income_with_account(uuid) from anon;
revoke execute on function public.delete_transaction_with_account(uuid) from anon;
revoke execute on function public.save_income_with_account(uuid, text, text, numeric, date, text, text, text, text, text, uuid) from anon;
revoke execute on function public.save_transaction_with_account(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid) from anon;
revoke execute on function public.void_account_entries_for_record(text, uuid, text) from anon;
revoke execute on function public.revoke_liability_payment(uuid, text) from anon;
revoke execute on function public.recalculate_account_balance(uuid) from anon;
revoke execute on function public.maintain_account_balance() from anon;
revoke execute on function public.resolve_account_entry_direction(uuid, text, text) from anon;
revoke execute on function public.handle_new_user() from anon;

-- Fix ai_insights RLS: replace always-true policies with user-scoped ones
drop policy if exists ai_insights_delete_all on public.ai_insights;
drop policy if exists ai_insights_update_all on public.ai_insights;
drop policy if exists ai_insights_write_all on public.ai_insights;

create policy ai_insights_delete_own on public.ai_insights
  for delete using (user_id = auth.uid());

create policy ai_insights_update_own on public.ai_insights
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy ai_insights_insert_own on public.ai_insights
  for insert with check (user_id = auth.uid());

-- Fix handle_new_user: add fixed search_path
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from anon;
