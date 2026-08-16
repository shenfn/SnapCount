\set ON_ERROR_STOP on

create table public.staging_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  status text,
  resolved_action text,
  resolved_at timestamptz,
  target_record_id uuid,
  target_kind text,
  resolved_domain_key text,
  updated_at timestamptz not null default now()
);

alter table public.staging_records
  add constraint staging_records_target_kind_check
  check (target_kind is null or target_kind in ('expense', 'income', 'data'));

grant select, insert, update, delete on public.staging_records to authenticated;

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into public.accounts (id, user_id, name, type, initial_balance, current_balance) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', '11111111-1111-4111-8111-111111111111', '测试负债', 'credit_line', 100, 100),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', '11111111-1111-4111-8111-111111111111', '测试借记卡', 'debit_card', 500, 500),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', '11111111-1111-4111-8111-111111111111', '全额还款负债', 'credit_line', 100, 100),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', '11111111-1111-4111-8111-111111111111', '部分还款负债', 'credit_line', 100, 100),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', '22222222-2222-4222-8222-222222222222', '其他用户负债', 'credit_line', 80, 80);

insert into public.account_repayment_cycles (
  id, user_id, account_id, cycle_month, statement_amount, paid_amount,
  remaining_amount, min_payment_amount, status, due_date, source
) values
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc1', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', '2026-08', 100, 0, 100, 20, 'pending', '2026-08-20', 'system'),
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc2', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', '2026-07', 20, 20, 0, 5, 'paid', '2026-07-20', 'screenshot'),
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc3', '22222222-2222-4222-8222-222222222222', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', '2026-08', 80, 0, 80, 10, 'pending', '2026-08-20', 'system'),
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc4', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', '2026-09', 100, 0, 100, 20, 'pending', '2026-09-20', 'system'),
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc5', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', '2026-10', 100, 0, 100, 20, 'pending', '2026-10-20', 'system');

insert into public.staging_records (id, user_id, status, resolved_action, target_record_id) values
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd1', '11111111-1111-4111-8111-111111111111', 'pending_review', null, null),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2', '11111111-1111-4111-8111-111111111111', 'archived', 'liability_repayment_confirmed', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd3', '11111111-1111-4111-8111-111111111111', 'pending_review', null, null),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4', '22222222-2222-4222-8222-222222222222', 'pending_review', null, null),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd5', '11111111-1111-4111-8111-111111111111', 'pending_review', null, null),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd6', '11111111-1111-4111-8111-111111111111', 'discarded', 'discarded', null),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd7', '11111111-1111-4111-8111-111111111111', 'archived', 'liability_repayment_confirmed', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1');
