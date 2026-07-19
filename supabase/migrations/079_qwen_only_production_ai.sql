-- Production AI contract: only Alibaba Cloud Bailian Qwen is available.
-- Keep auto as a route/model policy, not as a cross-provider fallback.

update public.user_configs
   set vision_primary = case when vision_primary = 'qwen' then 'qwen' else 'auto' end,
       screenshot_vision_primary = case when screenshot_vision_primary = 'qwen' then 'qwen' else 'auto' end,
       photo_vision_primary = case when photo_vision_primary = 'auto' then 'auto' else 'qwen' end,
       ai_insight_provider = case when ai_insight_provider = 'qwen' then 'qwen' else 'auto' end,
       qwen_screenshot_model = case
         when qwen_screenshot_model in ('qwen3.6-flash', 'qwen3.7-plus') then qwen_screenshot_model
         else 'qwen3.6-flash'
       end,
       qwen_photo_model = case
         when qwen_photo_model in ('qwen3.6-flash', 'qwen3.7-plus') then qwen_photo_model
         else 'qwen3.6-flash'
       end;

alter table public.user_configs
  alter column vision_primary set default 'auto',
  alter column screenshot_vision_primary set default 'auto',
  alter column photo_vision_primary set default 'qwen',
  alter column qwen_screenshot_model set default 'qwen3.6-flash',
  alter column qwen_photo_model set default 'qwen3.6-flash',
  alter column qwen_screenshot_enable_thinking set default false,
  alter column qwen_photo_enable_thinking set default false,
  alter column ai_insight_provider set default 'auto';

alter table public.user_configs
  drop constraint if exists user_configs_vision_primary_check,
  drop constraint if exists user_configs_screenshot_vision_primary_check,
  drop constraint if exists user_configs_photo_vision_primary_check,
  drop constraint if exists user_configs_qwen_screenshot_model_check,
  drop constraint if exists user_configs_qwen_photo_model_check,
  drop constraint if exists user_configs_ai_insight_provider_check;

alter table public.user_configs
  add constraint user_configs_vision_primary_check
    check (vision_primary in ('auto', 'qwen')),
  add constraint user_configs_screenshot_vision_primary_check
    check (screenshot_vision_primary in ('auto', 'qwen')),
  add constraint user_configs_photo_vision_primary_check
    check (photo_vision_primary in ('auto', 'qwen')),
  add constraint user_configs_qwen_screenshot_model_check
    check (qwen_screenshot_model in ('qwen3.6-flash', 'qwen3.7-plus')),
  add constraint user_configs_qwen_photo_model_check
    check (qwen_photo_model in ('qwen3.6-flash', 'qwen3.7-plus')),
  add constraint user_configs_ai_insight_provider_check
    check (ai_insight_provider in ('auto', 'qwen'));

comment on column public.user_configs.vision_primary is
  'Legacy recognition route. auto and qwen both use the production Qwen provider.';
comment on column public.user_configs.screenshot_vision_primary is
  'Screenshot recognition route. auto selects the configured Qwen screenshot model.';
comment on column public.user_configs.photo_vision_primary is
  'Photo recognition route. auto selects the configured Qwen photo model.';
comment on column public.user_configs.ai_insight_provider is
  'AI insight route. auto and qwen both use Alibaba Cloud Bailian Qwen.';
