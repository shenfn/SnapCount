alter table public.user_configs
  drop constraint if exists user_configs_vision_primary_check;

alter table public.user_configs
  add constraint user_configs_vision_primary_check
  check (vision_primary in ('auto','moonshot','qwen','mimo','relay'));
