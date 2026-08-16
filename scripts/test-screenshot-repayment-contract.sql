\set ON_ERROR_STOP on

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

do $$
declare
  result public.account_repayment_cycles%rowtype;
  payment_count integer;
begin
  select * into result from public.confirm_staging_repayment(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    40,
    '2026-08-16T08:00:00Z',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'paid',
    '截图部分还款'
  );
  if result.status <> 'minimum_paid' or result.remaining_amount <> 60 then
    raise exception 'client paid status must not force the cycle closed: %, %', result.status, result.remaining_amount;
  end if;
  if result.source <> 'screenshot' then raise exception 'cycle source was not screenshot'; end if;

  if not exists (
    select 1 from public.staging_records
    where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1'
      and status = 'archived'
      and target_record_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
      and target_kind = 'repayment_cycle'
      and resolved_domain_key = 'wallet'
      and resolved_action = 'liability_repayment_confirmed'
  ) then raise exception 'staging target metadata missing'; end if;

  if (select current_balance from public.accounts where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1') <> 60 then
    raise exception 'liability balance direction is incorrect';
  end if;
  if (select current_balance from public.accounts where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1') <> 460 then
    raise exception 'debit balance direction is incorrect';
  end if;
  if not exists (
    select 1 from public.liability_payments
    where statement_id = result.id and amount = 40 and source = 'screenshot' and status = 'confirmed'
  ) then raise exception 'screenshot payment missing'; end if;

  select * into result from public.confirm_staging_repayment(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    40, now(), 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', 'paid', '幂等重试'
  );
  select count(*) into payment_count from public.liability_payments
   where statement_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1' and status <> 'voided';
  if payment_count <> 1 then raise exception 'idempotent retry created another payment'; end if;
  if (select current_balance from public.accounts where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1') <> 60 then
    raise exception 'idempotent retry changed liability balance again';
  end if;
  if (select current_balance from public.accounts where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1') <> 460 then
    raise exception 'idempotent retry changed debit balance again';
  end if;
end $$;

do $$
declare
  result public.account_repayment_cycles%rowtype;
begin
  select * into result from public.confirm_staging_repayment(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd3',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
    100, '2026-08-16T09:00:00Z', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', 'partial_paid', '截图全额还款'
  );
  if result.status <> 'paid' or result.remaining_amount <> 0 then
    raise exception 'full repayment was not derived from canonical amounts: %, %', result.status, result.remaining_amount;
  end if;
  if (select current_balance from public.accounts where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3') <> 0 then
    raise exception 'full repayment did not clear liability balance';
  end if;
  if (select current_balance from public.accounts where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1') <> 360 then
    raise exception 'full repayment did not reduce debit balance';
  end if;
end $$;

do $$
declare
  result public.account_repayment_cycles%rowtype;
begin
  select * into result from public.confirm_staging_repayment(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd5',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
    10, '2026-08-16T10:00:00Z', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', 'paid', '截图普通部分还款'
  );
  if result.status <> 'partial_paid' or result.remaining_amount <> 90 then
    raise exception 'partial repayment status was not derived from canonical amounts: %, %', result.status, result.remaining_amount;
  end if;
  if (select current_balance from public.accounts where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4') <> 90 then
    raise exception 'partial repayment liability balance is incorrect';
  end if;
  if (select current_balance from public.accounts where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1') <> 350 then
    raise exception 'partial repayment debit balance is incorrect';
  end if;
end $$;

do $$
begin
  perform public.confirm_staging_repayment(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
    20, now(), null, null, '冲突目标'
  );
  raise exception 'archived staging accepted a different cycle';
exception when others then
  if sqlerrm = 'archived staging accepted a different cycle' then raise; end if;
end $$;

do $$
begin
  perform public.confirm_staging_repayment(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd6',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
    10, now(), null, null, '已丢弃记录'
  );
  raise exception 'discarded staging was accepted';
exception when others then
  if sqlerrm = 'discarded staging was accepted' then raise; end if;
end $$;

do $$
begin
  perform public.confirm_staging_repayment(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd4',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
    80, now(), null, null, '跨用户'
  );
  raise exception 'cross-user staging was accepted';
exception when others then
  if sqlerrm = 'cross-user staging was accepted' then raise; end if;
end $$;

do $$
begin
  if not exists (
    select 1 from public.staging_records
    where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2'
      and target_kind = 'repayment_cycle'
      and resolved_domain_key = 'wallet'
  ) then raise exception 'historical repayment target was not backfilled'; end if;
  if exists (
    select 1 from public.staging_records
    where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd7'
      and (target_kind is not null or resolved_domain_key is not null)
  ) then raise exception 'unmatched historical repayment target was backfilled'; end if;
end $$;

reset role;

do $$
begin
  if has_function_privilege('anon', 'public.confirm_staging_repayment(uuid,uuid,numeric,timestamp with time zone,uuid,text,text)', 'EXECUTE') then
    raise exception 'anon can execute confirm_staging_repayment';
  end if;
end $$;
