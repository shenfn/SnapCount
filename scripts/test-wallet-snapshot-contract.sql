\set ON_ERROR_STOP on

create or replace function public.wallet_snapshot_test_assert(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'wallet snapshot contract assertion failed: %', p_message;
  end if;
end;
$$;

select public.wallet_snapshot_test_assert(
  has_function_privilege('authenticated', 'public.apply_wallet_snapshot(uuid,uuid)', 'execute'),
  'authenticated must execute wallet snapshot command'
);
select public.wallet_snapshot_test_assert(
  not has_function_privilege('anon', 'public.apply_wallet_snapshot(uuid,uuid)', 'execute'),
  'anon must not execute wallet snapshot command'
);

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into public.accounts (
  id, user_id, name, type, initial_balance, current_balance, snapshot_balance, snapshot_at
) values
  ('41000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '空资产账户', 'wallet_balance', 0, 0, null, null),
  ('41000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '既有资产账户', 'debit_card', 500, 500, null, null),
  ('41000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', '较新资产账户', 'wallet_balance', 500, 500, 500, '2026-08-15T08:00:00Z'),
  ('41000000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', '账单负债账户', 'credit_line', 300, 300, null, null),
  ('41000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', '已还负债账户', 'credit_line', 200, 200, null, null),
  ('41000000-0000-4000-8000-000000000006', '11111111-1111-4111-8111-111111111111', '冲突负债账户', 'credit_card', 150, 150, null, null),
  ('41000000-0000-4000-8000-000000000007', '11111111-1111-4111-8111-111111111111', '校准负债账户', 'credit_line', 80, 80, 80, '2026-08-01T08:00:00Z'),
  ('41000000-0000-4000-8000-000000000008', '22222222-2222-4222-8222-222222222222', '其他用户账户', 'wallet_balance', 50, 50, null, null);

insert into public.data_records (
  id, user_id, domain_key, occurred_at, title, payload_jsonb, account_snapshot_kind, snapshot_balance, snapshot_at
) values
  ('42000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-16T08:00:00Z', '新资产', '{"account_name":"微信零钱","account_type":"wallet_balance","snapshot_balance":250}'::jsonb, 'asset', 250, '2026-08-16T08:00:00Z'),
  ('42000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-14T08:00:00Z', '空账户快照', '{"snapshot_balance":90}'::jsonb, 'asset', 90, '2026-08-14T08:00:00Z'),
  ('42000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-14T09:00:00Z', '既有账户快照', '{"snapshot_balance":900}'::jsonb, 'asset', 900, '2026-08-14T09:00:00Z'),
  ('42000000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-01T08:00:00Z', '旧快照', '{"snapshot_balance":100}'::jsonb, 'asset', 100, '2026-08-01T08:00:00Z'),
  ('42000000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-16T10:00:00Z', '待还账单', '{"snapshot_balance":300,"cycle_month":"2026-08","due_date":"2026-08-28","status":"unpaid"}'::jsonb, 'liability', 300, '2026-08-16T10:00:00Z'),
  ('42000000-0000-4000-8000-000000000006', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-10T10:00:00Z', '受保护账单', '{"snapshot_balance":900,"cycle_month":"2026-07","status":"unpaid"}'::jsonb, 'liability', 900, '2026-08-10T10:00:00Z'),
  ('42000000-0000-4000-8000-000000000007', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-16T11:00:00Z', '已还账单', '{"snapshot_balance":200,"cycle_month":"2026-06","status":"paid"}'::jsonb, 'liability', 200, '2026-08-16T11:00:00Z'),
  ('42000000-0000-4000-8000-000000000008', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-16T12:00:00Z', '冲突已还账单', '{"snapshot_balance":150,"cycle_month":"2026-05","status":"paid"}'::jsonb, 'liability', 150, '2026-08-16T12:00:00Z'),
  ('42000000-0000-4000-8000-000000000009', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-16T13:00:00Z', '当前总欠款', '{"snapshot_balance":120,"balance_scope":"current_total"}'::jsonb, 'liability', 120, '2026-08-16T13:00:00Z'),
  ('42000000-0000-4000-8000-000000000010', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-02T13:00:00Z', '旧总欠款', '{"snapshot_balance":60,"balance_scope":"current_total"}'::jsonb, 'liability', 60, '2026-08-02T13:00:00Z'),
  ('42000000-0000-4000-8000-000000000011', '22222222-2222-4222-8222-222222222222', 'wallet', '2026-08-16T14:00:00Z', '其他用户快照', '{"snapshot_balance":60}'::jsonb, 'asset', 60, '2026-08-16T14:00:00Z'),
  ('42000000-0000-4000-8000-000000000012', '11111111-1111-4111-8111-111111111111', 'wallet', '2026-08-16T15:00:00Z', '回滚快照', '{"snapshot_balance":70}'::jsonb, 'asset', 70, '2026-08-16T15:00:00Z');

insert into public.account_repayment_cycles (
  id, user_id, account_id, cycle_month, statement_amount, original_statement_amount,
  paid_amount, remaining_amount, carried_over_amount, status, source, evidence_record_id,
  statement_source_priority
) values
  ('43000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', '41000000-0000-4000-8000-000000000004', '2026-07', 800, 800, 0, 800, 0, 'pending', 'manual', null, 100),
  ('43000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', '41000000-0000-4000-8000-000000000005', '2026-06', 200, 200, 0, 200, 0, 'pending', 'system', null, 10),
  ('43000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', '41000000-0000-4000-8000-000000000006', '2026-05', 150, 150, 50, 100, 0, 'partial_paid', 'manual', null, 100);

insert into public.liability_payments (
  id, user_id, account_id, statement_id, amount, paid_at, source, status, note
) values (
  '44000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '41000000-0000-4000-8000-000000000006',
  '43000000-0000-4000-8000-000000000003',
  50,
  '2026-08-01T12:00:00Z',
  'manual',
  'confirmed',
  '已有人工付款'
);

select set_config('request.jwt.claim.sub', '', false);
do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000001', null);
  exception when others then
    if position('not_authenticated' in sqlerrm) > 0 then rejected := true; else raise; end if;
  end;
  if not rejected then raise exception 'wallet snapshot contract assertion failed: anonymous command must be rejected'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000011', null);
  exception when others then
    if position('wallet_snapshot_not_found' in sqlerrm) > 0 then rejected := true; else raise; end if;
  end;
  if not rejected then raise exception 'wallet snapshot contract assertion failed: cross-user record must be rejected'; end if;
end;
$$;

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000008');
  exception when others then
    if position('account_not_found' in sqlerrm) > 0 then rejected := true; else raise; end if;
  end;
  if not rejected then raise exception 'wallet snapshot contract assertion failed: cross-user account must be rejected'; end if;
end;
$$;

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000004');
  exception when others then
    if position('account_kind_mismatch' in sqlerrm) > 0 then rejected := true; else raise; end if;
  end;
  if not rejected then raise exception 'wallet snapshot contract assertion failed: incompatible account family must be rejected'; end if;
end;
$$;

select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000001', null);
select public.wallet_snapshot_test_assert(
  (select count(*) = 1 and bool_and(initial_balance = 250) and bool_and(current_balance = 250)
     from public.accounts
    where source_record_table = 'data_records'
      and source_record_id = '42000000-0000-4000-8000-000000000001'),
  'asset creation must create one opening account'
);
select public.wallet_snapshot_test_assert(
  (select count(*) = 1
     from public.account_entries
    where source_table = 'data_records'
      and source_id = '42000000-0000-4000-8000-000000000001'
      and entry_type = 'snapshot_initialization'),
  'asset creation must leave one opening audit entry'
);
select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000001', null);
select public.wallet_snapshot_test_assert(
  (select count(*) = 1 from public.accounts where source_record_id = '42000000-0000-4000-8000-000000000001'),
  'same record retry must not duplicate the account'
);

select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000002', '41000000-0000-4000-8000-000000000001');
select public.wallet_snapshot_test_assert(
  (select initial_balance = 90 and current_balance = 90 and source_record_id is null
     from public.accounts where id = '41000000-0000-4000-8000-000000000001'),
  'empty account may adopt opening balance without replacing its source'
);

select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000003', '41000000-0000-4000-8000-000000000002');
select public.wallet_snapshot_test_assert(
  (select initial_balance = 500 and current_balance = 500 and snapshot_balance = 900
     from public.accounts where id = '41000000-0000-4000-8000-000000000002'),
  'non-empty account must preserve ledger balances'
);

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000003', '41000000-0000-4000-8000-000000000001');
  exception when others then
    if position('snapshot_link_conflict' in sqlerrm) > 0 then rejected := true; else raise; end if;
  end;
  if not rejected then raise exception 'wallet snapshot contract assertion failed: different link target must conflict'; end if;
end;
$$;

select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000004', '41000000-0000-4000-8000-000000000003');
select public.wallet_snapshot_test_assert(
  (select snapshot_balance = 500 and snapshot_at = '2026-08-15T08:00:00Z'
     from public.accounts where id = '41000000-0000-4000-8000-000000000003'),
  'older snapshot must not replace newer account observation'
);

select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000005', '41000000-0000-4000-8000-000000000004');
select public.wallet_snapshot_test_assert(
  (select count(*) = 1 and bool_and(statement_amount = 300) and bool_and(source = 'screenshot')
     and bool_and(evidence_record_id = '42000000-0000-4000-8000-000000000005')
     and bool_and(statement_source_priority = 90)
     from public.account_repayment_cycles
    where account_id = '41000000-0000-4000-8000-000000000004' and cycle_month = '2026-08'),
  'unpaid screenshot must create one evidence-backed cycle'
);
select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000005', '41000000-0000-4000-8000-000000000004');
select public.wallet_snapshot_test_assert(
  (select count(*) = 1 from public.account_repayment_cycles
    where account_id = '41000000-0000-4000-8000-000000000004' and cycle_month = '2026-08'),
  'unpaid cycle retry must stay idempotent'
);

select public.wallet_snapshot_test_assert(
  (public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000006', '41000000-0000-4000-8000-000000000004')->>'outcome') = 'needs_confirmation',
  'manual or higher-priority cycle must require confirmation'
);
select public.wallet_snapshot_test_assert(
  (select statement_amount = 800 and source = 'manual' and statement_source_priority = 100
     from public.account_repayment_cycles where id = '43000000-0000-4000-8000-000000000001'),
  'protected cycle facts must remain unchanged'
);

select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000007', '41000000-0000-4000-8000-000000000005');
select public.wallet_snapshot_test_assert(
  (select current_balance = 0 from public.accounts where id = '41000000-0000-4000-8000-000000000005'),
  'paid snapshot must reduce liability without a negative balance'
);
select public.wallet_snapshot_test_assert(
  (select count(*) = 1 and bool_and(source = 'screenshot')
     and bool_and(evidence_record_id = '42000000-0000-4000-8000-000000000007')
     from public.liability_payments
    where statement_id = '43000000-0000-4000-8000-000000000002' and status = 'confirmed'),
  'paid snapshot must create one evidence-backed payment'
);
select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000007', '41000000-0000-4000-8000-000000000005');
select public.wallet_snapshot_test_assert(
  (select count(*) = 1 from public.liability_payments
    where evidence_record_id = '42000000-0000-4000-8000-000000000007' and status = 'confirmed'),
  'paid snapshot retry must not duplicate payment evidence'
);

select public.wallet_snapshot_test_assert(
  (public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000008', '41000000-0000-4000-8000-000000000006')->>'outcome') = 'needs_confirmation',
  'conflicting active payment must require confirmation'
);
select public.wallet_snapshot_test_assert(
  (select count(*) = 1 from public.liability_payments
    where statement_id = '43000000-0000-4000-8000-000000000003' and status = 'confirmed'),
  'conflicting payment must not be replaced'
);

select public.wallet_snapshot_test_assert(
  (public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000009', '41000000-0000-4000-8000-000000000007')->>'outcome') = 'needs_confirmation',
  'current-total snapshot without statement identity may still reconcile and request review'
);
select public.wallet_snapshot_test_assert(
  (select current_balance = 120 and last_reconciled_at = '2026-08-16T13:00:00Z'
     from public.accounts where id = '41000000-0000-4000-8000-000000000007'),
  'current-total evidence must reconcile balance and watermark atomically'
);
select public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000010', '41000000-0000-4000-8000-000000000007');
select public.wallet_snapshot_test_assert(
  (select current_balance = 120 and last_reconciled_at = '2026-08-16T13:00:00Z'
     from public.accounts where id = '41000000-0000-4000-8000-000000000007'),
  'older current-total evidence must not move balance or reconciliation watermark backward'
);

create or replace function public.wallet_snapshot_fail_after_account_insert()
returns trigger
language plpgsql
as $$
begin
  if new.id = '42000000-0000-4000-8000-000000000012' then
    raise exception 'fixture_forced_record_failure';
  end if;
  return new;
end;
$$;
create trigger tr_wallet_snapshot_fixture_failure
before update on public.data_records
for each row execute function public.wallet_snapshot_fail_after_account_insert();

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.apply_wallet_snapshot('42000000-0000-4000-8000-000000000012', null);
  exception when others then
    if position('fixture_forced_record_failure' in sqlerrm) > 0 then rejected := true; else raise; end if;
  end;
  if not rejected then raise exception 'wallet snapshot contract assertion failed: forced mid-command failure did not fire'; end if;
end;
$$;
select public.wallet_snapshot_test_assert(
  (select count(*) = 0 from public.accounts where source_record_id = '42000000-0000-4000-8000-000000000012'),
  'mid-command failure must roll back a newly inserted account'
);
select public.wallet_snapshot_test_assert(
  (select linked_account_id is null from public.data_records where id = '42000000-0000-4000-8000-000000000012'),
  'mid-command failure must leave the source record untouched'
);

drop trigger tr_wallet_snapshot_fixture_failure on public.data_records;
drop function public.wallet_snapshot_fail_after_account_insert();
drop function public.wallet_snapshot_test_assert(boolean, text);
select 'wallet snapshot transaction contract: ok' as result;
