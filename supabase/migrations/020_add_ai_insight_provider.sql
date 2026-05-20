alter table public.user_configs
  add column if not exists ai_insight_provider text not null default 'auto';

alter table public.user_configs
  drop constraint if exists user_configs_ai_insight_provider_check;

alter table public.user_configs
  add constraint user_configs_ai_insight_provider_check
  check (ai_insight_provider in ('auto','moonshot','relay'));

comment on column public.user_configs.ai_insight_provider is
  'AI 联动分析模型偏好：auto=跟随平台默认；moonshot=强制 Moonshot；relay=强制自建 OpenAI 兼容中转站';
