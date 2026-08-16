\set ON_ERROR_STOP on

create or replace function public.staging_archive_test_assert(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'staging archive assertion failed: %', p_message;
  end if;
end;
$$;

insert into public.data_domains (id, key, name, status, is_system, version)
values (
  '60000000-0000-4000-8000-000000000001',
  'sport',
  '运动记录',
  'active',
  true,
  '1.0'
)
on conflict (id) do nothing;

select public.staging_archive_test_assert(
  has_function_privilege(
    'authenticated',
    'public.archive_staging_record(uuid,text,numeric,text,text,text,text,text,date,time without time zone,timestamp with time zone,text,jsonb,uuid)',
    'EXECUTE'
  ),
  'authenticated must execute the archive RPC'
);
select public.staging_archive_test_assert(
  not has_function_privilege(
    'anon',
    'public.archive_staging_record(uuid,text,numeric,text,text,text,text,text,date,time without time zone,timestamp with time zone,text,jsonb,uuid)',
    'EXECUTE'
  ),
  'anon must not execute the archive RPC'
);
select public.staging_archive_test_assert(
  not has_function_privilege(
    'authenticated',
    'public.archive_staging_record_legacy(uuid,text,numeric,text,text,text,text,text,date,time without time zone,timestamp with time zone,text,jsonb,uuid)',
    'EXECUTE'
  ),
  'authenticated must not bypass the idempotency guard through the legacy implementation'
);

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

-- Expense archive must create the target, one ledger entry, terminal staging
-- state and one routing feedback row as one observable result.
insert into public.staging_records (
  id, user_id, status, detected_domain_key, image_hash, companion_message
) values (
  '61000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  'pending_review',
  'expense',
  'archive-expense-hash',
  '保留的陪伴说明'
);
insert into public.accounts (id, user_id, name, type)
values (
  '62000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  'Archive cash',
  'cash'
);

select public.staging_archive_test_assert(
  (public.archive_staging_record(
    '61000000-0000-4000-8000-000000000001',
    'expense',
    18.50,
    '午餐',
    '测试平台',
    '餐饮',
    '现金',
    null,
    '2026-08-16',
    '12:30',
    '2026-08-16T04:30:00Z',
    '测试支出',
    '{"source":"contract-test"}'::jsonb,
    '62000000-0000-4000-8000-000000000001'
  )->>'idempotent_retry') = 'false',
  'first expense archive must not be marked as retry'
);
select public.staging_archive_test_assert(
  (select status = 'archived' and target_record_id is not null
   from public.staging_records
   where id = '61000000-0000-4000-8000-000000000001'),
  'expense staging must become archived with a target'
);
select public.staging_archive_test_assert(
  (select target_kind = 'expense' and resolved_domain_key = 'expense'
   from public.staging_records
   where id = '61000000-0000-4000-8000-000000000001'),
  'expense archive must persist its physical and final target type'
);
select public.staging_archive_test_assert(
  (select count(*) = 1
   from public.transactions
   where staging_record_id = '61000000-0000-4000-8000-000000000001'
     and user_id = '11111111-1111-4111-8111-111111111111'
     and amount = 18.50),
  'expense archive must create exactly one target transaction'
);
select public.staging_archive_test_assert(
  (select count(*) = 1
   from public.account_entries
   where source_table = 'transactions'
     and source_id = (select target_record_id from public.staging_records where id = '61000000-0000-4000-8000-000000000001')
     and user_id = '11111111-1111-4111-8111-111111111111'),
  'expense archive must create exactly one account entry'
);
select public.staging_archive_test_assert(
  (select count(*) = 1
   from public.user_routing_feedback
   where staging_record_id = '61000000-0000-4000-8000-000000000001'),
  'expense archive must create exactly one routing feedback row'
);

-- Same-domain retry must return the original target and create no duplicates.
update public.staging_records
   set target_kind = null,
       resolved_domain_key = null
 where id = '61000000-0000-4000-8000-000000000001';
select public.staging_archive_test_assert(
  (public.archive_staging_record(
    '61000000-0000-4000-8000-000000000001',
    'expense',
    999.99,
    '不应覆盖',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    '{}'::jsonb,
    null
  )->>'idempotent_retry') = 'true',
  'same-domain retry must be idempotent'
);
select public.staging_archive_test_assert(
  (select target_kind = 'expense' and resolved_domain_key = 'expense'
   from public.staging_records
   where id = '61000000-0000-4000-8000-000000000001'),
  'same-domain retry must self-heal missing target type metadata'
);
select public.staging_archive_test_assert(
  (select count(*) = 1 from public.transactions
   where staging_record_id = '61000000-0000-4000-8000-000000000001'),
  'same-domain retry must not create a second transaction'
);
select public.staging_archive_test_assert(
  (select count(*) = 1 from public.account_entries
   where source_table = 'transactions'
     and source_id = (select target_record_id from public.staging_records where id = '61000000-0000-4000-8000-000000000001')),
  'same-domain retry must not create a second account entry'
);
select public.staging_archive_test_assert(
  (select count(*) = 1 from public.user_routing_feedback
   where staging_record_id = '61000000-0000-4000-8000-000000000001'),
  'same-domain retry must not create a second routing feedback row'
);

-- Income uses the same archive transaction and creates one inbound ledger row.
insert into public.staging_records (
  id, user_id, status, detected_domain_key, image_hash
) values (
  '61000000-0000-4000-8000-000000000005',
  '11111111-1111-4111-8111-111111111111',
  'pending_review',
  'income',
  'archive-income-hash'
);
select public.staging_archive_test_assert(
  (public.archive_staging_record(
    '61000000-0000-4000-8000-000000000005',
    'income',
    500.00,
    '报销',
    null,
    null,
    null,
    'reimbursement',
    '2026-08-16',
    null,
    '2026-08-16T02:00:00Z',
    '测试收入',
    '{}'::jsonb,
    '62000000-0000-4000-8000-000000000001'
  )->>'target_reference') like 'income/%',
  'income archive must return an income target reference'
);
select public.staging_archive_test_assert(
  (select count(*) = 1
   from public.income_records
   where staging_record_id = '61000000-0000-4000-8000-000000000005'
     and user_id = '11111111-1111-4111-8111-111111111111'
     and amount = 500.00),
  'income archive must create exactly one target record'
);
select public.staging_archive_test_assert(
  (select target_kind = 'income' and resolved_domain_key = 'income'
   from public.staging_records
   where id = '61000000-0000-4000-8000-000000000005'),
  'income archive must persist its target type'
);
select public.staging_archive_test_assert(
  (select count(*) = 1
   from public.account_entries
   where source_table = 'income_records'
     and source_id = (select target_record_id from public.staging_records where id = '61000000-0000-4000-8000-000000000005')
     and account_id = '62000000-0000-4000-8000-000000000001'
     and direction = 'in'),
  'income archive must create exactly one inbound account entry'
);

-- Missing/invalid finance facts must fail closed and keep the staging row open.
insert into public.staging_records (id, user_id, status, detected_domain_key)
values (
  '61000000-0000-4000-8000-000000000002',
  '11111111-1111-4111-8111-111111111111',
  'pending_review',
  'expense'
);
do $$
begin
  begin
    perform public.archive_staging_record(
      '61000000-0000-4000-8000-000000000002', 'expense', null,
      '缺少金额', null, null, null, null, null, null, null, null, '{}'::jsonb, null
    );
    raise exception 'expected missing amount rejection';
  exception when others then
    if sqlerrm not like '%expense amount must be greater than 0%' then
      raise;
    end if;
  end;
end;
$$;
select public.staging_archive_test_assert(
  (select status = 'pending_review' and target_record_id is null
   from public.staging_records where id = '61000000-0000-4000-8000-000000000002'),
  'missing amount must leave staging open without a target'
);

-- Cross-user access must fail closed.
do $$
begin
  perform set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
  begin
    perform public.archive_staging_record(
      '61000000-0000-4000-8000-000000000001', 'expense', 1,
      '越权', null, null, null, null, null, null, null, null, '{}'::jsonb, null
    );
    raise exception 'expected cross-user archive rejection';
  exception when others then
    if sqlerrm not like '%staging record not found or permission denied%' then
      raise;
    end if;
  end;
end;
$$;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

-- Generic data-domain archive must use the same atomic endpoint.
insert into public.staging_records (id, user_id, status, detected_domain_key)
values (
  '61000000-0000-4000-8000-000000000003',
  '11111111-1111-4111-8111-111111111111',
  'pending_review',
  'sport'
);
select public.staging_archive_test_assert(
  (public.archive_staging_record(
    '61000000-0000-4000-8000-000000000003', 'sport', null,
    '慢跑', null, null, null, null, null, null,
    '2026-08-16T01:00:00Z', '5 公里', '{"distance_km":5}'::jsonb, null
  )->>'target_reference') like 'data/%',
  'generic archive must return a data target reference'
);
select public.staging_archive_test_assert(
  (select status = 'archived'
   from public.staging_records
   where id = '61000000-0000-4000-8000-000000000003')
  and exists (
    select 1 from public.data_records
    where staging_record_id = '61000000-0000-4000-8000-000000000003'
      and domain_key = 'sport'
  ),
  'generic archive must create the requested domain record'
);
select public.staging_archive_test_assert(
  (select target_kind = 'data' and resolved_domain_key = 'sport'
   from public.staging_records
   where id = '61000000-0000-4000-8000-000000000003'),
  'generic archive must persist data kind and final domain'
);

-- An injected downstream failure must roll back target, staging state and
-- feedback together.
create or replace function public.staging_archive_test_fail_feedback()
returns trigger
language plpgsql
as $$
begin
  if new.staging_record_id = '61000000-0000-4000-8000-000000000004' then
    raise exception 'intentional feedback failure';
  end if;
  return new;
end;
$$;
create trigger staging_archive_test_fail_feedback_trigger
before insert on public.user_routing_feedback
for each row execute function public.staging_archive_test_fail_feedback();

insert into public.staging_records (id, user_id, status, detected_domain_key)
values (
  '61000000-0000-4000-8000-000000000004',
  '11111111-1111-4111-8111-111111111111',
  'pending_review',
  'expense'
);
do $$
begin
  begin
    perform public.archive_staging_record(
      '61000000-0000-4000-8000-000000000004', 'expense', 12.34,
      '应回滚', null, null, null, null, null, null, null, null, '{}'::jsonb,
      '62000000-0000-4000-8000-000000000001'
    );
    raise exception 'expected injected feedback failure';
  exception when others then
    if sqlerrm not like '%intentional feedback failure%' then
      raise;
    end if;
  end;
end;
$$;
select public.staging_archive_test_assert(
  (select status = 'pending_review' and target_record_id is null
   from public.staging_records where id = '61000000-0000-4000-8000-000000000004'),
  'downstream failure must roll staging state back'
);
select public.staging_archive_test_assert(
  not exists (select 1 from public.transactions where staging_record_id = '61000000-0000-4000-8000-000000000004'),
  'downstream failure must roll the target transaction back'
);
select public.staging_archive_test_assert(
  (select count(*) = 2
   from public.account_entries
   where account_id = '62000000-0000-4000-8000-000000000001'),
  'downstream failure must not leave an account entry'
);
select public.staging_archive_test_assert(
  not exists (select 1 from public.user_routing_feedback where staging_record_id = '61000000-0000-4000-8000-000000000004'),
  'downstream failure must not leave feedback'
);

drop trigger staging_archive_test_fail_feedback_trigger on public.user_routing_feedback;
drop function public.staging_archive_test_fail_feedback();

-- Archived retry with a different domain must not fabricate a reference.
do $$
begin
  begin
    perform public.archive_staging_record(
      '61000000-0000-4000-8000-000000000001', 'income', 1,
      '错误域', null, null, null, 'other', null, null, null, null, '{}'::jsonb, null
    );
    raise exception 'expected cross-domain idempotency rejection';
  exception when others then
    if sqlerrm not like '%archived staging record domain mismatch%' then
      raise;
    end if;
  end;
end;
$$;

select public.staging_archive_test_assert(
  (select count(*) = 1 from public.transactions where staging_record_id = '61000000-0000-4000-8000-000000000001'),
  'cross-domain retry must preserve the original target'
);

drop function public.staging_archive_test_assert(boolean, text);

select 'staging archive migration contract: ok' as result;
