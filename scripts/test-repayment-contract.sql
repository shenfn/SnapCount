\set ON_ERROR_STOP on

create or replace function public.repayment_test_assert(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
as $$
begin
  if coalesce(p_condition, false) is not true then
    raise exception 'repayment contract assertion failed: %', p_message;
  end if;
end;
$$;

select public.repayment_test_assert(
  has_function_privilege(
    'authenticated',
    'public.set_repayment_cycle_paid_amount(uuid,numeric,timestamp with time zone,uuid,text,text)',
    'execute'
  ),
  'authenticated must execute repayment confirmation'
);
select public.repayment_test_assert(
  not has_function_privilege(
    'anon',
    'public.set_repayment_cycle_paid_amount(uuid,numeric,timestamp with time zone,uuid,text,text)',
    'execute'
  ),
  'anon must not execute repayment confirmation'
);
select public.repayment_test_assert(
  has_function_privilege(
    'authenticated',
    'public.revoke_liability_payment(uuid,text)',
    'execute'
  ),
  'authenticated must execute repayment revocation'
);
select public.repayment_test_assert(
  not has_function_privilege(
    'anon',
    'public.revoke_liability_payment(uuid,text)',
    'execute'
  ),
  'anon must not execute repayment revocation'
);

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into public.accounts (
  id, user_id, name, type, initial_balance, current_balance
) values
  (
    '31000000-0000-4000-8000-000000000001',
    '11111111-1111-4111-8111-111111111111',
    '测试负债账户',
    'credit_line',
    100,
    100
  ),
  (
    '31000000-0000-4000-8000-000000000002',
    '11111111-1111-4111-8111-111111111111',
    '测试扣款账户',
    'debit_card',
    500,
    500
  );

insert into public.account_repayment_cycles (
  id,
  user_id,
  account_id,
  cycle_month,
  statement_amount,
  paid_amount,
  remaining_amount,
  min_payment_amount,
  status,
  due_date,
  auto_debit_account_id
) values (
  '32000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '31000000-0000-4000-8000-000000000001',
  '2026-08',
  100,
  0,
  100,
  20,
  'pending',
  '2099-08-20',
  '31000000-0000-4000-8000-000000000002'
);

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

select public.set_repayment_cycle_paid_amount(
  '32000000-0000-4000-8000-000000000001',
  40,
  '2026-08-16T08:00:00Z',
  '31000000-0000-4000-8000-000000000002',
  'partial_paid',
  '第一次部分还款'
);

select public.repayment_test_assert(
  (select paid_amount = 40 and remaining_amount = 60 and status = 'partial_paid'
     from public.account_repayment_cycles
    where id = '32000000-0000-4000-8000-000000000001'),
  'partial repayment must update the canonical cycle'
);
select public.repayment_test_assert(
  (select count(*) = 1
     from public.liability_payments
    where statement_id = '32000000-0000-4000-8000-000000000001'
      and status = 'confirmed'
      and amount = 40),
  'partial repayment must create one confirmed payment'
);
select public.repayment_test_assert(
  (select current_balance = 60
     from public.accounts
    where id = '31000000-0000-4000-8000-000000000001'),
  'partial repayment must reduce the liability balance'
);
select public.repayment_test_assert(
  (select current_balance = 460
     from public.accounts
    where id = '31000000-0000-4000-8000-000000000002'),
  'partial repayment must reduce the debit balance'
);

select public.set_repayment_cycle_paid_amount(
  '32000000-0000-4000-8000-000000000001',
  100,
  '2026-08-16T09:00:00Z',
  '31000000-0000-4000-8000-000000000002',
  'paid',
  '重新确认全额还款'
);

select public.repayment_test_assert(
  (select paid_amount = 100 and remaining_amount = 0 and status = 'paid'
     from public.account_repayment_cycles
    where id = '32000000-0000-4000-8000-000000000001'),
  'reconfirmation must replace the canonical cycle amount'
);
select public.repayment_test_assert(
  (select count(*) = 2 and count(*) filter (where status = 'voided') = 1
     from public.liability_payments
    where statement_id = '32000000-0000-4000-8000-000000000001'),
  'reconfirmation must void the previous payment and create one replacement'
);
select public.repayment_test_assert(
  (select count(*) = 4 and count(*) filter (where is_voided) = 2
     from public.account_entries
    where source_table = 'liability_payments'),
  'reconfirmation must void old entries before creating replacement entries'
);
select public.repayment_test_assert(
  (select current_balance = 0
     from public.accounts
    where id = '31000000-0000-4000-8000-000000000001'),
  'reconfirmation must not double-apply the liability payment'
);
select public.repayment_test_assert(
  (select current_balance = 400
     from public.accounts
    where id = '31000000-0000-4000-8000-000000000002'),
  'reconfirmation must not double-apply the debit deduction'
);

select public.revoke_liability_payment(
  (
    select id
      from public.liability_payments
     where statement_id = '32000000-0000-4000-8000-000000000001'
       and status = 'confirmed'
  ),
  '测试撤销'
);

select public.repayment_test_assert(
  (select paid_amount = 0 and remaining_amount = 100 and status = 'pending'
     from public.account_repayment_cycles
    where id = '32000000-0000-4000-8000-000000000001'),
  'revocation must restore the cycle to pending'
);
select public.repayment_test_assert(
  (select current_balance = 100
     from public.accounts
    where id = '31000000-0000-4000-8000-000000000001'),
  'revocation must restore the liability balance'
);
select public.repayment_test_assert(
  (select current_balance = 500
     from public.accounts
    where id = '31000000-0000-4000-8000-000000000002'),
  'revocation must restore the debit balance'
);

select public.revoke_liability_payment(
  (
    select id
     from public.liability_payments
     where statement_id = '32000000-0000-4000-8000-000000000001'
     order by paid_at desc, id desc
     limit 1
  ),
  '重复撤销'
);

select public.repayment_test_assert(
  (select current_balance = 100
     from public.accounts
    where id = '31000000-0000-4000-8000-000000000001'),
  'repeated revocation must not change the liability balance again'
);
select public.repayment_test_assert(
  (select current_balance = 500
     from public.accounts
    where id = '31000000-0000-4000-8000-000000000002'),
  'repeated revocation must not change the debit balance again'
);

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.set_repayment_cycle_paid_amount(
      '32000000-0000-4000-8000-000000000001',
      10,
      now(),
      null,
      'partial_paid',
      '跨用户确认'
    );
  exception
    when others then
      if position('repayment cycle not found or permission denied' in sqlerrm) > 0 then
        rejected := true;
      else
        raise;
      end if;
  end;
  if not rejected then
    raise exception 'repayment contract assertion failed: cross-user confirmation must be rejected';
  end if;
end;
$$;

do $$
declare
  rejected boolean := false;
begin
  begin
    perform public.revoke_liability_payment(
      (
        select id
         from public.liability_payments
         where statement_id = '32000000-0000-4000-8000-000000000001'
         order by paid_at desc, id desc
         limit 1
      ),
      '跨用户撤销'
    );
  exception
    when others then
      if position('payment not found or permission denied' in sqlerrm) > 0 then
        rejected := true;
      else
        raise;
      end if;
  end;
  if not rejected then
    raise exception 'repayment contract assertion failed: cross-user revocation must be rejected';
  end if;
end;
$$;

select public.repayment_test_assert(
  (select count(*) filter (where status = 'confirmed') = 0
     from public.liability_payments
    where statement_id = '32000000-0000-4000-8000-000000000001'),
  'cross-user attempts must not create or restore a confirmed payment'
);

drop function public.repayment_test_assert(boolean, text);
select 'repayment transaction contract: ok' as result;
