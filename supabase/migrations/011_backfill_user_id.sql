-- ════════════════════════════════════════════════════════════════════
-- 旧数据 user_id 回填 + RLS 收紧
-- 目的：邀请第二个真实用户前必须执行
-- 风险：破坏性更新，请先在 Supabase 控制台备份相关表
-- 前置条件：auth.users 中只有你一个种子账号
-- 操作方式：Supabase Dashboard → SQL Editor → 整段粘贴 Run
-- ════════════════════════════════════════════════════════════════════

-- 1. 回填旧记录 user_id
--    仅当 auth.users 中只有 1 个用户时自动执行，避免误伤
do $$
declare
  seed_uid uuid;
  user_count int;
  affected int;
begin
  select count(*) into user_count from auth.users;

  if user_count <> 1 then
    raise notice '跳过回填：auth.users 当前有 % 个用户，需手动核对后执行 update', user_count;
    return;
  end if;

  select id into seed_uid from auth.users limit 1;
  raise notice '识别到种子用户 user_id = %，开始回填...', seed_uid;

  update public.transactions          set user_id = seed_uid where user_id is null;
  get diagnostics affected = row_count; raise notice '  transactions 回填 % 行', affected;

  update public.income_records        set user_id = seed_uid where user_id is null;
  get diagnostics affected = row_count; raise notice '  income_records 回填 % 行', affected;

  update public.budgets               set user_id = seed_uid where user_id is null;
  get diagnostics affected = row_count; raise notice '  budgets 回填 % 行', affected;

  update public.staging_records       set user_id = seed_uid where user_id is null;
  get diagnostics affected = row_count; raise notice '  staging_records 回填 % 行', affected;

  update public.data_records          set user_id = seed_uid where user_id is null;
  get diagnostics affected = row_count; raise notice '  data_records 回填 % 行', affected;

  update public.ai_recognition_logs   set user_id = seed_uid where user_id is null;
  get diagnostics affected = row_count; raise notice '  ai_recognition_logs 回填 % 行', affected;

  update public.user_routing_feedback set user_id = seed_uid where user_id is null;
  get diagnostics affected = row_count; raise notice '  user_routing_feedback 回填 % 行', affected;

  -- data_domains: is_system=true 的系统域保持 user_id=null（共享给所有用户）
  --              其余 user_id=null 的视作种子用户私有
  update public.data_domains
     set user_id = seed_uid
   where user_id is null and is_system = false;
  get diagnostics affected = row_count; raise notice '  data_domains 私有域回填 % 行', affected;
end $$;

-- 2. 收紧 RLS：移除过渡期的 user_id IS NULL 容忍
--    执行前请确认上一步回填成功

drop policy if exists "tx_user_access" on public.transactions;
create policy "tx_user_access" on public.transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "inc_user_access" on public.income_records;
create policy "inc_user_access" on public.income_records
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "budget_user_access" on public.budgets;
create policy "budget_user_access" on public.budgets
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "staging_user_access" on public.staging_records;
create policy "staging_user_access" on public.staging_records
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "dr_user_access" on public.data_records;
create policy "dr_user_access" on public.data_records
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "ai_logs_user_access" on public.ai_recognition_logs;
create policy "ai_logs_user_access" on public.ai_recognition_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "routing_fb_user_access" on public.user_routing_feedback;
create policy "routing_fb_user_access" on public.user_routing_feedback
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- data_domains: 系统域 (user_id IS NULL AND is_system) 仍对所有人可读，
--              用户私有域只能本人读写
drop policy if exists "domains_user_access" on public.data_domains;
drop policy if exists "domains_user_write"  on public.data_domains;

create policy "domains_user_select" on public.data_domains
  for select using (
    is_system = true
    or auth.uid() = user_id
  );

create policy "domains_user_write" on public.data_domains
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 3. 验证（可选）：列出仍存在 user_id IS NULL 的核心表行数
--    回填完成后这些查询应全部返回 0
-- select 'transactions'        as tbl, count(*) from public.transactions          where user_id is null
-- union all select 'income_records',         count(*) from public.income_records  where user_id is null
-- union all select 'staging_records',        count(*) from public.staging_records where user_id is null
-- union all select 'data_records',           count(*) from public.data_records    where user_id is null
-- union all select 'ai_recognition_logs',    count(*) from public.ai_recognition_logs where user_id is null
-- union all select 'data_domains_private',   count(*) from public.data_domains    where user_id is null and is_system = false;
