-- ════════════════════════════════════════════════════════════════════
-- 修复 handle_new_user 触发器函数
-- 背景：
--   008 创建 handle_new_user 时是"insert into public.user_configs"；
--   051 在做安全加固（设置 search_path）时错误地把函数体改成了
--   "insert into public.profiles"，但项目里从未创建过 profiles 表，
--   导致每次新用户注册都因为触发器失败而回滚，前端报：
--     "Database error saving new user"
--
-- 本迁移：
--   1. 把 handle_new_user 函数体改回往 public.user_configs 插入；
--   2. 同步保留 051 的安全配置（security definer + 固定 search_path + 收回 anon 执行权限）；
--   3. 重新声明触发器，确保 on_auth_user_created 仍然挂在 auth.users 上。
-- 幂等：可重复执行。
-- ════════════════════════════════════════════════════════════════════

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 与 008 的初始默认值保持一致：seed 计划，每月 100、每日 30 次额度
  insert into public.user_configs (user_id, plan, monthly_quota, daily_quota, is_active)
  values (new.id, 'seed', 100, 30, true)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- 与 051 保持一致：禁止 anon 角色直接调用此 SECURITY DEFINER 函数，
-- 只允许通过 auth.users 触发器路径间接执行。
revoke execute on function public.handle_new_user() from anon;

-- 重建触发器，确保不会因旧版函数遗留而失效
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
