-- LOCAL-003 RC: bring the production transaction schema in line with the
-- already-deployed sync tombstone and update-time contract.
--
-- The columns are additive. Existing rows keep their creation time as the
-- best available update time; no transaction data is deleted or rewritten.

alter table public.transactions
  add column if not exists deleted_at timestamptz,
  add column if not exists updated_at timestamptz;

update public.transactions
set updated_at = coalesce(updated_at, created_at, now())
where updated_at is null;

alter table public.transactions
  alter column updated_at set default now(),
  alter column updated_at set not null;

create index if not exists idx_transactions_user_deleted_at
  on public.transactions (user_id, deleted_at);
