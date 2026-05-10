-- ════════════════════════════════════════════════════════════════════
-- 阶段 1C：用户级 AI 引擎偏好
-- 目的：让用户在设置页自助选择 Vision Provider
-- 取值：auto = 跟随 VISION_PRIMARY env；其它 = 强制使用指定 provider
-- ════════════════════════════════════════════════════════════════════

alter table public.user_configs
  add column if not exists vision_primary text not null default 'auto'
    check (vision_primary in ('auto','moonshot','qwen','mimo'));

comment on column public.user_configs.vision_primary is
  'AI 识别引擎偏好：auto=跟随平台默认，其它=用户强制指定 provider';
