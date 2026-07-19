-- Normalize production AI settings without rejecting values written by older clients.
-- The Qwen-only constraints remain deferred until those clients are retired.

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

comment on column public.user_configs.vision_primary is
  'Legacy recognition route. auto and qwen both use the production Qwen provider.';
comment on column public.user_configs.screenshot_vision_primary is
  'Screenshot recognition route. auto selects the configured Qwen screenshot model.';
comment on column public.user_configs.photo_vision_primary is
  'Photo recognition route. auto selects the configured Qwen photo model.';
comment on column public.user_configs.ai_insight_provider is
  'AI insight route. auto and qwen both use Alibaba Cloud Bailian Qwen.';
