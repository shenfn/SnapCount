alter table public.user_configs
  alter column qwen_photo_model set default 'qwen3.6-flash',
  alter column qwen_photo_enable_thinking set default false;

update public.user_configs
   set qwen_photo_model = 'qwen3.6-flash',
       qwen_photo_enable_thinking = false
 where qwen_photo_model = 'qwen3.7-plus'
   and qwen_photo_enable_thinking = true;

comment on column public.user_configs.qwen_photo_model is
  'Qwen model for camera-photo recognition. Default qwen3.6-flash favors bounded upload latency.';

comment on column public.user_configs.qwen_photo_enable_thinking is
  'Whether Qwen thinking mode is enabled for photo recognition. Defaults off to keep uploads responsive.';
