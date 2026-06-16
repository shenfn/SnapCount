-- Split screenshot and camera-photo vision settings.
-- Screenshots keep the fast path by default; photos can use a higher-quality model.

alter table public.user_configs
  add column if not exists screenshot_vision_primary text not null default 'auto',
  add column if not exists photo_vision_primary text not null default 'qwen',
  add column if not exists qwen_screenshot_model text not null default 'qwen3.6-flash',
  add column if not exists qwen_photo_model text not null default 'qwen3.7-plus',
  add column if not exists qwen_screenshot_enable_thinking boolean not null default false,
  add column if not exists qwen_photo_enable_thinking boolean not null default true;

update public.user_configs
   set screenshot_vision_primary = vision_primary
 where vision_primary <> 'auto'
   and screenshot_vision_primary = 'auto';

alter table public.user_configs
  drop constraint if exists user_configs_screenshot_vision_primary_check;

alter table public.user_configs
  add constraint user_configs_screenshot_vision_primary_check
  check (screenshot_vision_primary in ('auto','moonshot','qwen','mimo','relay'));

alter table public.user_configs
  drop constraint if exists user_configs_photo_vision_primary_check;

alter table public.user_configs
  add constraint user_configs_photo_vision_primary_check
  check (photo_vision_primary in ('auto','moonshot','qwen','mimo','relay'));

alter table public.user_configs
  drop constraint if exists user_configs_qwen_screenshot_model_check;

alter table public.user_configs
  add constraint user_configs_qwen_screenshot_model_check
  check (length(trim(qwen_screenshot_model)) > 0);

alter table public.user_configs
  drop constraint if exists user_configs_qwen_photo_model_check;

alter table public.user_configs
  add constraint user_configs_qwen_photo_model_check
  check (length(trim(qwen_photo_model)) > 0);

comment on column public.user_configs.screenshot_vision_primary is
  'Screenshot/account/bill recognition provider preference. auto follows platform defaults.';

comment on column public.user_configs.photo_vision_primary is
  'Camera photo recognition provider preference. Defaults to qwen for higher-quality food/photo extraction.';

comment on column public.user_configs.qwen_screenshot_model is
  'Qwen model for screenshot recognition. Default qwen3.6-flash favors speed.';

comment on column public.user_configs.qwen_photo_model is
  'Qwen model for camera-photo recognition. Default qwen3.7-plus favors data quality.';

comment on column public.user_configs.qwen_screenshot_enable_thinking is
  'Whether Qwen thinking mode is enabled for screenshot recognition.';

comment on column public.user_configs.qwen_photo_enable_thinking is
  'Whether Qwen thinking mode is enabled for camera-photo recognition.';
