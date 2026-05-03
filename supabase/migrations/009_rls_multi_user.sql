-- ════════════════════════════════════════════════════════════════════
-- 多用户 RLS 收紧
-- 目的：从 using (true) 迁移到 auth.uid() = user_id
-- 过渡期允许 user_id IS NULL 保证旧数据可访问
-- ════════════════════════════════════════════════════════════════════

-- 1. 确保所有表有 user_id 列（大部分已在建表时加了）
do $$
begin
  if not exists (select 1 from information_schema.columns
    where table_name = 'transactions' and column_name = 'user_id') then
    alter table public.transactions add column user_id uuid references auth.users(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns
    where table_name = 'income_records' and column_name = 'user_id') then
    alter table public.income_records add column user_id uuid references auth.users(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns
    where table_name = 'data_records' and column_name = 'user_id') then
    alter table public.data_records add column user_id uuid references auth.users(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns
    where table_name = 'data_domains' and column_name = 'user_id') then
    alter table public.data_domains add column user_id uuid references auth.users(id) on delete set null;
  end if;
end $$;

-- 2. 替换所有核心表的 RLS 策略为过渡策略
--    过渡期: auth.uid() = user_id OR user_id IS NULL

-- transactions
drop policy if exists "allow_all_tx" on public.transactions;
create policy "tx_user_access" on public.transactions
  for all using (auth.uid() = user_id or user_id is null)
  with check (auth.uid() = user_id);

-- income_records
drop policy if exists "allow_all_inc" on public.income_records;
create policy "inc_user_access" on public.income_records
  for all using (auth.uid() = user_id or user_id is null)
  with check (auth.uid() = user_id);

-- budgets
drop policy if exists "allow_all_budget" on public.budgets;
create policy "budget_user_access" on public.budgets
  for all using (auth.uid() = user_id or user_id is null)
  with check (auth.uid() = user_id);

-- staging_records
drop policy if exists "allow_all_staging" on public.staging_records;
create policy "staging_user_access" on public.staging_records
  for all using (auth.uid() = user_id or user_id is null)
  with check (auth.uid() = user_id);

-- data_records
drop policy if exists "allow_all_data_records" on public.data_records;
create policy "dr_user_access" on public.data_records
  for all using (auth.uid() = user_id or user_id is null)
  with check (auth.uid() = user_id);

-- data_domains（系统域 is_system=true 对所有用户可见）
drop policy if exists "allow_all_domains" on public.data_domains;
create policy "domains_user_access" on public.data_domains
  for select using (auth.uid() = user_id or user_id is null or is_system = true)
  with check (auth.uid() = user_id);

-- ai_recognition_logs
drop policy if exists "allow_all_ai_logs" on public.ai_recognition_logs;
create policy "ai_logs_user_access" on public.ai_recognition_logs
  for all using (auth.uid() = user_id or user_id is null)
  with check (auth.uid() = user_id);

-- user_routing_feedback
drop policy if exists "allow_all_routing_feedback" on public.user_routing_feedback;
create policy "routing_fb_user_access" on public.user_routing_feedback
  for all using (auth.uid() = user_id or user_id is null)
  with check (auth.uid() = user_id);

-- user_configs (already set correctly in 008, but ensure)
drop policy if exists "user_configs_access" on public.user_configs;
create policy "user_configs_access" on public.user_configs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 3. 注释：过渡期结束后（旧数据迁移完成），移除 user_id IS NULL 条件
--    执行: create policy ... using (auth.uid() = user_id) with check (auth.uid() = user_id);
