\set ON_ERROR_STOP on

create or replace function public.staging_target_type_test_assert(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'staging target type assertion failed: %', p_message;
  end if;
end;
$$;

select public.staging_target_type_test_assert(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'staging_records'
      and column_name = 'target_kind'
  ),
  'staging_records.target_kind must exist'
);
select public.staging_target_type_test_assert(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'staging_records'
      and column_name = 'resolved_domain_key'
  ),
  'staging_records.resolved_domain_key must exist'
);

select public.staging_target_type_test_assert(
  (select target_kind = 'expense' and resolved_domain_key = 'expense'
   from public.staging_records where id = '63100000-0000-4000-8000-000000000001'),
  'unique expense history must be recovered'
);
select public.staging_target_type_test_assert(
  (select target_kind = 'income' and resolved_domain_key = 'income'
   from public.staging_records where id = '63100000-0000-4000-8000-000000000002'),
  'unique income history must be recovered'
);
select public.staging_target_type_test_assert(
  (select target_kind = 'data' and resolved_domain_key = 'sleep'
   from public.staging_records where id = '63100000-0000-4000-8000-000000000003'),
  'unique data history must be recovered with its final domain'
);
select public.staging_target_type_test_assert(
  (select target_kind is null and resolved_domain_key is null
   from public.staging_records where id = '63100000-0000-4000-8000-000000000004'),
  'multi-table history must remain unknown'
);
select public.staging_target_type_test_assert(
  (select target_kind is null and resolved_domain_key is null
   from public.staging_records where id = '63100000-0000-4000-8000-000000000005'),
  'zero-match history must remain unknown'
);
select public.staging_target_type_test_assert(
  (select target_kind is null and resolved_domain_key is null
   from public.staging_records where id = '63100000-0000-4000-8000-000000000006'),
  'cross-user history must remain unknown'
);

select public.staging_target_type_test_assert(
  exists (
    select 1 from pg_constraint
    where conname = 'staging_records_target_kind_check'
      and conrelid = 'public.staging_records'::regclass
  ),
  'target kind constraint must be present'
);

do $$
begin
  begin
    update public.staging_records
       set target_kind = 'wallet'
     where id = '63100000-0000-4000-8000-000000000005';
    raise exception 'expected invalid target kind rejection';
  exception when check_violation then
    null;
  end;

  begin
    update public.staging_records
       set resolved_domain_key = '   '
     where id = '63100000-0000-4000-8000-000000000005';
    raise exception 'expected blank resolved domain rejection';
  exception when check_violation then
    null;
  end;
end;
$$;

drop function public.staging_target_type_test_assert(boolean, text);
select 'staging target type migration contract: ok' as result;
