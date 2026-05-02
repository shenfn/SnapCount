-- ════════════════════════════════════════════════════════════════════
-- 种子用户验证前 · 用户配置与额度表
-- 目的：支持多用户隔离前的用户配置存储
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.user_configs (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  user_id         uuid not null unique references auth.users(id) on delete cascade,
  plan            text not null default 'seed' check (plan in ('seed','free','pro')),
  monthly_quota   integer not null default 100,       -- 每月识别次数上限
  daily_quota     integer not null default 30,         -- 每日识别次数上限
  used_this_month integer not null default 0,
  used_today      integer not null default 0,
  last_reset_at   timestamptz,
  is_active       boolean not null default true,
  upload_token    uuid default uuid_generate_v4(),    -- 快捷指令上传 Token
  notes           text
);

create index if not exists idx_user_configs_user on public.user_configs (user_id);

alter table public.user_configs enable row level security;

drop policy if exists "user_configs_access" on public.user_configs;

create policy "user_configs_access" on public.user_configs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 给 auth.users 新增记录的触发器函数（可选，也支持应用层插入）
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.user_configs (user_id, plan, monthly_quota, daily_quota, is_active)
  values (new.id, 'seed', 100, 30, true)
  on conflict (user_id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

-- 如果触发器已存在则替换
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
