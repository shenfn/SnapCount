-- Remove expression-planning artifacts when their source business record is deleted.

create or replace function public.purge_expression_artifacts_after_record_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_exposure_ids uuid[] := '{}'::uuid[];
  v_feedback_keys text[] := '{}'::text[];
  v_deleted_signal_count integer := 0;
  v_deleted_feedback_count integer := 0;
begin
  if old.id is null or old.user_id is null then return old; end if;

  perform pg_advisory_xact_lock(hashtextextended('expression-feedback:' || old.user_id::text, 0));

  select coalesce(array_agg(exposure.id), '{}'::uuid[]) into v_exposure_ids
  from public.expression_exposure_events as exposure
  where exposure.user_id = old.user_id
    and (
      exposure.record_id = old.id
      or exists (
        select 1
        from public.expression_exposure_source_records as source
        where source.exposure_event_id = exposure.id
          and source.user_id = old.user_id
          and source.source_table = tg_table_name
          and source.source_record_id = old.id
      )
    );

  select coalesce(array_agg(feedback.feedback_key), '{}'::text[]) into v_feedback_keys
  from public.expression_feedback_events as feedback
  where feedback.user_id = old.user_id
    and feedback.exposure_event_id = any(v_exposure_ids);

  delete from public.expression_preference_signals
  where user_id = old.user_id
    and (
      exposure_event_id = any(v_exposure_ids)
      or feedback_key = any(v_feedback_keys)
    );
  get diagnostics v_deleted_signal_count = row_count;

  delete from public.expression_feedback_events
  where user_id = old.user_id
    and exposure_event_id = any(v_exposure_ids);
  get diagnostics v_deleted_feedback_count = row_count;

  delete from public.expression_exposure_events
  where user_id = old.user_id
    and id = any(v_exposure_ids);

  delete from public.expression_delivery_snapshots
  where user_id = old.user_id
    and record_id = old.id;

  delete from public.expression_shadow_runs
  where user_id = old.user_id
    and (
      record_id = old.id
      or old.id = any(source_record_ids)
    );

  if v_deleted_signal_count > 0 or v_deleted_feedback_count > 0 then
    delete from public.expression_preference_snapshots where user_id = old.user_id;
    insert into public.expression_preference_revisions (user_id, revision, updated_at)
    values (old.user_id, 1, now())
    on conflict (user_id) do update set
      revision = public.expression_preference_revisions.revision + 1,
      updated_at = now();
  end if;

  return old;
end;
$$;

drop trigger if exists transactions_purge_expression_artifacts on public.transactions;
create trigger transactions_purge_expression_artifacts
after delete on public.transactions
for each row execute function public.purge_expression_artifacts_after_record_delete();

drop trigger if exists income_records_purge_expression_artifacts on public.income_records;
create trigger income_records_purge_expression_artifacts
after delete on public.income_records
for each row execute function public.purge_expression_artifacts_after_record_delete();

drop trigger if exists data_records_purge_expression_artifacts on public.data_records;
create trigger data_records_purge_expression_artifacts
after delete on public.data_records
for each row execute function public.purge_expression_artifacts_after_record_delete();

revoke all on function public.purge_expression_artifacts_after_record_delete() from public, anon, authenticated;

create or replace function public.delete_user_account_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_user_id is null then
    raise exception 'user id is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('expression-feedback:' || p_user_id::text, 0));

  delete from public.expression_preference_signals where user_id = p_user_id;
  delete from public.expression_feedback_events where user_id = p_user_id;
  delete from public.expression_exposure_source_records where user_id = p_user_id;
  delete from public.expression_exposure_events where user_id = p_user_id;
  delete from public.expression_delivery_snapshots where user_id = p_user_id;
  delete from public.expression_preference_snapshots where user_id = p_user_id;
  delete from public.expression_preference_revisions where user_id = p_user_id;
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
  if to_regclass('public.user_finance_vocabulary') is not null then
    execute 'delete from public.user_finance_vocabulary where user_id = $1' using p_user_id;
  end if;
  delete from public.accounts where user_id = p_user_id;
  delete from public.data_domains where user_id = p_user_id;
  delete from public.user_configs where user_id = p_user_id;
end;
$$;

revoke all on function public.delete_user_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_user_account_data(uuid) to service_role;
