\set ON_ERROR_STOP on

create or replace function public.account_management_test_assert(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'account management contract assertion failed: %', p_message;
  end if;
end;
$$;

select public.account_management_test_assert(
  has_function_privilege(
    'authenticated',
    'public.save_account(text,public.account_type,uuid,text,text,numeric,integer,integer,uuid,boolean,boolean,boolean)',
    'execute'
  ),
  'authenticated must execute canonical account save'
);
select public.account_management_test_assert(
  not has_function_privilege(
    'anon',
    'public.save_account(text,public.account_type,uuid,text,text,numeric,integer,integer,uuid,boolean,boolean,boolean)',
    'execute'
  ),
  'anon must not execute canonical account save'
);
select public.account_management_test_assert(
  has_function_privilege('authenticated', 'public.set_account_archived(uuid,boolean)', 'execute'),
  'authenticated must execute canonical account archive'
);
select public.account_management_test_assert(
  not has_function_privilege('anon', 'public.set_account_archived(uuid,boolean)', 'execute'),
  'anon must not execute canonical account archive'
);

select public.account_management_test_assert(
  (select is_default_expense and is_default_income
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000001'),
  'migration must preserve the first effective active defaults'
);
select public.account_management_test_assert(
  (select not is_default_expense
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000002'),
  'migration must clear duplicate active defaults'
);
select public.account_management_test_assert(
  (select not is_default_expense and not is_default_income
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000003'),
  'migration must clear archived defaults'
);

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

-- Legacy clients still patch the target first and clear old defaults later.
update public.accounts
set is_default_expense = true
where id = '66000000-0000-4000-8000-000000000002';

select public.account_management_test_assert(
  (select count(*) = 1
     from public.accounts
    where user_id = '11111111-1111-4111-8111-111111111111'
      and is_default_expense
      and not is_archived),
  'legacy direct writes must keep one active expense default'
);
select public.account_management_test_assert(
  (select is_default_expense
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000002'),
  'legacy direct write must keep the requested default'
);

update public.accounts
set is_archived = true,
    is_default_expense = true,
    is_default_income = true
where id = '66000000-0000-4000-8000-000000000002';

select public.account_management_test_assert(
  (select is_archived and not is_default_expense and not is_default_income
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000002'),
  'legacy archive must clear default flags in the same write'
);

update public.accounts
set is_archived = false
where id = '66000000-0000-4000-8000-000000000002';

select public.account_management_test_assert(
  (select not is_default_expense and not is_default_income
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000002'),
  'legacy restore must not restore defaults'
);

select public.save_account(
  'Canonical 新账户', 'wallet_balance', null, '测试机构', null, 88,
  null, null, null, false, false, true
);

select public.account_management_test_assert(
  (select count(*) = 1
     from public.accounts
    where user_id = '11111111-1111-4111-8111-111111111111'
      and is_default_income
      and not is_archived),
  'canonical save must atomically replace the income default'
);
select public.account_management_test_assert(
  (select initial_balance = 88 and current_balance = 88
     from public.accounts
    where name = 'Canonical 新账户'),
  'canonical create must initialize balances once'
);

select public.save_account(
  '第一默认账户已编辑', 'debit_card',
  '66000000-0000-4000-8000-000000000001', null, null, 999,
  null, null, null, false, false, false
);

select public.account_management_test_assert(
  (select initial_balance = 100 and current_balance = 100 and name = '第一默认账户已编辑'
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000001'),
  'canonical edit must preserve balances'
);

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.save_account(
      '禁止跨家族', 'credit_card',
      '66000000-0000-4000-8000-000000000001', null, null, 0,
      18, 28, null, false, false, false
    );
  exception when others then
    rejected := position('account_type_transition_blocked' in sqlerrm) > 0;
  end;
  if not rejected then
    raise exception 'account management contract assertion failed: historical cross-family transition must be rejected';
  end if;
end;
$$;

select public.save_account(
  '空负债账户', 'credit_line',
  '66000000-0000-4000-8000-000000000006', null, null, 0,
  18, 28, '66000000-0000-4000-8000-000000000004', false, false, false
);

select public.account_management_test_assert(
  (select type = 'credit_line' and bill_day = 18 and payment_due_day = 28
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000006'),
  'empty unreferenced account may cross families'
);

select public.set_account_archived('66000000-0000-4000-8000-000000000004', true);

select public.account_management_test_assert(
  (select is_archived and current_balance = 500
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000004'),
  'archive must preserve account balance'
);
select public.account_management_test_assert(
  (select auto_debit_account_id is null
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000005'),
  'archive must clear future account auto-debit references'
);
select public.account_management_test_assert(
  (select auto_debit_account_id is null
     from public.account_repayment_cycles
    where id = '66200000-0000-4000-8000-000000000001'),
  'archive must clear open-cycle auto-debit references'
);
select public.account_management_test_assert(
  (select auto_debit_account_id = '66000000-0000-4000-8000-000000000004'
     from public.account_repayment_cycles
    where id = '66200000-0000-4000-8000-000000000002'),
  'archive must preserve paid-cycle history'
);
select public.account_management_test_assert(
  (select debit_account_id = '66000000-0000-4000-8000-000000000004'
     from public.liability_payments
    where id = '66300000-0000-4000-8000-000000000001'),
  'archive must preserve payment history'
);

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.save_account(
      '负债账户', 'credit_card',
      '66000000-0000-4000-8000-000000000005', null, null, 0,
      18, 28, '66000000-0000-4000-8000-000000000004', false, false, false
    );
  exception when others then
    rejected := position('invalid_auto_debit_account' in sqlerrm) > 0;
  end;
  if not rejected then
    raise exception 'account management contract assertion failed: archived auto-debit account must be rejected';
  end if;
end;
$$;

select public.set_account_archived('66000000-0000-4000-8000-000000000004', false);
select public.account_management_test_assert(
  (select not is_archived and not is_default_expense and not is_default_income
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000004'),
  'restore must not restore defaults'
);
select public.account_management_test_assert(
  (select auto_debit_account_id is null
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000005'),
  'restore must not restore account auto-debit references'
);
select public.account_management_test_assert(
  (select auto_debit_account_id is null
     from public.account_repayment_cycles
    where id = '66200000-0000-4000-8000-000000000001'),
  'restore must not restore open-cycle auto-debit references'
);

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.save_account(
      '跨用户编辑', 'debit_card',
      '66000000-0000-4000-8000-000000000001', null, null, 0,
      null, null, null, false, false, false
    );
  exception when others then
    rejected := position('account not found or permission denied' in sqlerrm) > 0;
  end;
  if not rejected then
    raise exception 'account management contract assertion failed: cross-user edit must be rejected';
  end if;
end;
$$;

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.set_account_archived('66000000-0000-4000-8000-000000000001', true);
  exception when others then
    rejected := position('account_not_found' in sqlerrm) > 0;
  end;
  if not rejected then
    raise exception 'account management contract assertion failed: cross-user archive must be rejected';
  end if;
end;
$$;

select public.account_management_test_assert(
  (select name = '第一默认账户已编辑'
     from public.accounts
    where id = '66000000-0000-4000-8000-000000000001'),
  'cross-user failure must preserve owner data'
);

drop function public.account_management_test_assert(boolean, text);
select 'account management contract: ok' as result;
