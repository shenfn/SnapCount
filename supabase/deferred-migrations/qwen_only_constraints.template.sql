-- 延后执行模板：所有旧客户端退役后，用当时的新时间戳创建正式迁移。

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
