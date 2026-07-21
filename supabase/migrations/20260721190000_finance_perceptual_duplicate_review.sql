-- Keep perceptual duplicate review independent from optional AI trace logging.

alter table public.transactions
  add column if not exists perceptual_hash text;

alter table public.income_records
  add column if not exists perceptual_hash text;

create index if not exists idx_transactions_user_perceptual_recent
  on public.transactions (user_id, created_at desc)
  where perceptual_hash is not null;

create index if not exists idx_income_user_perceptual_recent
  on public.income_records (user_id, created_at desc)
  where perceptual_hash is not null;

create or replace function public.fill_finance_perceptual_hash_from_staging()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.perceptual_hash is null and new.staging_record_id is not null then
    select staging.perceptual_hash
      into new.perceptual_hash
    from public.staging_records as staging
    where staging.id = new.staging_record_id
      and staging.user_id = new.user_id;
  end if;

  return new;
end;
$$;

drop trigger if exists fill_transaction_perceptual_hash_from_staging on public.transactions;
create trigger fill_transaction_perceptual_hash_from_staging
before insert or update on public.transactions
for each row execute function public.fill_finance_perceptual_hash_from_staging();

drop trigger if exists fill_income_perceptual_hash_from_staging on public.income_records;
create trigger fill_income_perceptual_hash_from_staging
before insert or update on public.income_records
for each row execute function public.fill_finance_perceptual_hash_from_staging();

update public.transactions as transaction
set perceptual_hash = staging.perceptual_hash
from public.staging_records as staging
where transaction.staging_record_id = staging.id
  and transaction.user_id = staging.user_id
  and transaction.perceptual_hash is null
  and staging.perceptual_hash is not null;

update public.income_records as income
set perceptual_hash = staging.perceptual_hash
from public.staging_records as staging
where income.staging_record_id = staging.id
  and income.user_id = staging.user_id
  and income.perceptual_hash is null
  and staging.perceptual_hash is not null;

revoke all on function public.fill_finance_perceptual_hash_from_staging() from public;
revoke execute on function public.fill_finance_perceptual_hash_from_staging() from anon, authenticated;

comment on column public.transactions.perceptual_hash is
  'Non-reversible 64-bit image fingerprint used only for user-scoped possible-duplicate review.';
comment on column public.income_records.perceptual_hash is
  'Non-reversible 64-bit image fingerprint used only for user-scoped possible-duplicate review.';
