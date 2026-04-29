-- ════════════════════════════════════════════════════════════════════
-- 随手账 V1.0 数据库初始化脚本
-- 使用方式：Supabase Dashboard → SQL Editor → 粘贴并 Run
-- ════════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp";

-- ─── transactions 表（支出/收入流水） ───
create table if not exists public.transactions (
  id                  uuid primary key default uuid_generate_v4(),
  created_at          timestamptz not null default now(),
  transaction_date    date not null default current_date,
  transaction_time    time,
  type                text not null check (type in ('expense','income')),
  amount              numeric(10,2) not null check (amount > 0),
  merchant_name       text,
  platform            text,
  category            text,
  payment_method      text,
  status              text not null default 'pending' check (status in ('pending','done')),
  image_url           text,
  image_hash          text unique,
  is_large_transport  boolean default false,
  transport_type      text,
  source              text not null default 'ai_scan' check (source in ('ai_scan','manual')),
  note                text,
  user_id             uuid
);

create index if not exists idx_tx_date   on public.transactions (transaction_date desc);
create index if not exists idx_tx_status on public.transactions (status);
create index if not exists idx_tx_type   on public.transactions (type);

-- ─── income_records 表（收入专表） ───
create table if not exists public.income_records (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz not null default now(),
  income_date     date not null default current_date,
  amount          numeric(10,2) not null check (amount > 0),
  category        text not null check (category in ('salary','bonus','freelance','investment','reimbursement','other')),
  source_name     text,
  is_recurring    boolean default false,
  recurring_day   int check (recurring_day between 1 and 31),
  note            text,
  user_id         uuid
);

create index if not exists idx_inc_date on public.income_records (income_date desc);

-- ─── budgets 表（V1.1 预算，可先建好） ───
create table if not exists public.budgets (
  id              uuid primary key default uuid_generate_v4(),
  year_month      text not null,         -- 格式 YYYY-MM
  category        text,                  -- null 表示总预算
  budget_amount   numeric(10,2) not null check (budget_amount > 0),
  user_id         uuid,
  unique (year_month, category, user_id)
);

-- ─── RLS：单用户阶段先全开，避免 anon key 被拒 ───
-- 上线多用户后再改为 user_id = auth.uid() 的策略
alter table public.transactions    enable row level security;
alter table public.income_records  enable row level security;
alter table public.budgets         enable row level security;

drop policy if exists "allow_all_tx"     on public.transactions;
drop policy if exists "allow_all_inc"    on public.income_records;
drop policy if exists "allow_all_budget" on public.budgets;

create policy "allow_all_tx"     on public.transactions    for all using (true) with check (true);
create policy "allow_all_inc"    on public.income_records  for all using (true) with check (true);
create policy "allow_all_budget" on public.budgets         for all using (true) with check (true);
