alter table public.user_configs
  add column if not exists ai_logs_enabled boolean not null default true,
  add column if not exists keep_source_images boolean not null default true;

comment on column public.user_configs.ai_logs_enabled is
  'Whether to retain AI recognition logs for debugging and prompt optimization.';

comment on column public.user_configs.keep_source_images is
  'Whether to retain uploaded source images for replay and re-recognition.';
